import AudioToolbox
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum ScreenRecordingFormat: String, CaseIterable {
    case mp4
    case gif

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .mp4: return L10n.recordingFormatMP4
        case .gif: return L10n.recordingFormatGIF
        }
    }
}

enum RecordingSavePreference: String, CaseIterable {
    case manual
    case gif
    case mp4

    var displayName: String {
        switch self {
        case .manual: return L10n.recordingFormatManual
        case .gif: return L10n.recordingFormatGIF
        case .mp4: return L10n.recordingFormatMP4
        }
    }

    var format: ScreenRecordingFormat? {
        switch self {
        case .manual: return nil
        case .gif: return .gif
        case .mp4: return .mp4
        }
    }
}

typealias RecordingProgressCallback = (_ seconds: Int) -> Void
typealias RecordingCompletionCallback = (_ url: URL?, _ error: Error?) -> Void

/// Audio source options the engine can capture alongside video. Both audio
/// tracks are always created so the HUD toggles work live mid-recording;
/// a track that never receives a sample is dropped from the output file.
struct RecordingAudioOptions {
    let systemAudio: Bool
    let microphone: Bool
    /// UID of the CoreAudio input device to use for the microphone. nil means
    /// the system default input device.
    var microphoneDeviceUID: String? = nil

    static let none = RecordingAudioOptions(systemAudio: false, microphone: false)
}

final class RecordingEngine: NSObject {
    enum State {
        case idle
        case recording
        case paused
        case stopping
    }

    private(set) var state: State = .idle

    private let fps: Int
    private let recordingQueue = DispatchQueue(label: "capcap.recording")
    private let audioQueue = DispatchQueue(label: "capcap.recording.audio")

    private var screen: NSScreen?
    private var sourceRect: CGRect = .zero
    private var stream: SCStream?
    private var streamOutput: RecordingStreamOutput?
    private var outputURL: URL?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var sessionStarted = false
    /// Session anchor PTS — the timeline origin silence backfill starts from.
    private var referenceAnchor: CMTime?
    private var hasWrittenSystemAudio = false
    private var hasWrittenMicrophone = false
    private var audioOptions: RecordingAudioOptions = .none

    private var microphoneRecorder: MicrophoneRecorder?
    /// The writer has a mic input but the recorder isn't running (mic was off
    /// at start) — a live HUD enable starts the recorder lazily.
    private var microphoneTrackArmed = false
    private let systemAudioMuted = LockedFlag()

    /// Gate system-audio samples mid-recording so HUD toggles apply live.
    func setSystemAudioMuted(_ muted: Bool) {
        systemAudioMuted.set(muted)
    }

    /// Mute/unmute the mic mid-recording. When the recording was started with
    /// an armed mic track but a stopped recorder, unmuting starts capture now.
    func setMicrophoneMuted(_ muted: Bool) {
        if let recorder = microphoneRecorder {
            recorder.muted.set(muted)
        } else if !muted, microphoneTrackArmed, state == .recording {
            startMicrophoneRecording()
        }
    }

    private var hasWrittenFrame = false

    private var progressTimer: Timer?
    private var elapsedSeconds = 0
    private var pauseStartTime: Date?
    private var totalPausedDuration: TimeInterval = 0

    var onProgress: RecordingProgressCallback?
    var onCompletion: RecordingCompletionCallback?
    var onPauseChanged: ((Bool) -> Void)?

    init(fps: Int = 30) {
        self.fps = fps
    }

    func startRecording(
        rect: NSRect,
        screen: NSScreen,
        excludeWindowNumbers: [CGWindowID] = [],
        audioOptions: RecordingAudioOptions = .none
    ) {
        guard state == .idle else { return }
        guard rect.width > 0, rect.height > 0 else {
            fail(RecordingError.invalidSelection)
            return
        }

        self.state = .recording
        self.screen = screen
        self.totalPausedDuration = 0
        self.pauseStartTime = nil
        self.hasWrittenFrame = false
        self.hasWrittenSystemAudio = false
        self.hasWrittenMicrophone = false
        self.microphoneTrackArmed = false
        // Set before the stream starts: SCStream delivers audio immediately
        // after startCapture, so arming the gate here prevents an initial
        // audio blip when system audio starts muted.
        self.systemAudioMuted.set(!audioOptions.systemAudio)
        self.audioOptions = audioOptions

        sourceRect = CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        Task {
            await beginCapture(
                screen: screen,
                excludeWindowNumbers: excludeWindowNumbers,
                audioOptions: audioOptions
            )
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        state = .paused
        pauseStartTime = Date()
        microphoneRecorder?.pause()
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
            self?.onPauseChanged?(true)
        }
    }

