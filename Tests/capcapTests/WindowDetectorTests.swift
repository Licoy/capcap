import CoreGraphics
import XCTest
@testable import capcap

final class WindowDetectorTests: XCTestCase {
    private let primaryDisplay = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let secondaryDisplay = CGRect(x: 1728, y: -220, width: 1440, height: 900)
    private var statusLayer: Int { Int(CGWindowLevelForKey(.statusWindow)) }

    func testLayerZeroWindowRemainsSelectable() {
        XCTAssertEqual(
            WindowDetector.targetType(
                layer: 0,
                frame: CGRect(x: 80, y: 100, width: 800, height: 600),
                displayBounds: [primaryDisplay]
            ),
            .applicationWindow
        )
    }

    func testTopAlignedStatusWindowIsMenuBarComponentOnPrimaryDisplay() {
        XCTAssertEqual(
            WindowDetector.targetType(
                layer: statusLayer,
                frame: CGRect(x: 1410, y: 0, width: 90, height: 30),
                displayBounds: [primaryDisplay]
            ),
            .menuBarComponent
        )
    }

    func testTopAlignedStatusWindowIsMenuBarComponentOnSecondaryDisplay() {
        XCTAssertEqual(
            WindowDetector.targetType(
                layer: statusLayer,
                frame: CGRect(x: 2860, y: -220, width: 120, height: 30),
                displayBounds: [primaryDisplay, secondaryDisplay]
            ),
            .menuBarComponent
        )
    }

    func testStatusWindowAwayFromDisplayTopIsRejected() {
        XCTAssertNil(WindowDetector.targetType(
            layer: statusLayer,
            frame: CGRect(x: 1410, y: 12, width: 90, height: 30),
            displayBounds: [primaryDisplay]
        ))
    }

    func testOverHeightStatusWindowIsRejected() {
        XCTAssertNil(WindowDetector.targetType(
            layer: statusLayer,
            frame: CGRect(x: 1410, y: 0, width: 90, height: 65),
            displayBounds: [primaryDisplay]
        ))
    }

    func testWholeMenuBarIsRejected() {
        XCTAssertNil(WindowDetector.targetType(
            layer: statusLayer,
            frame: CGRect(x: 0, y: 0, width: primaryDisplay.width, height: 30),
            displayBounds: [primaryDisplay]
        ))
    }

    func testPopupMenuLayerIsElevatedWindow() {
        XCTAssertEqual(
            WindowDetector.targetType(
                layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                frame: CGRect(x: 80, y: 90, width: 240, height: 320),
                displayBounds: [primaryDisplay]
            ),
            .elevatedWindow
        )
    }

    func testCursorLayerIsRejected() {
        XCTAssertNil(WindowDetector.targetType(
            layer: Int(CGWindowLevelForKey(.cursorWindow)),
            frame: CGRect(x: 80, y: 90, width: 36, height: 51),
            displayBounds: [primaryDisplay]
        ))
    }

    func testWindowAtReturnsTopmostMenuBarComponentBeforeAppWindow() {
        let detector = WindowDetector()
        detector.apply([
            DetectedWindow(
                name: "Control Center",
                windowID: 100,
                layer: statusLayer,
                frame: CGRect(x: 1410, y: 0, width: 90, height: 30),
                target: .menuBarComponent
            ),
            DetectedWindow(
                name: "Editor",
                windowID: 200,
                layer: 0,
                frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                target: .applicationWindow
            )
        ])

        let detected = detector.windowAt(cgPoint: CGPoint(x: 1440, y: 15))

        XCTAssertEqual(detected?.windowID, 100)
        XCTAssertTrue(detector.usesCompositedScreenBackdrop(forWindowID: 100))
        XCTAssertFalse(detector.usesCompositedScreenBackdrop(forWindowID: 200))
    }

    func testWindowAtSelectsPopupMenuAboveAppWindow() {
        let detector = WindowDetector()
        detector.apply([
            DetectedWindow(
                name: "Menu",
                windowID: 100,
                layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                frame: CGRect(x: 80, y: 90, width: 240, height: 320),
                target: .elevatedWindow
            ),
            DetectedWindow(
                name: "Editor",
                windowID: 200,
                layer: 0,
                frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                target: .applicationWindow
            )
        ])

        let detected = detector.windowAt(cgPoint: CGPoint(x: 90, y: 100))

        XCTAssertEqual(detected?.windowID, 100)
        XCTAssertTrue(detector.usesCompositedScreenBackdrop(forWindowID: 100))
    }
}
