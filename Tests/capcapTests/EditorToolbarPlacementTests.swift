import AppKit
import XCTest
@testable import capcap

final class EditorToolbarPlacementTests: XCTestCase {
    private let bounds = NSRect(x: 0, y: 0, width: 1_512, height: 982)
    private let toolbarSize = NSSize(width: 720, height: 44)

    func testPrimaryToolbarReservesTopSafeInsetWhenSelectionFillsScreen() {
        let rect = EditorToolbarPlacement.primaryToolbarRect(
            referenceRect: bounds,
            in: bounds,
            size: toolbarSize,
            topSafeInset: 38
        )

        XCTAssertEqual(rect.maxY, bounds.maxY - 38 - 8, accuracy: 0.001)
        XCTAssertEqual(rect.midX, bounds.midX, accuracy: 0.001)
    }

    func testPrimaryToolbarKeepsEdgeMarginWithoutTopSafeInset() {
        let rect = EditorToolbarPlacement.primaryToolbarRect(
            referenceRect: bounds,
            in: bounds,
            size: toolbarSize,
            topSafeInset: 0
        )

        XCTAssertEqual(rect.maxY, bounds.maxY - 8, accuracy: 0.001)
    }

    func testPrimaryToolbarBelowSelectionIsUnaffectedByTopSafeInset() {
        let selection = NSRect(x: 200, y: 300, width: 900, height: 500)
        let rect = EditorToolbarPlacement.primaryToolbarRect(
            referenceRect: selection,
            in: bounds,
            size: toolbarSize,
            topSafeInset: 38
        )

        XCTAssertEqual(rect.maxY, selection.minY - 8, accuracy: 0.001)
    }
}
