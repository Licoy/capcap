import CoreGraphics
import XCTest
@testable import capcap

final class WindowDetectorTests: XCTestCase {
    func testWindowAtIgnoresTransientSurfacesAboveAppWindows() {
        let detector = WindowDetector()
        detector.apply([
            DetectedWindow(
                name: "Cursor",
                windowID: 100,
                layer: 101,
                frame: CGRect(x: 80, y: 90, width: 36, height: 51)
            ),
            DetectedWindow(
                name: "Editor",
                windowID: 200,
                layer: 0,
                frame: CGRect(x: 0, y: 0, width: 600, height: 400)
            )
        ])

        let detected = detector.windowAt(cgPoint: CGPoint(x: 90, y: 100))

        XCTAssertEqual(detected?.windowID, 200)
    }

    func testWindowAtDoesNotReturnOnlyTransientSurface() {
        let detector = WindowDetector()
        detector.apply([
            DetectedWindow(
                name: "Insertion Point",
                windowID: 300,
                layer: 25,
                frame: CGRect(x: 80, y: 90, width: 36, height: 51)
            )
        ])

        XCTAssertNil(detector.windowAt(cgPoint: CGPoint(x: 90, y: 100)))
    }
}
