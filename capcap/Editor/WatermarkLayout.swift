import AppKit

enum WatermarkAnchor: String, Codable, CaseIterable {
    case topLeft
    case top
    case topRight
    case left
    case center
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var symbol: String {
        switch self {
        case .topLeft: return "↖"
        case .top: return "↑"
        case .topRight: return "↗"
        case .left: return "←"
        case .center: return "●"
        case .right: return "→"
        case .bottomLeft: return "↙"
        case .bottom: return "↓"
        case .bottomRight: return "↘"
        }
    }

    var localizedName: String {
        switch self {
        case .topLeft: return L10n.watermarkAnchorTopLeft
        case .top: return L10n.watermarkAnchorTop
        case .topRight: return L10n.watermarkAnchorTopRight
        case .left: return L10n.watermarkAnchorLeft
        case .center: return L10n.watermarkAnchorCenter
        case .right: return L10n.watermarkAnchorRight
        case .bottomLeft: return L10n.watermarkAnchorBottomLeft
        case .bottom: return L10n.watermarkAnchorBottom
        case .bottomRight: return L10n.watermarkAnchorBottomRight
        }
    }
}

struct WatermarkTemplate: Codable, Equatable, Identifiable {
    static let maxCount = 8
    static let defaultFontSize = 28.0
    static let defaultOpacity = 1.0
    static let defaultMargin = 16.0
    static let defaultColorHex = "#FFFFFF"

    var id: UUID
    var name: String
    var text: String
    /// nil follows the text tool's default family.
    var fontFamily: String?
    var fontSize: Double
    var colorHex: String
    var opacity: Double
    var hasStroke: Bool
    var anchor: WatermarkAnchor
    var margin: Double

    static func makeNew(displayIndex: Int) -> WatermarkTemplate {
        WatermarkTemplate(
            id: UUID(),
            name: L10n.watermarkTemplateName(displayIndex),
            text: "",
            fontFamily: nil,
            fontSize: defaultFontSize,
            colorHex: defaultColorHex,
            opacity: defaultOpacity,
            hasStroke: true,
            anchor: .bottomRight,
            margin: defaultMargin
        )
    }

    func normalized(displayIndex: Int) -> WatermarkTemplate {
        var copy = self
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmedName.isEmpty ? L10n.watermarkTemplateName(displayIndex) : trimmedName
        copy.fontFamily = TextFontResolver.normalizedFamily(fontFamily)
        copy.fontSize = Self.clamp(fontSize, to: 10...100, fallback: Self.defaultFontSize)
        copy.opacity = Self.clamp(opacity, to: 0.2...1, fallback: Self.defaultOpacity)
        copy.margin = Self.clamp(margin, to: 0...160, fallback: Self.defaultMargin)
        copy.colorHex = EditorStyleDefaults.normalizedHex(colorHex) ?? Self.defaultColorHex
        return copy
    }

