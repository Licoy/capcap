import AppKit
import ApplicationServices
import CoreGraphics
import XCTest
@testable import capcap

final class MenuBarExtraCatalogTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testRejectsFullMenuBarAndExtrasStrip() {
        XCTAssertFalse(MenuBarExtraGeometry.isIndividualExtra(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 30),
            displayBounds: [display]
        ))
        XCTAssertFalse(MenuBarExtraGeometry.isIndividualExtra(
            frame: CGRect(x: 1665, y: 0, width: 875, height: 30),
            displayBounds: [display]
        ))
    }

    func testAcceptsClockAndStatusItemSlots() {
        XCTAssertTrue(MenuBarExtraGeometry.isIndividualExtra(
            frame: CGRect(x: 2415, y: 0, width: 125, height: 30),
            displayBounds: [display]
        ))
        XCTAssertTrue(MenuBarExtraGeometry.isIndividualExtra(
            frame: CGRect(x: 2293, y: 0, width: 22, height: 30),
            displayBounds: [display]
        ))
        XCTAssertTrue(MenuBarExtraGeometry.isIndividualExtra(
            frame: CGRect(x: 2416, y: 4, width: 124, height: 22),
            displayBounds: [display]
        ))
    }

    func testCatalogDiscoversMenuBarAgentExtrasWhenAvailable() {
        guard AXIsProcessTrusted(),
              NSWorkspace.shared.runningApplications.contains(where: {
                  $0.bundleIdentifier == "com.apple.MenuBarAgent"
              })
        else { return }

        let bounds = [CGDisplayBounds(CGMainDisplayID())]
        let frames = MenuBarExtraCatalog.frames(displayBounds: bounds)
        XCTAssertFalse(
            frames.isEmpty,
            "MenuBarAgent extras should be enumerable when Accessibility is trusted"
        )
        XCTAssertTrue(frames.allSatisfy { $0.width <= MenuBarExtraGeometry.maxWidth })
        XCTAssertTrue(frames.allSatisfy {
            MenuBarExtraGeometry.isIndividualExtra(frame: $0, displayBounds: bounds)
        })
    }

    func testUniquedKeepsTallerOverlappingSlot() {
        let uniqued = MenuBarExtraGeometry.uniqued([
            CGRect(x: 2416, y: 4, width: 124, height: 22),
            CGRect(x: 2415, y: 0, width: 125, height: 30)
        ])
        XCTAssertEqual(uniqued, [CGRect(x: 2415, y: 0, width: 125, height: 30)])
    }
}

final class WindowDetectorMenuBarExtraTests: XCTestCase {
    func testInjectedMenuBarExtrasAreSelectableWhenCGWindowsOmitThem() throws {
        let extra = CGRect(x: 2400, y: 0, width: 80, height: 30)
        let context = WindowDetectionContext(
            primaryScreenArea: 2560 * 1440,
            displayBounds: [CGRect(x: 0, y: 0, width: 2560, height: 1440)],
            menuBarExtras: [extra]
        )

        let windows = try WindowDetector.snapshot(context: context).get()
        let detector = WindowDetector()
        detector.apply(windows)

        let hit = detector.windowAt(cgPoint: CGPoint(x: 2440, y: 10))
        XCTAssertEqual(hit?.target, .menuBarComponent)
        XCTAssertEqual(hit?.frame, extra)
        XCTAssertTrue(detector.usesCompositedScreenBackdrop(forWindowID: try XCTUnwrap(hit?.windowID)))
    }

    func testMainMenuWindowLayerIndividualComponentIsSelectable() {
        XCTAssertEqual(
            WindowDetector.targetType(
                layer: Int(CGWindowLevelForKey(.mainMenuWindow)),
                frame: CGRect(x: 2293, y: 0, width: 22, height: 30),
                displayBounds: [CGRect(x: 0, y: 0, width: 2560, height: 1440)]
            ),
            .menuBarComponent
        )
        XCTAssertNil(
            WindowDetector.targetType(
                layer: Int(CGWindowLevelForKey(.mainMenuWindow)),
                frame: CGRect(x: 0, y: 0, width: 2560, height: 30),
                displayBounds: [CGRect(x: 0, y: 0, width: 2560, height: 1440)]
            )
        )
    }
}
