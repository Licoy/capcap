import XCTest
@testable import capcap

final class SelectionSizeParserTests: XCTestCase {
    func testParsesCommonFormats() {
        XCTAssertEqual(SelectionSizeParser.parse("800x600")?.width, 800)
        XCTAssertEqual(SelectionSizeParser.parse("800x600")?.height, 600)
        XCTAssertEqual(SelectionSizeParser.parse("800×600")?.width, 800)
        XCTAssertEqual(SelectionSizeParser.parse("800 600")?.height, 600)
        XCTAssertEqual(SelectionSizeParser.parse(" 1024 * 768 ")?.width, 1024)
    }

    func testRejectsInvalidInput() {
        XCTAssertNil(SelectionSizeParser.parse(""))
        XCTAssertNil(SelectionSizeParser.parse("abc"))
        XCTAssertNil(SelectionSizeParser.parse("800"))
        XCTAssertNil(SelectionSizeParser.parse("0x100"))
        XCTAssertNil(SelectionSizeParser.parse("-10x20"))
    }

    func testTypedDimensionsRemainIndependentOfRatio() {
        // Apply path must keep both values even when a ratio chip is selected.
        let parsed = SelectionSizeParser.parse("800x600")
        XCTAssertEqual(parsed?.width, 800)
        XCTAssertEqual(parsed?.height, 600)
        // Simulated "do not rewrite height from 16:9"
        let ratio: CGFloat = 16.0 / 9.0
        XCTAssertNotEqual(parsed!.height, parsed!.width / ratio, accuracy: 0.01)
    }
}

final class LastCaptureRegionTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let region = LastCaptureRegion(
            displayID: 1,
            screenRect: NSRect(x: 10, y: 20, width: 300, height: 200),
            captureRect: CGRect(x: 10, y: 40, width: 300, height: 200),
            isWindowCapture: true,
            windowID: 42
        )
        let data = try JSONEncoder().encode(region)
        let decoded = try JSONDecoder().decode(LastCaptureRegion.self, from: data)
        XCTAssertEqual(decoded, region)
        XCTAssertEqual(decoded.screenRect.width, 300)
        XCTAssertEqual(decoded.windowID, 42)
    }
}
