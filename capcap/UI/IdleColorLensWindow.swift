import AppKit

/// Cursor-adjacent magnifier color picker shown on the overlay's idle state.
///
/// Replaces the legacy "drag to screenshot" cursor chip while the user has not
/// yet started dragging a selection rectangle. Displays absolute desktop
/// coordinates, a 12× magnification of the 8×8 pixel neighborhood around the
/// cursor, and the current pixel value in either HEX or RGB. Listens for
/// mouse-move events to follow the cursor but never blocks input.
final class IdleColorLensWindow: NSPanel {

    enum Format {
        case hex
        case rgb
    }

    /// Single-pixel sRGB sample. Channels are 0-255 integers.
    struct Sample: Equatable {
        let r: Int
        let g: Int
        let b: Int
    }

    private static let panelSize = NSSize(width: 256, height: 240)
    private static let cursorOffsetX: CGFloat = 15
    private static let cursorOffsetY: CGFloat = 14
    private static let edgeMargin: CGFloat = 8

    private let lensView = IdleColorLensView(frame: NSRect(origin: .zero, size: panelSize))
    private var mouseMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = lensView
    }

    deinit {
        stopTracking()
    }

    func show() {
        orderFrontRegardless()
        updatePosition()
        startTracking()
    }

    func dismiss() {
        stopTracking()
        orderOut(nil)
    }

    func update(
        snapshot: CGImage?,
        screenFrame: NSRect,
        mouseLocation: NSPoint,
        format: Format
    ) {
        guard let snapshot else {
            lensView.clear()
            return
        }
        let pixelPoint = IdleColorLensSampler.pixelCoordinate(
            globalPoint: mouseLocation,
            screenFrame: screenFrame,
            snapshotSize: CGSize(width: snapshot.width, height: snapshot.height)
        )
        let sample = IdleColorLensSampler.sample(image: snapshot, at: pixelPoint)
            ?? Sample(r: 0, g: 0, b: 0)
        lensView.update(
            sample: sample,
            pixelPoint: pixelPoint,
            mouseLocation: mouseLocation,
            snapshot: snapshot,
            screenFrame: screenFrame,
            format: format
        )
        updatePosition()
    }

    func setFormat(_ format: Format) {
        lensView.format = format
    }

    /// Returns the current sample and pixel location the lens is displaying.
    /// Used by the overlay controller to perform the actual copy on ⌘+C.
    var currentSample: Sample? { lensView.currentSample }
    var currentPixelPoint: CGPoint { lensView.currentPixelPoint }

    // MARK: - Position tracking

    private func startTracking() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updatePosition()
            return event
        }
    }

    private func stopTracking() {
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
        }
    }

    private func updatePosition() {
        let loc = NSEvent.mouseLocation
        // Default: panel sits directly below the cursor so the cursor stays
        // inside the magnified area when the lens first appears and when the
        // user is near the top edge of the screen.
        // AppKit's panel origin is the bottom-left corner, so:
        //   panel.bottom = origin.y
        //   panel.top    = origin.y + panelSize.height
        // "Below cursor" → panel top = cursor.y - offsetY → origin.y = cursor.y - offsetY - height
        var origin = NSPoint(
            x: loc.x + Self.cursorOffsetX,
            y: loc.y - Self.cursorOffsetY - Self.panelSize.height
        )
        // Find the screen containing the cursor so the panel stays inside it.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }) {
            let frame = screen.frame
            // Right edge flip: panel would overflow screen right → move to the
            // left side of the cursor.
            let panelRight = origin.x + Self.panelSize.width
            if panelRight > frame.maxX - Self.edgeMargin {
                origin.x = loc.x - Self.cursorOffsetX - Self.panelSize.width
            }
            // Bottom edge flip: panel would overflow screen bottom → move above
            // the cursor. This is the only case where the panel sits above the
            // cursor.
            if origin.y < frame.minY + Self.edgeMargin {
                origin.y = loc.y + Self.cursorOffsetY
            }
        }
        setFrameOrigin(origin)
    }
}

/// Pure helpers for reading a single pixel from a `CGImage` and mapping a
/// global mouse location onto the image's coordinate space. Kept as a free
/// namespace so unit tests can exercise them without an `NSPanel`.
enum IdleColorLensSampler {