    func resumeRecording() {
        guard state == .paused else { return }
        if let pauseStartTime {
            totalPausedDuration += Date().timeIntervalSince(pauseStartTime)
            self.pauseStartTime = nil
        }
        state = .recording
        microphoneRecorder?.resume()
        DispatchQueue.main.async { [weak self] in
            self?.startProgressTimer()
            self?.onPauseChanged?(false)
        }
    }

    func stopRecording() {
        guard state == .recording || state == .paused else { return }
        state = .stopping
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
        Task {
            await finalizeCapture()
        }
    }

    func cancelRecording() {
        guard state == .recording || state == .paused else { return }
        state = .stopping
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
        Task {
            await cancelCapture()
        }
    }

    private func beginCapture(
        screen: NSScreen,
        excludeWindowNumbers: [CGWindowID],
        audioOptions: RecordingAudioOptions
    ) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard state == .recording else { return }

            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
                fail(RecordingError.noDisplay)
                return
            }

            let excludedWindows = excludeWindowNumbers.compactMap { windowID in
                content.windows.first(where: { $0.windowID == windowID })
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

            let scale = max(screen.backingScaleFactor, 1)
            let (pixelWidth, pixelHeight) = VideoEncodingSettings.evenDimensions(
                width: sourceRect.width * scale,
                height: sourceRect.height * scale
            )

            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            config.width = pixelWidth
            config.height = pixelHeight
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.showsCursor = true
            // Always capture system audio: samples are gated on the mute flag,
            // so the HUD toggle can enable it mid-recording. SCStream requires
            // explicit sampleRate/channelCount when audio capture is on.
            config.capturesAudio = true
            config.sampleRate = 44_100
            config.channelCount = 2
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.scalesToFit = false
            if #available(macOS 14.0, *) {
                config.colorSpaceName = CGColorSpace.sRGB
            }

            let outputURL = Self.makeOutputURL()
            self.outputURL = outputURL
            try prepareWriter(
                url: outputURL,
                width: pixelWidth,
                height: pixelHeight
            )
            guard state == .recording else {
                cleanupTemporaryOutput()
                return
            }

            let output = RecordingStreamOutput()
            output.onFrame = { [weak self] pixelBuffer, presentationTime in
                self?.handleFrame(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
            }
            output.onAudioSampleBuffer = { [weak self] sampleBuffer in
                self?.handleSystemAudioSampleBuffer(sampleBuffer)
            }
            output.onStopped = { [weak self] in
                self?.stopRecording()
            }
            streamOutput = output

            let stream = SCStream(filter: filter, configuration: config, delegate: output)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: recordingQueue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
            guard state == .recording else {
                cleanupTemporaryOutput()
                return
            }
            try await stream.startCapture()
            self.stream = stream

            if audioOptions.microphone {
                startMicrophoneRecording()
            } else {
                microphoneTrackArmed = true
            }

            DispatchQueue.main.async { [weak self] in
                self?.elapsedSeconds = 0
                self?.onProgress?(0)
                self?.startProgressTimer()
            }
        } catch {
            fail(error)
        }
    }

    private func prepareWriter(
        url: URL,
        width: Int,
        height: Int
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: VideoEncodingSettings.outputSettings(width: width, height: height, fps: fps)
        )
        input.expectsMediaDataInRealTime = true

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.canAdd(input) else { throw RecordingError.writerSetupFailed }
        writer.add(input)

        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: RecordingAudioSettings.systemAudioOutputSettings
        )
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(audioInput) else { throw RecordingError.writerSetupFailed }
        writer.add(audioInput)
        self.systemAudioInput = audioInput

        let micInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: RecordingAudioSettings.microphoneOutputSettings
        )
        micInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(micInput) else { throw RecordingError.writerSetupFailed }
        writer.add(micInput)
        self.microphoneInput = micInput

        writer.startWriting()

        self.assetWriter = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.sessionStarted = false
        self.referenceAnchor = nil
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard state == .recording else { return }
        writeMP4Frame(pixelBuffer: pixelBuffer, presentationTime: adjustedTime(presentationTime))
    }

    private func writeMP4Frame(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let writer = assetWriter,
              let input = videoInput,
              let adaptor = adaptor,
              input.isReadyForMoreMediaData
        else { return }

        if !sessionStarted {
            startWriterSession(at: presentationTime)
        }

        if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            hasWrittenFrame = true
        }
    }

    private func handleSystemAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording, let input = systemAudioInput else { return }

        let presentationTime = adjustedTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if !sessionStarted {
            startWriterSession(at: presentationTime)
        }

        // AVAssetWriter compresses PTS gaps in audio tracks, so a muted span
        // must be filled with silence or later audio shifts out of sync.
        if systemAudioMuted.get() {
            // Before the first real sample, dropping keeps the track empty so
            // it is omitted from the file entirely.
            guard hasWrittenSystemAudio, input.isReadyForMoreMediaData else { return }
            appendSilence(into: input, like: sampleBuffer, from: presentationTime, duration: CMSampleBufferGetDuration(sampleBuffer))
            return
        }

        guard input.isReadyForMoreMediaData else { return }
        if !hasWrittenSystemAudio {
            appendSilence(into: input, like: sampleBuffer, from: referenceAnchor, to: presentationTime)
            hasWrittenSystemAudio = true
        }
        guard let restamped = restamp(sampleBuffer, to: presentationTime) else { return }
        _ = input.append(restamped)
    }

    private func handleMicrophoneSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording, let input = microphoneInput else { return }

        let presentationTime = adjustedTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if !sessionStarted {
            startWriterSession(at: presentationTime)
        }

        if microphoneRecorder?.muted.get() == true {
            // The recorder keeps delivering zeroed buffers while muted so the
            // track stays continuous; before the first real sample, dropping
            // keeps the track out of the file entirely.
            guard hasWrittenMicrophone, input.isReadyForMoreMediaData else { return }
            guard let restamped = restamp(sampleBuffer, to: presentationTime) else { return }
            _ = input.append(restamped)
            return
        }

        guard input.isReadyForMoreMediaData else { return }
        if !hasWrittenMicrophone {
            appendSilence(into: input, like: sampleBuffer, from: referenceAnchor, to: presentationTime)
            hasWrittenMicrophone = true
        }
        guard let restamped = restamp(sampleBuffer, to: presentationTime) else { return }
        _ = input.append(restamped)
    }

    private func appendSilence(
        into input: AVAssetWriterInput,
        like reference: CMSampleBuffer,
        from start: CMTime,
        duration: CMTime
    ) {
        appendSilence(into: input, like: reference, from: start, to: CMTimeAdd(start, duration))
    }

    /// Writes zeroed PCM covering [start, end), chunked like the reference
    /// sample so the encoder never sees a format change mid-track. Keeps the
    /// audio track continuous across muted spans and live enables —
    /// AVAssetWriter compresses PTS gaps, which would desync later audio.
    private func appendSilence(
        into input: AVAssetWriterInput,
        like reference: CMSampleBuffer,
        from start: CMTime?,
        to end: CMTime
    ) {
        guard let start, start.isValid, end.isValid, CMTimeCompare(start, end) < 0,
              let formatDescription = CMSampleBufferGetFormatDescription(reference),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              asbd.mSampleRate > 0
        else { return }

        let framesPerChunk = max(1, CMSampleBufferGetNumSamples(reference))
        let chunkDuration = CMTime(value: CMTimeValue(framesPerChunk), timescale: CMTimeScale(asbd.mSampleRate))
        var cursor = start
        while CMTimeCompare(cursor, end) < 0, input.isReadyForMoreMediaData {
            guard let silent = Self.makeSilence(
                like: reference, at: cursor,
                formatDescription: formatDescription, asbd: asbd
            ) else { break }
            _ = input.append(silent)
            cursor = CMTimeAdd(cursor, chunkDuration)
        }
    }

    private static func makeSilence(
        like reference: CMSampleBuffer,
        at pts: CMTime,
        formatDescription: CMAudioFormatDescription,
        asbd: AudioStreamBasicDescription
    ) -> CMSampleBuffer? {
        guard let sourceBlock = CMSampleBufferGetDataBuffer(reference) else { return nil }
        let length = CMBlockBufferGetDataLength(sourceBlock)
        guard length > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        guard CMBlockBufferFillDataBytes(
            with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length
        ) == kCMBlockBufferNoErr else { return nil }

        let numSamples = CMSampleBufferGetNumSamples(reference)
        var needed = CMItemCount()
        CMSampleBufferGetSampleSizeArray(reference, entryCount: 0, arrayToFill: nil, entriesNeededOut: &needed)
        var sampleSizes = [Int](repeating: 0, count: max(1, Int(needed)))
        if needed > 0 {
            CMSampleBufferGetSampleSizeArray(reference, entryCount: needed, arrayToFill: &sampleSizes, entriesNeededOut: nil)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer,
            formatDescription: formatDescription, sampleCount: numSamples,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: needed, sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }

    private func startWriterSession(at time: CMTime) {
        guard let writer = assetWriter, !sessionStarted else { return }
        writer.startSession(atSourceTime: time)
        referenceAnchor = time
        sessionStarted = true
    }

    /// Re-stamps a sample buffer's PTS onto the pause-adjusted timeline so
    /// audio and video stay continuous across pause/resume.
    private func restamp(_ sampleBuffer: CMSampleBuffer, to presentationTime: CMTime) -> CMSampleBuffer? {
        var timingCount = CMItemCount()
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        )
        let originalDuration: CMTime
        if timingCount > 0 {
            var originalTiming = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: Int(timingCount))
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: timingCount,
                arrayToFill: &originalTiming,
                entriesNeededOut: &timingCount
            )
            originalDuration = originalTiming.first?.duration ?? .invalid
        } else {
            originalDuration = .invalid
        }

        var newTiming = CMSampleTimingInfo(
            duration: originalDuration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &newTiming,
            sampleBufferOut: &newBuffer
        )
        guard status == noErr else { return nil }
        return newBuffer
    }

    private func startMicrophoneRecording() {
        let recorder = MicrophoneRecorder(deviceUID: audioOptions.microphoneDeviceUID)
        recorder.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handleMicrophoneSampleBuffer(sampleBuffer)
        }
        // Assign before start(): engine spin-up can take ~1s, and HUD mutes
        // landing in that window would otherwise be lost.
        self.microphoneRecorder = recorder
        _ = recorder.start()
    }

    private func adjustedTime(_ time: CMTime) -> CMTime {
        guard totalPausedDuration > 0 else { return time }
        return CMTimeSubtract(
            time,
            CMTimeMakeWithSeconds(totalPausedDuration, preferredTimescale: time.timescale)
        )
    }

    private func finalizeCapture() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        streamOutput = nil
        microphoneRecorder?.stop()
        microphoneRecorder = nil

        await finalizeMP4()
    }

    private func cancelCapture() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        streamOutput = nil
        microphoneRecorder?.stop()
        microphoneRecorder = nil
        cleanupTemporaryOutput()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.onCompletion?(nil, nil)
        }
    }

    private func finalizeMP4() async {
        guard let writer = assetWriter, let input = videoInput else {
            fail(RecordingError.writerSetupFailed)
            return
        }

        input.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()

        assetWriter = nil
        videoInput = nil
        adaptor = nil
        systemAudioInput = nil
        microphoneInput = nil

        if let error = writer.error {
            fail(error)
        } else if !hasWrittenFrame {
            fail(RecordingError.noFrames)
        } else {
            succeed()
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds += 1
            self.onProgress?(self.elapsedSeconds)
        }
    }

    private func succeed() {
        let url = outputURL
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.onCompletion?(url, nil)
        }
    }

    private func fail(_ error: Error) {
        cleanupTemporaryOutput()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            self.state = .idle
            self.onCompletion?(nil, error)
        }
    }

    private func cleanupTemporaryOutput() {
        let url = outputURL
        assetWriter?.cancelWriting()
        assetWriter = nil
        videoInput = nil
        adaptor = nil
        systemAudioInput = nil
        microphoneInput = nil
        outputURL = nil
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = formatter.string(from: Date())
        let token = ProcessInfo.processInfo.globallyUniqueString
            .replacingOccurrences(of: "/", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("capcap-recording-\(date)-\(token).mp4")
    }

    enum RecordingError: LocalizedError {
        case invalidSelection
        case noDisplay
        case noFrames
        case writerSetupFailed

        var errorDescription: String? {
            switch self {
            case .invalidSelection: return "The selected recording area is empty"
            case .noDisplay: return "Could not find the selected display"
            case .noFrames: return "No video frames were recorded"
            case .writerSetupFailed: return "Could not prepare the recording writer"
            }
        }
    }
}

