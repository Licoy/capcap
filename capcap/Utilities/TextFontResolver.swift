import AppKit

/// Resolves the screenshot text tool's font from a family name.
///
/// An empty or unknown family keeps the historical system bold face so existing
/// annotations do not change appearance. A chosen family uses its regular face;
/// synthetic bold makes CJK families look blurred.
enum TextFontResolver {
    private static var cachedFamilies: [String]?

    static func availableFamilies() -> [String] {
        if let cachedFamilies { return cachedFamilies }
        let families = NSFontManager.shared.availableFontFamilies
            .filter { family in
                NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13) != nil
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        cachedFamilies = families
        return families
    }

    /// Installed family, or nil when the name is blank or not on this Mac.
    static func normalizedFamily(_ family: String?) -> String? {
        guard let trimmed = family?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return availableFamilies().contains(trimmed) ? trimmed : nil
    }

    static func font(family: String?, size: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let family = normalizedFamily(family) else { return fallback }
        return NSFontManager.shared.font(
            withFamily: family,
            traits: [],
            weight: 5,
            size: size
        ) ?? fallback
    }
}
