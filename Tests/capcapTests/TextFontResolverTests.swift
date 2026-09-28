import AppKit
import XCTest
@testable import capcap

final class TextFontResolverTests: XCTestCase {
    func testMissingFamilyUsesSystemBold() {
        let size: CGFloat = 18
        let expected = NSFont.systemFont(ofSize: size, weight: .bold).fontName
        XCTAssertEqual(TextFontResolver.font(family: nil, size: size).fontName, expected)
        XCTAssertEqual(TextFontResolver.font(family: "   ", size: size).fontName, expected)
        XCTAssertEqual(TextFontResolver.font(family: "NotARealFontFamilyZZZ", size: size).fontName, expected)
        XCTAssertNil(TextFontResolver.normalizedFamily("NotARealFontFamilyZZZ"))
    }

    func testInstalledFamilyKeepsItsName() throws {
        guard TextFontResolver.availableFamilies().contains("Helvetica") else { return }
        let font = TextFontResolver.font(family: "Helvetica", size: 18)
        XCTAssertEqual(font.familyName, "Helvetica")
        XCTAssertNotEqual(font.fontName, NSFont.systemFont(ofSize: 18, weight: .bold).fontName)
    }
}
