import AppKit

/// AppKit preview of the magnifier panel used in Settings > General.
/// The right side embeds the production `IdleColorLensView` so preview drawing
/// stays aligned with the live panel. Hovering the icon drives real pixel
/// sampling from the bundled app icon.
final class MagnifierPreviewView: NSView {

    private static let iconSide: CGFloat = 76
    private static let contentPadding: CGFloat = 16
    private static let contentSpacing: CGFloat = 18

    private let iconImage: NSImage
    private let mockSnapshot: CGImage
    private let iconView: MagnifierPreviewSubjectView
    private let lensView: IdleColorLensView
    private var defaultsObserver: NSObjectProtocol?
    private var hoverLocation: CGPoint?
    private var lensWidthConstraint: NSLayoutConstraint?
    private var lensHeightConstraint: NSLayoutConstraint?

    init(iconImage: NSImage, mockSnapshot: CGImage) {
        self.iconImage = iconImage
        self.mockSnapshot = mockSnapshot
        self.iconView = MagnifierPreviewSubjectView(iconImage: iconImage)
        self.lensView = IdleColorLensView(frame: .zero)
        super.init(frame: NSRect(origin: .zero, size: Self.requiredSize()))

        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 0.4).cgColor
        setupLayout()
        iconView.onHoverChanged = { [weak self] point in
            self?.hoverLocation = self?.pixelPoint(forIconPoint: point)
            self?.iconView.showsFakeCursor = point == nil
            self?.updateLens()
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshForCurrentDefaults()
        }
        refreshForCurrentDefaults()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    override var intrinsicContentSize: NSSize {
        Self.requiredSize()
    }

    /// Total preview size. SettingsView uses this to size the embedded AppKit
    /// view in the card layout.
    static func requiredSize() -> NSSize {
        let lens = IdleColorLensWindow.panelSizeForCurrentSettings()
        return NSSize(
            width: contentPadding * 2 + iconSide + contentSpacing + lens.width,
            height: contentPadding * 2 + max(iconSide, lens.height)
        )
    }

    private func setupLayout() {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Self.contentSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSide),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSide),
        ])

        lensView.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(lensView)
        let lensSize = IdleColorLensWindow.panelSizeForCurrentSettings()
        lensWidthConstraint = lensView.widthAnchor.constraint(equalToConstant: lensSize.width)
        lensHeightConstraint = lensView.heightAnchor.constraint(equalToConstant: lensSize.height)
        lensWidthConstraint?.isActive = true
        lensHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentPadding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentPadding),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentPadding),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentPadding),
        ])
    }

    private func refreshForCurrentDefaults() {
        let lensSize = IdleColorLensWindow.panelSizeForCurrentSettings()
        lensWidthConstraint?.constant = lensSize.width
        lensHeightConstraint?.constant = lensSize.height
        setFrameSize(Self.requiredSize())
        invalidateIntrinsicContentSize()
        updateLens()
    }

    private func pixelPoint(forIconPoint point: NSPoint?) -> CGPoint? {
        guard let point else { return nil }
        let x = min(max(0, point.x), Self.iconSide)
        let y = min(max(0, point.y), Self.iconSide)
        let scaleX = CGFloat(mockSnapshot.width) / Self.iconSide
        let scaleY = CGFloat(mockSnapshot.height) / Self.iconSide
        return CGPoint(x: x * scaleX, y: y * scaleY)
    }

    private func updateLens() {
        let w = CGFloat(mockSnapshot.width)
        let h = CGFloat(mockSnapshot.height)
        let pixelPoint = hoverLocation ?? CGPoint(x: w / 2, y: h / 2)
        let mouseLocation = NSPoint(x: pixelPoint.x, y: h - pixelPoint.y)
        let screenFrame = NSRect(x: 0, y: 0, width: w, height: h)
        let sample = IdleColorLensSampler.sample(image: mockSnapshot, at: pixelPoint)
            ?? IdleColorLensWindow.Sample(r: 0, g: 0, b: 0)

        lensView.update(
            sample: sample,
            pixelPoint: pixelPoint,
            mouseLocation: mouseLocation,
            snapshot: mockSnapshot,
            screenFrame: screenFrame,
            format: .hex
        )
    }
}

private final class MagnifierPreviewSubjectView: NSView {
    private static let cursorSide: CGFloat = 22
    private static let cursorHotspotOffset = NSPoint(x: 3, y: 2)

    var onHoverChanged: ((NSPoint?) -> Void)?
    var showsFakeCursor: Bool = true {
        didSet { needsDisplay = true }
    }

    private let iconImage: NSImage
    private var trackingAreaRef: NSTrackingArea?

    init(iconImage: NSImage) {
        self.iconImage = iconImage
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        publishHover(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        publishHover(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconRect = bounds
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSBezierPath(roundedRect: iconRect, xRadius: 17, yRadius: 17).addClip()
        iconImage.draw(in: iconRect)
        NSGraphicsContext.current?.restoreGraphicsState()

        guard showsFakeCursor else { return }
        let cursorImage = NSCursor.arrow.image
        let hotspot = NSPoint(x: iconRect.midX, y: iconRect.midY)
        let cursorRect = NSRect(
            x: hotspot.x - Self.cursorHotspotOffset.x,
            y: hotspot.y - Self.cursorHotspotOffset.y,
            width: Self.cursorSide,
            height: Self.cursorSide
        )
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        cursorImage.draw(in: cursorRect)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func publishHover(from event: NSEvent) {
        onHoverChanged?(convert(event.locationInWindow, from: nil))
    }
}