private final class RecordingStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onStopped: (() -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
            onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        case .audio:
            guard sampleBuffer.numSamples > 0 else { return }
            onAudioSampleBuffer?(sampleBuffer)
        case .microphone:
            // SCStream doesn't capture microphone directly — capcap routes it
            // through AVAudioEngine via MicrophoneRecorder instead.
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onStopped?()
        }
    }
}

/// Captures microphone audio via AVAudioEngine (SCStream has no mic capture
/// on macOS) and converts PCM buffers into CMSampleBuffers for the writer.
private final class MicrophoneRecorder {
    let muted = LockedFlag()

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let deviceUID: String?
    private var paused = false

    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    init(deviceUID: String?) {
        self.deviceUID = deviceUID
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44_100,
            channels: 1,
            interleaved: true
        )!
    }

    /// Returns false if the mic can't start; the recording continues without
    /// a mic track, so callers should not treat this as fatal.
    func start() -> Bool {
        // Select the user's chosen device BEFORE querying the input format —
        // the format depends on the device.
        if let deviceUID, let deviceID = AudioInputDevices.deviceID(forUID: deviceUID) {
            var id = deviceID
            // Best-effort: on failure the system default input is used.
            _ = AudioUnitSetProperty(
                engine.inputNode.audioUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioObjectID>.size)
            )
        }

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return false }
        self.converter = converter

        do {
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.handle(buffer: buffer)
            }
            try engine.start()
            return true
        } catch {
            // Mic denied or in use: continue without microphone samples.
            return false
        }
    }

    func pause() {
        paused = true
        engine.pause()
    }

    func resume() {
        guard paused else { return }
        do {
            try engine.start()
            paused = false
        } catch {
            // Resume best-effort: leave paused state if restart fails.
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        paused = false
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        guard !paused else { return }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        )
        guard frameCapacity > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity)
        else { return }

        var conversionError: NSError?
        var supplied = false
        guard let converter else { return }
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil else { return }

        if muted.get() {
            // Zero the PCM but keep delivering: the engine needs the cadence
            // to hold the track timeline (AVAssetWriter compresses gaps).
            let byteCount = Int(converted.frameLength) * Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
            memset(converted.int16ChannelData?[0], 0, byteCount)
        }

        if let sampleBuffer = Self.makeSampleBuffer(from: converted, format: outputFormat) {
            onSampleBuffer?(sampleBuffer)
        }
    }

    private static func makeSampleBuffer(
        from buffer: AVAudioPCMBuffer,
        format: AVAudioFormat
    ) -> CMSampleBuffer? {
        var formatDescription: CMAudioFormatDescription?
        var basicDescription = format.streamDescription.pointee
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &basicDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        // Copy the PCM bytes into a CMBlockBuffer the sample buffer owns;
        // AVAudioPCMBuffer's backing memory may be reused before the writer
        // drains the queue. NOTE: `int16ChannelData` points to the *channel
        // pointer array* — subscript [0] to reach the actual PCM storage.
        var blockBuffer: CMBlockBuffer?
        let dataByteSize = Int(buffer.frameLength) * Int(format.streamDescription.pointee.mBytesPerFrame)
        guard dataByteSize > 0,
              let channelData = buffer.int16ChannelData?[0]
        else { return nil }

        let allocationStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataByteSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataByteSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard allocationStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        let replaceStatus = CMBlockBufferReplaceDataBytes(
            with: channelData,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: dataByteSize
        )
        guard replaceStatus == kCMBlockBufferNoErr else { return nil }

        // sampleSizeArray is UnsafePointer<Int> on macOS 14, not Int32.
        let sampleSize = MemoryLayout<Int16>.size
        var sampleSizes: [Int] = [sampleSize]
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else { return nil }

        // Stamp with the host-time clock so mic PTS shares SCStream's clock
        // domain and the engine can re-stamp it onto the recording timeline.
        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var timedBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &timedBuffer
        )
        return timedBuffer ?? sampleBuffer
    }
}

/// Thread-safe boolean shared between the main thread and the sample queues.
private final class LockedFlag {
    private var value: Bool
    private let lock = NSLock()

    init(_ value: Bool = false) {
        self.value = value
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

enum RecordingAudioSettings {
    /// Output settings for system audio captured via SCStream. Matches the
    /// 44.1kHz stereo format requested in `SCStreamConfiguration`.
    static var systemAudioOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    /// Output settings for microphone audio captured via AVAudioEngine.
    /// Single channel matches typical microphone input.
    static var microphoneOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }
}
