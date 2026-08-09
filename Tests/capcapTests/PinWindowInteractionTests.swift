import AppKit
import XCTest
@testable import capcap

@MainActor
final class PinWindowInteractionTests: XCTestCase {
    func testImagePinAcceptsActivationMouseDown() {
        let view = PinContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))

        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }
}
