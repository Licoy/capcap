import AppKit

/// Mock preview of the idle magnifier color picker used inside Settings.
///
/// Renders a fixed-size facsimile of `IdleColorLensWindow` so users can see
/// how the live panel will look under their current configuration. The mock
/// content (a stylised app icon, sample coordinates, and a complementary
/// swatch colour) is hand-drawn so the preview feels like a real lens at
/// work, without bundling any image assets. It reads from `Defaults` directly
/// so it updates automatically when settings change.
final class IdleLensPreviewView: NSView {

    private let magnifiedSide: CGFloat = 144
    private let swatchSize: CGFloat = 12
    private let rowHeight: CGFloat = 14
    private let textLeftPadding: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        observeDefaults()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var observer: NSObjectProtocol?

    private func observeDefaults() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = IdleColorLensSampler.backgroundColor(forAppearance: effectiveAppearance)
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        // Subtle border — slightly stronger than the live panel so it reads
        // against the Settings chrome.
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        stroke.lineWidth = 0.5
        stroke.stroke()

        let magnifiedRect = NSRect(
            x: (bounds.width - magnifiedSide) / 2,
            y: bounds.height - 16 - magnifiedSide,
            width: magnifiedSide,
            height: magnifiedSide
        )
        drawMockMagnifiedArea(in: magnifiedRect)
        drawInfoRows(below: magnifiedRect.minY)
    }

    // MARK: - Mock magnification content

    private func drawMockMagnifiedArea(in rect: NSRect) {
        // Background tinted darker so the mock "icon" stands out.
        NSColor(calibratedWhite: 0.10, alpha: 0.55).setFill()
        NSBezierPath(rect: rect).fill()

        // Stylised "app icon" — blue rounded square with a white refresh
        // symbol, evoking the look of a sync / share button. Sits at the
        // centre so the crosshair (below) lands on its dominant colour.
        let iconSize: CGFloat = rect.width * 0.45
        let iconRect = NSRect(
            x: rect.midX - iconSize / 2,
            y: rect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        let iconColor = NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.99, alpha: 1)
        iconColor.setFill()
        let iconPath = NSBezierPath(
            roundedRect: iconRect,
            xRadius: iconSize * 0.22,
            yRadius: iconSize * 0.22
        )
        iconPath.fill()

        // Refresh / sync glyph: arc with arrowheads at both ends.
        NSColor.white.setStroke()
        let glyph = NSBezierPath()
        glyph.lineWidth = max(1.5, iconSize * 0.08)
        glyph.lineCapStyle = .round
        glyph.lineJoinStyle = .round
        let r = iconSize * 0.30
        let cx = iconRect.midX
        let cy = iconRect.midY
        glyph.appendArc(
            withCenter: NSPoint(x: cx, y: cy),
            radius: r,
            startAngle: 30,
            endAngle: 330,
            clockwise: false
        )
        glyph.stroke()

        // Arrow heads at the two ends of the arc.
        let head = max(3.5, iconSize * 0.16)
        // Right end (terminates near 330°, points down-right).
        let rightEnd = NSPoint(
            x: cx + r * cos(.pi * 330.0 / 180.0),
            y: cy + r * sin(.pi * 330.0 / 180.0)
        )
        let arrow1 = NSBezierPath()
        arrow1.move(to: NSPoint(x: rightEnd.x, y: rightEnd.y))
        arrow1.line(to: NSPoint(x: rightEnd.x - head * 0.6, y: rightEnd.y + head * 0.9))
        arrow1.line(to: NSPoint(x: rightEnd.x + head * 0.7, y: rightEnd.y - head * 0.3))
        arrow1.close()
        NSColor.white.setFill()
        arrow1.fill()

        // Left end (terminates near 150°, points up-left).
        let leftEnd = NSPoint(
            x: cx + r * cos(.pi * 150.0 / 180.0),
            y: cy + r * sin(.pi * 150.0 / 180.0)
        )
        let arrow2 = NSBezierPath()
        arrow2.move(to: NSPoint(x: leftEnd.x, y: leftEnd.y))
        arrow2.line(to: NSPoint(x: leftEnd.x + head * 0.6, y: leftEnd.y - head * 0.9))
        arrow2.line(to: NSPoint(x: leftEnd.x - head * 0.7, y: leftEnd.y + head * 0.3))
        arrow2.close()
        arrow2.fill()

        // Subtle inner shadow on the icon to give it depth.
        NSColor.black.withAlphaComponent(0.10).setStroke()
        iconPath.lineWidth = 1
        iconPath.stroke()

        // Pixel grid overlay — kept faint so it reads as "magnified pixels".
        drawPixelGrid(in: rect)

        // Border + crosshair (matches the live lens chrome).
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 0.5
        border.stroke()

        NSColor.white.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1.0
        let cxCross = rect.midX
        let cyCross = rect.midY
        cross.move(to: NSPoint(x: cxCross - 5, y: cyCross))
        cross.line(to: NSPoint(x: cxCross + 5, y: cyCross))
        cross.move(to: NSPoint(x: cxCross, y: cyCross - 5))
        cross.line(to: NSPoint(x: cxCross, y: cyCross + 5))
        cross.stroke()
    }

    private func drawPixelGrid(in rect: NSRect) {
        // 12-pixel grid that hints at "this is a magnification" without
        // dominating the icon. We render it last so the dark fill behind
        // gives the grid consistent contrast.
        let cells = 12
        let cell = rect.width / CGFloat(cells)
        NSColor.white.withAlphaComponent(0.05).setStroke()
        for i in 1..<cells {
            let v = rect.minX + CGFloat(i) * cell
            NSBezierPath.strokeLine(from: NSPoint(x: v, y: rect.minY), to: NSPoint(x: v, y: rect.maxY))
            let h = rect.minY + CGFloat(i) * cell
            NSBezierPath.strokeLine(from: NSPoint(x: rect.minX, y: h), to: NSPoint(x: rect.maxX, y: h))
        }
    }

    // MARK: - Info rows

    private func drawInfoRows(below topBoundary: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let tipAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)
        ]

        let totalRows = 2
            + (Defaults.idleLensShowCopyHint ? 1 : 0)
            + (Defaults.idleLensShowShiftHint ? 1 : 0)
        let availableTop = topBoundary - 8
        let totalInfoHeight = CGFloat(totalRows) * rowHeight
        let startY = availableTop - totalInfoHeight + rowHeight * 0.85

        // Coordinates row (top of info area).
        let coordsText = String(format: L10n.idleLensCoordinates, "590", "445")
        let coordsY = startY + CGFloat(totalRows - 1) * rowHeight
        (coordsText as NSString).draw(
            at: NSPoint(x: textLeftPadding, y: coordsY),
            withAttributes: attrs
        )

        // Swatch + HEX/RGB row.
        let rowIndex = totalRows - 2
        let swatchRect = NSRect(
            x: textLeftPadding,
            y: startY + CGFloat(rowIndex) * rowHeight,
            width: swatchSize,
            height: swatchSize
        )
        // Swatch colour matches the dominant blue of the mocked icon so the
        // HEX readout reflects what the lens would show in the magnified area.
        let swatch = NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.99, alpha: 1)
        swatch.setFill()
        NSBezierPath(roundedRect: swatchRect, xRadius: 2, yRadius: 2).fill()
        NSColor.labelColor.withAlphaComponent(0.3).setStroke()
        let sw = NSBezierPath(roundedRect: swatchRect, xRadius: 2, yRadius: 2)
        sw.lineWidth = 0.5
        sw.stroke()

        let mockHex = String(format: L10n.idleLensHex, "#0B63FE")
        (mockHex as NSString).draw(
            at: NSPoint(x: textLeftPadding + swatchSize + 6, y: startY + CGFloat(rowIndex) * rowHeight),
            withAttributes: attrs
        )

        // Tip rows (conditional on the user's preferences).
        var rowIdx = totalRows - 3
        if Defaults.idleLensShowCopyHint, rowIdx >= 0 {
            (L10n.idleLensCopyHint as NSString).draw(
                at: NSPoint(x: textLeftPadding, y: startY + CGFloat(rowIdx) * rowHeight),
                withAttributes: tipAttrs
            )
            rowIdx -= 1
        }
        if Defaults.idleLensShowShiftHint, rowIdx >= 0 {
            (L10n.idleLensShiftHint as NSString).draw(
                at: NSPoint(x: textLeftPadding, y: startY + CGFloat(rowIdx) * rowHeight),
                withAttributes: tipAttrs
            )
        }
    }
}