    static func decodedList(from data: Data) -> [WatermarkTemplate] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return rows.compactMap { row in
            guard JSONSerialization.isValidJSONObject(row),
                  let rowData = try? JSONSerialization.data(withJSONObject: row)
            else { return nil }
            return try? JSONDecoder().decode(WatermarkTemplate.self, from: rowData)
        }
    }

    static func normalizedList(_ templates: [WatermarkTemplate]) -> [WatermarkTemplate] {
        templates.prefix(maxCount).enumerated().map { index, template in
            template.normalized(displayIndex: index + 1)
        }
    }

    init(
        id: UUID,
        name: String,
        text: String,
        fontFamily: String?,
        fontSize: Double,
        colorHex: String,
        opacity: Double,
        hasStroke: Bool,
        anchor: WatermarkAnchor,
        margin: Double
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.opacity = opacity
        self.hasStroke = hasStroke
        self.anchor = anchor
        self.margin = margin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.defaultFontSize
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? Self.defaultColorHex
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? Self.defaultOpacity
        hasStroke = try container.decodeIfPresent(Bool.self, forKey: .hasStroke) ?? true
        let anchorRaw = try container.decodeIfPresent(String.self, forKey: .anchor) ?? ""
        anchor = WatermarkAnchor(rawValue: anchorRaw) ?? .bottomRight
        margin = try container.decodeIfPresent(Double.self, forKey: .margin) ?? Self.defaultMargin
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(hasStroke, forKey: .hasStroke)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(margin, forKey: .margin)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, text, fontFamily, fontSize, colorHex, opacity, hasStroke, anchor, margin
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

enum WatermarkLayout {
    static func resolvedFamily(for template: WatermarkTemplate) -> String? {
        TextFontResolver.normalizedFamily(template.fontFamily)
            ?? TextFontResolver.normalizedFamily(Defaults.textFontFamily)
    }

    static func origin(
        textSize: NSSize,
        canvasSize: NSSize,
        anchor: WatermarkAnchor,
        margin: CGFloat
    ) -> NSPoint {
        let inset = max(0, margin)
        let maxX = max(0, canvasSize.width - textSize.width)
        let maxY = max(0, canvasSize.height - textSize.height)
        let x: CGFloat
        let y: CGFloat
        switch anchor {
        case .topLeft, .left, .bottomLeft:
            x = min(inset, maxX)
        case .top, .center, .bottom:
            x = min(max(0, (canvasSize.width - textSize.width) / 2), maxX)
        case .topRight, .right, .bottomRight:
            x = max(0, canvasSize.width - textSize.width - inset)
        }
        switch anchor {
        case .bottomLeft, .bottom, .bottomRight:
            y = min(inset, maxY)
        case .left, .center, .right:
            y = min(max(0, (canvasSize.height - textSize.height) / 2), maxY)
        case .topLeft, .top, .topRight:
            y = max(0, canvasSize.height - textSize.height - inset)
        }
        return NSPoint(x: min(max(0, x), maxX), y: min(max(0, y), maxY))
    }

    static func seededAnnotation(
        enabled: Bool,
        allowsSeeding: Bool,
        template: WatermarkTemplate?,
        canvasSize: NSSize
    ) -> TextAnnotation? {
        guard enabled, allowsSeeding, let template else { return nil }
        var snapshot = template
        snapshot.fontFamily = resolvedFamily(for: template)
        return annotation(for: snapshot, canvasSize: canvasSize)
    }

    static func annotation(for template: WatermarkTemplate, canvasSize: NSSize) -> TextAnnotation? {
        let trimmed = template.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canvasSize.width > 1, canvasSize.height > 1 else { return nil }
        let normalized = template.normalized(displayIndex: 1)
        let family = resolvedFamily(for: normalized)
        let font = TextFontResolver.font(family: family, size: CGFloat(normalized.fontSize))
        let textSize = TextAnnotation.editorSize(for: template.text, font: font)
        let origin = origin(
            textSize: textSize,
            canvasSize: canvasSize,
            anchor: normalized.anchor,
            margin: CGFloat(normalized.margin)
        )
        return TextAnnotation(
            text: template.text,
            origin: origin,
            color: color(for: normalized),
            fontSize: CGFloat(normalized.fontSize),
            fontFamily: family,
            watermarkPinID: template.id,
            hasStroke: normalized.hasStroke
        )
    }

    /// Keeps a pinned watermark in its corner. A cleared pin, or content that
    /// no longer matches the template, stays where the user left it.
    static func relayout(
        _ annotations: [Annotation],
        templates: [WatermarkTemplate],
        canvasSize: NSSize
    ) -> [Annotation] {
        annotations.map { annotation in
            guard let text = annotation as? TextAnnotation,
                  let pinID = text.watermarkPinID,
                  let template = templates.first(where: { $0.id == pinID })
            else { return annotation }
            guard matchesPinnedContent(text, template: template),
                  let updated = self.annotation(for: template, canvasSize: canvasSize)
            else { return text.clearingWatermarkPin() }
            return updated.origin == text.origin ? annotation : updated
        }
    }

    static func matchesPinnedContent(_ text: TextAnnotation, template: WatermarkTemplate) -> Bool {
        let normalized = template.normalized(displayIndex: 1)
        guard text.watermarkPinID == template.id else { return false }
        guard text.text == template.text else { return false }
        guard text.fontFamily == resolvedFamily(for: normalized) else { return false }
        guard abs(text.fontSize - CGFloat(normalized.fontSize)) < 0.5 else { return false }
        guard text.hasStroke == normalized.hasStroke else { return false }
        guard !text.hasCallout, text.rotation == 0 else { return false }
        guard text.calloutTip == nil, text.secondCalloutTip == nil else { return false }
        return colorsMatch(text.color, color(for: normalized))
    }

    static func color(for template: WatermarkTemplate) -> NSColor {
        let base = EditorStyleDefaults.color(fromHex: template.colorHex) ?? .white
        let rgb = base.usingColorSpace(.sRGB) ?? base
        let opacity = WatermarkTemplate.normalizedOpacity(template.opacity)
        return rgb.withAlphaComponent(CGFloat(opacity))
    }

    private static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let left = lhs.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else {
            return false
        }
        let channels = [
            (left.redComponent, right.redComponent),
            (left.greenComponent, right.greenComponent),
            (left.blueComponent, right.blueComponent),
            (left.alphaComponent, right.alphaComponent),
        ]
        return channels.allSatisfy { abs($0.0 - $0.1) < 0.02 }
    }
}

private extension WatermarkTemplate {
    static func normalizedOpacity(_ opacity: Double) -> Double {
        guard opacity.isFinite else { return defaultOpacity }
        return min(max(opacity, 0.2), 1)
    }
}
