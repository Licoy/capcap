import AppKit

/// Live-ish preview of the idle magnifier color picker used inside Settings.
///
/// Draws a stylised "app icon" on the left and embeds a real
/// `IdleColorLensView` on the right. The lens samples from a `CGImage` we
/// generate on the fly from the same icon drawing, so the magnified square,
/// coordinates, swatch and HEX all reflect the user's current configuration.
/// When any relevant `Defaults` value changes, we re-render the icon
/// snapshot and feed the lens the fresh sample.
final class IdleLensPreviewView: NSView {

    private let iconSquare: CGFloat = 96
    private let iconToLensGap: CGFloat = 12
    private let containerInset: CGFloat = 8
    private var cachedPanelSize: NSSize = .zero

    private var lensView: IdleColorLensView?
    private var iconImage: CGImage?
    private var iconSample: IdleColorLensWindow.Sample?
    private var iconPixelPoint: CGPoint = .zero

    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        observeDefaults()
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Required size of the preview container. Includes the icon plus the
    /// live panel plus a gap. Callers (SettingsView) use this to lay out the
    /// preview area.
    static func requiredSize() -> NSSize {
        let panel = IdleColorLensWindow.panelSizeForCurrentSettings()
        let icon: CGFloat = 96
        let gap: CGFloat = 12
        let inset: CGFloat = 8
        let width = icon + gap + panel.width + inset * 2
        let height = max(icon, panel.height) + inset * 2
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private func observeDefaults() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
    }

    override func layout() {
        super.layout()
        positionLens()
    }

    /// Recreates the icon snapshot, samples its centre pixel, and rebuilds
    /// the embedded lens view if its size has changed.
    private func rebuild() {
        let iconSnapshot = IdleLensMockIcon.makeSnapshot()
        let centre = CGPoint(x: iconSnapshot.width / 2, y: iconSnapshot.height / 2)
        let sample = IdleColorLensSampler.sample(image: iconSnapshot, at: centre)
            ?? IdleColorLensWindow.Sample(r: 14, g: 118, b: 110)
        iconImage = iconSnapshot
        iconSample = sample
        iconPixelPoint = centre

        let newSize = IdleColorLensWindow.panelSizeForCurrentSettings()
        if newSize != cachedPanelSize || lensView == nil {
            cachedPanelSize = newSize
            lensView?.removeFromSuperview()
            let view = IdleColorLensView(frame: NSRect(origin: .zero, size: newSize))
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
            lensView = view
        }
        feedLens()
        positionLens()
        needsDisplay = true
    }

    private func feedLens() {
        guard let lens = lensView, let icon = iconImage, let sample = iconSample else { return }
        let screenFrame = NSRect(
            x: 0, y: 0,
            width: CGFloat(icon.width), height: CGFloat(icon.height)
        )
        let mouseLocation = NSPoint(
            x: CGFloat(iconPixelPoint.x),
            y: CGFloat(icon.height) - CGFloat(iconPixelPoint.y) // CG y-up → AppKit y-up
        )
        lens.format = .hex
        lens.update(
            sample: sample,
            pixelPoint: iconPixelPoint,
            mouseLocation: mouseLocation,
            snapshot: icon,
            screenFrame: screenFrame,
            format: .hex
        )
    }

    private func positionLens() {
        guard let lens = lensView else { return }
        lens.frame = NSRect(
            x: containerInset + iconSquare + iconToLensGap,
            y: (bounds.height - lens.frame.height) / 2,
            width: lens.frame.width,
            height: lens.frame.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        // Soft backdrop so the preview reads against the Settings chrome.
        NSColor(calibratedWhite: 0.18, alpha: 0.4).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        guard let icon = iconImage else { return }
        let iconRect = NSRect(
            x: containerInset,
            y: (bounds.height - iconSquare) / 2,
            width: iconSquare,
            height: iconSquare
        )
        NSImage(
            cgImage: icon,
            size: NSSize(width: icon.width, height: icon.height)
        ).draw(
            in: iconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        let iconOutline = NSBezierPath(roundedRect: iconRect, xRadius: 18, yRadius: 18)
        iconOutline.lineWidth = 0.5
        iconOutline.stroke()
    }
}

/// Renders a stylised app icon as a `CGImage` so the idle lens preview has
/// something recognisable to magnify. The shape and colour echo a generic
/// "capcap" / "Tencent Meeting" / "ChatGPT" / "refresh" style icon.
enum IdleLensMockIcon {

    /// Render a 256×256 CGImage containing a teal rounded square with a
    /// white "refresh" / "knot" symbol at its centre.
    static func makeSnapshot() -> CGImage {
        let size = CGSize(width: 256, height: 256)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
        let bytesPerRow = Int(size.width) * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * Int(size.height))

        guard let context = CGContext(
            data: &pixels,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return fallback()
        }

        // Soft gradient backdrop so the icon doesn't sit on a flat colour.
        let colors = [
            CGColor(red: 0.06, green: 0.36, blue: 0.46, alpha: 1),
            CGColor(red: 0.04, green: 0.46, blue: 0.55, alpha: 1)
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }

        // Icon: off-white rounded square.
        let iconSize: CGFloat = 180
        let iconOrigin = CGPoint(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2
        )
        let iconRect = CGRect(origin: iconOrigin, size: CGSize(width: iconSize, height: iconSize))
        let iconCornerRadius: CGFloat = iconSize * 0.22
        let iconPath = CGPath(
            roundedRect: iconRect,
            cornerWidth: iconCornerRadius,
            cornerHeight: iconCornerRadius,
            transform: nil
        )
        context.addPath(iconPath)
        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1))
        context.fillPath()

        // Teal refresh / knot symbol: a thick arc with two arrowheads.
        context.setStrokeColor(CGColor(red: 0.06, green: 0.36, blue: 0.46, alpha: 1))
        context.setLineWidth(iconSize * 0.075)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let r = iconSize * 0.30
        let cx = iconRect.midX
        let cy = iconRect.midY
        context.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            startAngle: .pi * 30.0 / 180.0,
            endAngle: .pi * 330.0 / 180.0,
            clockwise: false
        )
        context.strokePath()

        // Arrowheads at the two arc ends.
        context.setFillColor(CGColor(red: 0.06, green: 0.36, blue: 0.46, alpha: 1))
        let head: CGFloat = iconSize * 0.14
        for angleDegrees in [330.0, 150.0] as [Double] {
            let angle = .pi * angleDegrees / 180.0
            let endX = cx + r * cos(angle)
            let endY = cy + r * sin(angle)
            let tangentAngle = angle + .pi / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: endX, y: endY))
            path.addLine(to: CGPoint(
                x: endX + head * cos(tangentAngle + .pi),
                y: endY + head * sin(tangentAngle + .pi)
            ))
            path.addLine(to: CGPoint(
                x: endX + head * cos(tangentAngle - .pi / 2),
                y: endY + head * sin(tangentAngle - .pi / 2)
            ))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }

        return context.makeImage() ?? fallback()
    }

    /// Plain teal fallback used only if the CGContext allocation fails.
    private static func fallback() -> CGImage {
        let size = CGSize(width: 256, height: 256)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = Int(size.width) * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * Int(size.height))
        guard let context = CGContext(
            data: &pixels,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let image = context.makeImage() else {
            return CGImage(
                width: 1, height: 1,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: CGDataProvider(data: Data([0, 0, 0, 0]) as CFData)!,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!
        }
        return image
    }
}