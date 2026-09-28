import AppKit
import XCTest
@testable import capcap

final class WatermarkLayoutTests: XCTestCase {
    private let textSize = NSSize(width: 20, height: 10)
    private let canvasSize = NSSize(width: 100, height: 80)

    func testAnchorsPlaceTextInsideTheMargin() {
        let margin: CGFloat = 8
        let expected: [WatermarkAnchor: NSPoint] = [
            .bottomLeft: NSPoint(x: 8, y: 8),
            .bottom: NSPoint(x: 40, y: 8),
            .bottomRight: NSPoint(x: 72, y: 8),
            .left: NSPoint(x: 8, y: 35),
            .center: NSPoint(x: 40, y: 35),
            .right: NSPoint(x: 72, y: 35),
            .topLeft: NSPoint(x: 8, y: 62),
            .top: NSPoint(x: 40, y: 62),
            .topRight: NSPoint(x: 72, y: 62),
        ]
        for anchor in WatermarkAnchor.allCases {
            XCTAssertEqual(
                WatermarkLayout.origin(
                    textSize: textSize,
                    canvasSize: canvasSize,
                    anchor: anchor,
                    margin: margin
                ),
                expected[anchor]
            )
        }
    }

    func testOversizedTextStaysAtTheOrigin() {
        let origin = WatermarkLayout.origin(
            textSize: NSSize(width: 200, height: 200),
            canvasSize: canvasSize,
            anchor: .topRight,
            margin: 30
        )
        XCTAssertEqual(origin, .zero)
    }

    func testTemplateJSONDropsInvalidRowsAndClampsValues() throws {
        let id = UUID()
        let json = """
        [
          {"id":"\(id.uuidString)","name":"","text":"Hi","fontSize":1000,"opacity":5,"margin":-4,"anchor":"nope","colorHex":"zz"},
          {"name":"missing id","text":"Skip"}
        ]
        """
        let list = WatermarkTemplate.normalizedList(WatermarkTemplate.decodedList(from: Data(json.utf8)))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, id)
        XCTAssertEqual(list[0].fontSize, 100)
        XCTAssertEqual(list[0].opacity, 1)
        XCTAssertEqual(list[0].margin, 0)
        XCTAssertEqual(list[0].anchor, .bottomRight)
        XCTAssertEqual(list[0].colorHex, "#FFFFFF")
        XCTAssertFalse(list[0].name.isEmpty)

        let data = try JSONEncoder().encode(list)
        let again = WatermarkTemplate.normalizedList(WatermarkTemplate.decodedList(from: data))
        XCTAssertEqual(again, list)
    }

    func testPinnedWatermarkMovesUntilThePinIsCleared() throws {
        let template = sampleTemplate(text: "Hi", anchor: .bottomRight)
        let placed = try XCTUnwrap(WatermarkLayout.annotation(
            for: template,
            canvasSize: NSSize(width: 200, height: 100)
        ))
        let moved = try XCTUnwrap(WatermarkLayout.relayout(
            [placed],
            templates: [template],
            canvasSize: NSSize(width: 400, height: 240)
        ).first as? TextAnnotation)
        XCTAssertGreaterThan(moved.origin.x, placed.origin.x)
        XCTAssertEqual(moved.watermarkPinID, template.id)

        let dragged = try XCTUnwrap(
            placed.clearingWatermarkPin().translated(by: NSPoint(x: 12, y: 4)) as? TextAnnotation
        )
        let stayed = try XCTUnwrap(WatermarkLayout.relayout(
            [dragged],
            templates: [template],
            canvasSize: NSSize(width: 400, height: 240)
        ).first as? TextAnnotation)
        XCTAssertEqual(stayed.origin, dragged.origin)
        XCTAssertNil(stayed.watermarkPinID)
    }

    func testSeedingSkipsDisabledBlankAndPresetEditing() {
        let template = sampleTemplate(text: "Hi", anchor: .bottomLeft)
        let canvas = NSSize(width: 240, height: 160)
        XCTAssertNotNil(WatermarkLayout.seededAnnotation(
            enabled: true,
            allowsSeeding: true,
            template: template,
            canvasSize: canvas
        ))
        XCTAssertNil(WatermarkLayout.seededAnnotation(
            enabled: false,
            allowsSeeding: true,
            template: template,
            canvasSize: canvas
        ))
        XCTAssertNil(WatermarkLayout.seededAnnotation(
            enabled: true,
            allowsSeeding: false,
            template: template,
            canvasSize: canvas
        ))
        var blank = template
        blank.text = " \n "
        XCTAssertNil(WatermarkLayout.seededAnnotation(
            enabled: true,
            allowsSeeding: true,
            template: blank,
            canvasSize: canvas
        ))
    }

    private func sampleTemplate(text: String, anchor: WatermarkAnchor) -> WatermarkTemplate {
        WatermarkTemplate(
            id: UUID(),
            name: "Mark",
            text: text,
            fontFamily: TextFontResolver.availableFamilies().contains("Helvetica") ? "Helvetica" : nil,
            fontSize: 20,
            colorHex: "#FFFFFF",
            opacity: 1,
            hasStroke: false,
            anchor: anchor,
            margin: 8
        )
    }
}