    /// Maps an AppKit global mouse location (y-up) onto the CGImage coordinate
    /// space (y-down) of the supplied snapshot, accounting for the screen's
    /// pixel-to-point scale factor.
    static func pixelCoordinate(
        globalPoint: NSPoint,
        screenFrame: NSRect,
        snapshotSize: CGSize
    ) -> CGPoint {
        let scaleX = snapshotSize.width / max(screenFrame.width, 1)
        let scaleY = snapshotSize.height / max(screenFrame.height, 1)
        let xInScreen = (globalPoint.x - screenFrame.origin.x) * scaleX
        let yInScreenFromTop = (screenFrame.maxY - globalPoint.y) * scaleY
        // Clamp into the valid pixel range so cursor-on-edge still resolves
        // to a valid sample instead of returning nil.
        let maxX = max(0, snapshotSize.width - 1)
        let maxY = max(0, snapshotSize.height - 1)
        return CGPoint(
            x: min(max(0, xInScreen), maxX),
            y: min(max(0, yInScreenFromTop), maxY)
        )
    }

    /// Samples a single pixel from `image` at `point` (CGImage coords). Returns
    /// `nil` if the point lies outside the image bounds or the context cannot
    /// be allocated.
    static func sample(image: CGImage, at point: CGPoint) -> IdleColorLensWindow.Sample? {
        guard point.x >= 0, point.y >= 0,
              point.x < CGFloat(image.width),
              point.y < CGFloat(image.height) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // Position the image so that `point` lands at (0.5, 0.5) of the 1x1
        // context. `CGContext.draw(image, in: rect)` places the image's top
        // edge at the top of `rect` in the context's y-up coords, so the
        // desired image pixel needs:
        //   x:  rect.x + px = 0.5  →  rect.x = 0.5 - px
        //   y:  rect.y + imageH - py = 0.5  →  rect.y = 0.5 + py - imageH
        let drawRect = CGRect(
            x: 0.5 - point.x,
            y: 0.5 + point.y - CGFloat(image.height),
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        context.draw(image, in: drawRect)

        return IdleColorLensWindow.Sample(
            r: Int(pixelData[0]),
            g: Int(pixelData[1]),
            b: Int(pixelData[2])
        )
    }
}

private final class IdleColorLensView: NSView {

    var format: IdleColorLensWindow.Format = .hex {
        didSet { needsDisplay = true }
    }

    private(set) var currentSample: IdleColorLensWindow.Sample?
    private(set) var currentPixelPoint: CGPoint = .zero
    private var mouseLocation: NSPoint = .zero
    private var snapshot: CGImage?
    private var screenFrame: NSRect = .zero

    // Layout
    private static let magnifiedSide: CGFloat = 144
    private static let magnifiedBottom: CGFloat = 88
    private static let magnifiedLeft: CGFloat = 56 // (256 - 144) / 2
    private static let infoLeftPadding: CGFloat = 12
    private static let infoRightPadding: CGFloat = 12
    private static let infoRowHeight: CGFloat = 18
    private static let infoBottomInset: CGFloat = 8
    private static let swatchSize: CGFloat = 16
    private static let magnifiedSourceSize: CGFloat = 12 // 12x12 source → 144x144 dest = 12x mag
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let tipFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    func clear() {
        currentSample = nil
        snapshot = nil
        needsDisplay = true
    }

    func update(
        sample: IdleColorLensWindow.Sample,
        pixelPoint: CGPoint,
        mouseLocation: NSPoint,
        snapshot: CGImage,
        screenFrame: NSRect,
        format: IdleColorLensWindow.Format
    ) {
        self.currentSample = sample
        self.currentPixelPoint = pixelPoint
        self.mouseLocation = mouseLocation
        self.snapshot = snapshot
        self.screenFrame = screenFrame
        self.format = format
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Panel background
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        AdaptiveChrome.floatingBackground.setFill()
        path.fill()
        AdaptiveChrome.border.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        drawMagnifiedArea()
        drawInfo()
    }

