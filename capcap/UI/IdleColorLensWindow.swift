import AppKit

/// Cursor-adjacent magnifier color picker shown on the overlay's idle state.
///
/// Replaces the legacy "drag to screenshot" cursor chip while the user has not
/// yet started dragging a selection rectangle. Displays absolute desktop
/// coordinates, a magnification of the pixel neighborhood around the cursor,
/// and the current pixel value in either HEX or RGB. Listens for mouse-move
/// events to follow the cursor but never blocks input. All visual settings
/// (panel size, magnified area, offsets, background color, hint visibility)
/// are read from `Defaults` so changes in Settings take effect the next time
/// the lens is shown.
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

    private static let edgeMargin: CGFloat = 8

    /// Computes the panel size that fits the current Defaults (magnified
    /// square + 4 info rows or 2 rows when hints are disabled). Public so
    /// the Settings preview can size its embedded lens view identically to
    /// the live panel.
    static func panelSizeForCurrentSettings() -> NSSize {
        let magnifiedSide = CGFloat(Defaults.idleLensMagnifiedSize)
        let infoRows = 2
            + (Defaults.idleLensShowCopyHint ? 1 : 0)
            + (Defaults.idleLensShowShiftHint ? 1 : 0)
        let infoHeight = CGFloat(infoRows) * 18 + 8
        let gap: CGFloat = 8
        let topInset: CGFloat = 8
        let width: CGFloat = max(220, magnifiedSide + 24)
        let height = magnifiedSide + gap + infoHeight + topInset
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private static func computePanelSize() -> NSSize {
        panelSizeForCurrentSettings()
    }

    private let lensView: IdleColorLensView
    private var mouseMonitor: Any?
    private let panelSize: NSSize

    init() {
        let size = Self.computePanelSize()
        self.panelSize = size
        self.lensView = IdleColorLensView(frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
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

    /// Public layout values for the Settings preview to mirror.
    var layoutMagnifiedSide: CGFloat { CGFloat(Defaults.idleLensMagnifiedSize) }
    var layoutPanelSize: NSSize { panelSize }
    var layoutCursorOffset: NSPoint {
        NSPoint(x: Defaults.idleLensPanelOffsetX, y: Defaults.idleLensPanelOffsetY)
    }

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
        let offsetX = CGFloat(Defaults.idleLensPanelOffsetX)
        let offsetY = CGFloat(Defaults.idleLensPanelOffsetY)
        // Default: panel sits directly below the cursor. AppKit panel origin
        // is the bottom-left corner, so panel.top = origin.y + height →
        // origin.y = cursor.y - offsetY - height.
        var origin = NSPoint(
            x: loc.x + offsetX,
            y: loc.y - offsetY - panelSize.height
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }) {
            let frame = screen.frame
            let panelRight = origin.x + panelSize.width
            if panelRight > frame.maxX - Self.edgeMargin {
                origin.x = loc.x - offsetX - panelSize.width
            }
            if origin.y < frame.minY + Self.edgeMargin {
                origin.y = loc.y + offsetY
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

        // Position the image so that `point` lands at (0.5, 0.5) of the 1×1
        // context. CGContext.draw places the image's top edge at rect's top in
        // the context's y-up coords, so the target pixel needs:
        //   x: rect.x + px = 0.5  →  rect.x = 0.5 - px
        //   y: rect.y + imageH - py = 0.5  →  rect.y = 0.5 + py - imageH
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

    /// Picks the dark- or light-mode background color according to the user's
    /// `followSystemAppearance` preference. Pass `effectiveAppearance` from
    /// the view that needs to draw so this works regardless of AppKit quirks.
    static func backgroundColor(forAppearance appearance: NSAppearance) -> NSColor {
        if Defaults.idleLensFollowSystemAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
            return isDark ? darkBackgroundColor() : lightBackgroundColor()
        }
        return darkBackgroundColor()
    }

    static func darkBackgroundColor() -> NSColor {
        NSColor(
            srgbRed: CGFloat(Defaults.idleLensDarkBackgroundRed),
            green: CGFloat(Defaults.idleLensDarkBackgroundGreen),
            blue: CGFloat(Defaults.idleLensDarkBackgroundBlue),
            alpha: CGFloat(Defaults.idleLensDarkBackgroundAlpha)
        )
    }

    static func lightBackgroundColor() -> NSColor {
        NSColor(
            srgbRed: CGFloat(Defaults.idleLensLightBackgroundRed),
            green: CGFloat(Defaults.idleLensLightBackgroundGreen),
            blue: CGFloat(Defaults.idleLensLightBackgroundBlue),
            alpha: CGFloat(Defaults.idleLensLightBackgroundAlpha)
        )
    }
}

final class IdleColorLensView: NSView {

    var format: IdleColorLensWindow.Format = .hex {
        didSet { needsDisplay = true }
    }

    private(set) var currentSample: IdleColorLensWindow.Sample?
    private(set) var currentPixelPoint: CGPoint = .zero
    private var mouseLocation: NSPoint = .zero
    private var snapshot: CGImage?
    private var screenFrame: NSRect = .zero

    // Layout — derived from Defaults on every draw so changes show up
    // immediately the next time the lens appears.
    private let infoLeftPadding: CGFloat = 12
    private let infoRightPadding: CGFloat = 12
    private let infoRowHeight: CGFloat = 18
    private let infoBottomInset: CGFloat = 8
    private let swatchSize: CGFloat = 16
    private let gapBetweenMagnifiedAndInfo: CGFloat = 8
    private let topInset: CGFloat = 8

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
        let magnifiedSide = CGFloat(Defaults.idleLensMagnifiedSize)
        let panelWidth = bounds.width
        let panelHeight = bounds.height
        let magnifiedRect = NSRect(
            x: (panelWidth - magnifiedSide) / 2,
            y: panelHeight - topInset - magnifiedSide,
            width: magnifiedSide,
            height: magnifiedSide
        )

        // Panel background — pick dark or light based on appearance + setting.
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        let panelBackground = IdleColorLensSampler.backgroundColor(forAppearance: effectiveAppearance)
        panelBackground.setFill()
        bgPath.fill()
        AdaptiveChrome.border.setStroke()
        bgPath.lineWidth = 0.5
        bgPath.stroke()

        drawMagnifiedArea(in: magnifiedRect)
        drawInfo(panelHeight: panelHeight, magnifiedBottom: magnifiedRect.minY)
    }

    private func drawMagnifiedArea(in rect: NSRect) {
        // Fill the entire area with a visually distinct out-of-bounds
        // colour so the user can tell which region sits beyond the
        // screen boundary. The valid crop is drawn on top afterwards.
        NSColor(calibratedWhite: 0.15, alpha: 0.6).setFill()
        NSBezierPath(rect: rect).fill()

        guard let snapshot else { return }

        // Source region (in pixels) = display size / zoom factor.
        let regionSize = max(2, rect.width / CGFloat(Defaults.idleLensMagnification))
        let sourceX = max(0, currentPixelPoint.x - regionSize / 2)
        let sourceY = max(0, currentPixelPoint.y - regionSize / 2)
        let clampedWidth = min(regionSize, CGFloat(snapshot.width) - sourceX)
        let clampedHeight = min(regionSize, CGFloat(snapshot.height) - sourceY)

        guard clampedWidth > 0, clampedHeight > 0,
              let cropped = snapshot.cropping(to: CGRect(
                x: sourceX, y: sourceY, width: clampedWidth, height: clampedHeight
              )),
              let context = NSGraphicsContext.current?.cgContext else { return }

        // Compute where the valid crop should sit inside the display
        // rect so the out-of-bounds portion stays visible as the dimmed
        // background fill. The cursor pixel must land at rect.mid.
        // CGContext maps CGImage y=0 to drawRect.maxY (AppKit y-up),
        // so the cursor (at crop-y cursorOffsetY) sits at
        // drawRect.maxY - cursorOffsetY * scale == rect.midY.
        let scale = rect.width / regionSize
        let missingLeft = sourceX - (currentPixelPoint.x - regionSize / 2)  // ≥ 0
        let cursorOffsetY = currentPixelPoint.y - sourceY  // in crop (y-down)
        let drawMaxY = rect.midY + cursorOffsetY * scale
        let drawRect = NSRect(
            x: rect.minX + missingLeft * scale,
            y: drawMaxY - clampedHeight * scale,
            width: clampedWidth * scale,
            height: clampedHeight * scale
        )

        context.saveGState()
        context.interpolationQuality = .none
        context.draw(cropped, in: drawRect)
        context.restoreGState()

        // Border
        NSColor.labelColor.withAlphaComponent(0.4).setStroke()
        let borderPath = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 0.5
        borderPath.stroke()

        // Enhanced crosshair — 10 px lines in #A5BAF9 spanning the full
        // magnified area. Sits behind the fine white cross so the centre
        // remains visible even on pure-white backgrounds.
        let centerX = rect.midX
        let centerY = rect.midY
        NSColor(srgbRed: 0xA5 / 255.0, green: 0xBA / 255.0, blue: 0xF9 / 255.0, alpha: 0.65).setStroke()
        let bigCross = NSBezierPath()
        bigCross.lineWidth = 10
        bigCross.move(to: NSPoint(x: rect.minX, y: centerY))
        bigCross.line(to: NSPoint(x: rect.maxX, y: centerY))
        bigCross.move(to: NSPoint(x: centerX, y: rect.minY))
        bigCross.line(to: NSPoint(x: centerX, y: rect.maxY))
        bigCross.stroke()

        // Fine white crosshair — aligns with the sampled pixel.
        NSColor.white.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1.0
        cross.move(to: NSPoint(x: centerX - 4, y: centerY))
        cross.line(to: NSPoint(x: centerX + 4, y: centerY))
        cross.move(to: NSPoint(x: centerX, y: centerY - 4))
        cross.line(to: NSPoint(x: centerX, y: centerY + 4))
        cross.stroke()
    }

    private func drawInfo(panelHeight: CGFloat, magnifiedBottom: CGFloat) {
        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.labelColor
        ]
        let tipAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.tipFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)
        ]

        // Compute the row index (from the bottom) for each row that exists.
        // We always render coords + color (rows 3 and 2 in old layout).
        // Tip rows occupy 1 and 0 conditionally.
        var rowFromBottom = 0
        let infoAreaBottom = infoBottomInset
        // totalRows in info area (coords + color + maybe copy + maybe shift)
        let totalRows = 2
            + (Defaults.idleLensShowCopyHint ? 1 : 0)
            + (Defaults.idleLensShowShiftHint ? 1 : 0)

        func rowY(forIndex i: Int) -> CGFloat {
            // i is 0-based from bottom
            infoAreaBottom + CGFloat(i) * infoRowHeight
        }

        // Coordinates row (always)
        if currentSample != nil {
            let x = String(Int(mouseLocation.x))
            let y = String(Int(mouseLocation.y))
            let coordsText = String(format: L10n.idleLensCoordinates, x, y)
            drawText(
                coordsText,
                attrs: infoAttrs,
                at: rowY(forIndex: totalRows - 1),
                availableWidth: bounds.width - infoLeftPadding - infoRightPadding
            )
        }

        // Swatch + HEX/RGB row (always)
        if let sample = currentSample {
            let rowIndex = totalRows - 2
            let swatchRect = NSRect(
                x: infoLeftPadding,
                y: rowY(forIndex: rowIndex) + 1,
                width: swatchSize,
                height: swatchSize
            )
            NSColor(
                srgbRed: CGFloat(sample.r) / 255.0,
                green: CGFloat(sample.g) / 255.0,
                blue: CGFloat(sample.b) / 255.0,
                alpha: 1.0
            ).setFill()
            NSBezierPath(roundedRect: swatchRect, xRadius: 2, yRadius: 2).fill()
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
                at: rowY(forIndex: rowIndex),
                leftOffset: infoLeftPadding + swatchSize + 6,
                availableWidth: bounds.width - infoLeftPadding - swatchSize - 6 - infoRightPadding
            )
        }

        // Tip rows (conditional)
        if Defaults.idleLensShowCopyHint {
            drawText(
                L10n.idleLensCopyHint,
                attrs: tipAttrs,
                at: rowY(forIndex: rowFromBottom),
                availableWidth: bounds.width - infoLeftPadding - infoRightPadding
            )
            rowFromBottom += 1
        }
        if Defaults.idleLensShowShiftHint {
            drawText(
                L10n.idleLensShiftHint,
                attrs: tipAttrs,
                at: rowY(forIndex: rowFromBottom),
                availableWidth: bounds.width - infoLeftPadding - infoRightPadding
            )
        }
        _ = magnifiedBottom // silence unused warning
        _ = panelHeight
    }

    private func drawText(
        _ text: String,
        attrs: [NSAttributedString.Key: Any],
        at y: CGFloat,
        leftOffset: CGFloat = 0,
        availableWidth: CGFloat = 0
    ) {
        let x = leftOffset == 0 ? infoLeftPadding : leftOffset
        let width = leftOffset == 0
            ? bounds.width - infoLeftPadding - infoRightPadding
            : availableWidth
        let rect = NSRect(x: x, y: y, width: width, height: infoRowHeight)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func hexString(_ sample: IdleColorLensWindow.Sample) -> String {
        String(format: "#%02X%02X%02X", sample.r, sample.g, sample.b)
    }
}