    private func drawMagnifiedArea() {
        let rect = NSRect(
            x: Self.magnifiedLeft,
            y: Self.magnifiedBottom,
            width: Self.magnifiedSide,
            height: Self.magnifiedSide
        )
        // Frame
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(rect: rect).fill()

        guard let snapshot else { return }

        let regionSize = Self.magnifiedSourceSize
        let sourceX = max(0, currentPixelPoint.x - regionSize / 2)
        let sourceY = max(0, currentPixelPoint.y - regionSize / 2)
        // Clamp the source region so it never extends beyond the snapshot.
        let clampedWidth = min(regionSize, CGFloat(snapshot.width) - sourceX)
        let clampedHeight = min(regionSize, CGFloat(snapshot.height) - sourceY)

        guard clampedWidth > 0, clampedHeight > 0,
              let cropped = snapshot.cropping(to: CGRect(
                x: sourceX, y: sourceY, width: clampedWidth, height: clampedHeight
              )),
              let context = NSGraphicsContext.current?.cgContext else { return }

        // CGContext.draw(image, in: rect) already places the image's visual
        // top-left at rect's visual top-left, so cropping to sourceRect and
        // drawing the result into the magnified area gives a correctly
        // oriented magnification with the cursor pixel at destRect's center.
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(cropped, in: rect)
        context.restoreGState()

        // Border
        NSColor.labelColor.withAlphaComponent(0.4).setStroke()
        let borderPath = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 0.5
        borderPath.stroke()

        // Center crosshair — aligns with the sampled pixel.
        let centerX = rect.midX
        let centerY = rect.midY
        NSColor.white.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1.0
        cross.move(to: NSPoint(x: centerX - 4, y: centerY))
        cross.line(to: NSPoint(x: centerX + 4, y: centerY))
        cross.move(to: NSPoint(x: centerX, y: centerY - 4))
        cross.line(to: NSPoint(x: centerX, y: centerY + 4))
        cross.stroke()
    }

    private func drawInfo() {
        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor
        ]
        let tipAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.tipFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)
        ]

        // Coordinates (top row)
        if currentSample != nil {
            let x = String(Int(mouseLocation.x))
            let y = String(Int(mouseLocation.y))
            let coordsText = String(format: L10n.idleLensCoordinates, x, y)
            drawText(
                coordsText,
                attrs: infoAttrs,
                rowFromBottom: 3,
                availableWidth: bounds.width - Self.infoLeftPadding - Self.infoRightPadding
            )
        }

        // Swatch + HEX/RGB
        if let sample = currentSample {
            let swatchRect = NSRect(
                x: Self.infoLeftPadding,
                y: Self.infoBottomInset + 2 * Self.infoRowHeight + 1,
                width: Self.swatchSize,
                height: Self.swatchSize
            )
            NSColor(
                srgbRed: CGFloat(sample.r) / 255.0,
                green: CGFloat(sample.g) / 255.0,
                blue: CGFloat(sample.b) / 255.0,
                alpha: 1.0
            ).setFill()
            NSBezierPath(roundedRect: swatchRect, xRadius: 2, yRadius: 2).fill()
            // Border
            NSColor.labelColor.withAlphaComponent(0.3).setStroke()
            let border = NSBezierPath(roundedRect: swatchRect, xRadius: 2, yRadius: 2)
            border.lineWidth = 0.5
            border.stroke()

            let colorText: String
            switch format {
            case .hex:
                colorText = String(format: L10n.idleLensHex, hexString(sample))
            case .rgb:
                colorText = String(format: L10n.idleLensRgb, L10n.idleLensRgbString(r: sample.r, g: sample.g, b: sample.b))
            }
            drawText(
                colorText,
                attrs: infoAttrs,
                rowFromBottom: 2,
                leftOffset: Self.infoLeftPadding + Self.swatchSize + 6,
                availableWidth: bounds.width - Self.infoLeftPadding - Self.swatchSize - 6 - Self.infoRightPadding
            )
        }

        // Tip rows (permanent — no fade-out)
        drawText(
            L10n.idleLensCopyHint,
            attrs: tipAttrs,
            rowFromBottom: 1,
            availableWidth: bounds.width - Self.infoLeftPadding - Self.infoRightPadding
        )
        drawText(
            L10n.idleLensShiftHint,
            attrs: tipAttrs,
            rowFromBottom: 0,
            availableWidth: bounds.width - Self.infoLeftPadding - Self.infoRightPadding
        )
    }

    private func drawText(
        _ text: String,
        attrs: [NSAttributedString.Key: Any],
        rowFromBottom: Int,
        leftOffset: CGFloat = 0,
        availableWidth: CGFloat = 0
    ) {
        let y = Self.infoBottomInset + CGFloat(rowFromBottom) * Self.infoRowHeight
        let x = leftOffset == 0 ? Self.infoLeftPadding : leftOffset
        let width = leftOffset == 0
            ? bounds.width - Self.infoLeftPadding - Self.infoRightPadding
            : availableWidth
        let rect = NSRect(x: x, y: y, width: width, height: Self.infoRowHeight)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func hexString(_ sample: IdleColorLensWindow.Sample) -> String {
        String(format: "#%02X%02X%02X", sample.r, sample.g, sample.b)
    }
}