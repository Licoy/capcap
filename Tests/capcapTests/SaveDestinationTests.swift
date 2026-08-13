import XCTest
@testable import capcap

final class SaveDestinationTests: XCTestCase {
    private let last = URL(fileURLWithPath: "/tmp/capcap-last-shots", isDirectory: true)
    private let fallback = URL(fileURLWithPath: "/tmp/capcap-default-shots", isDirectory: true)

    func testPanelUsesConfiguredPathWhenMemoryIsOff() {
        let directory = SaveDestination.screenshotSavePanelDirectory(
            rememberLastPath: false,
            lastDirectory: last,
            defaultDirectory: fallback,
            isExistingDirectory: { _ in true }
        )
        XCTAssertEqual(directory, fallback.standardizedFileURL)
    }

    func testPanelUsesLastPathWhenMemoryIsOnAndFolderExists() {
        let directory = SaveDestination.screenshotSavePanelDirectory(
            rememberLastPath: true,
            lastDirectory: last,
            defaultDirectory: fallback,
            isExistingDirectory: { $0.standardizedFileURL == self.last.standardizedFileURL }
        )
        XCTAssertEqual(directory, last.standardizedFileURL)
    }

    func testPanelFallsBackWhenLastPathIsMissing() {
        let directory = SaveDestination.screenshotSavePanelDirectory(
            rememberLastPath: true,
            lastDirectory: last,
            defaultDirectory: fallback,
            isExistingDirectory: { _ in false }
        )
        XCTAssertEqual(directory, fallback.standardizedFileURL)
    }

    func testPanelFallsBackWhenLastPathIsNil() {
        let directory = SaveDestination.screenshotSavePanelDirectory(
            rememberLastPath: true,
            lastDirectory: nil,
            defaultDirectory: fallback,
            isExistingDirectory: { _ in true }
        )
        XCTAssertEqual(directory, fallback.standardizedFileURL)
    }
}

final class RememberLastScreenshotSavePathDefaultsTests: XCTestCase {
    private let rememberKey = "rememberLastScreenshotSavePath"
    private let lastPathKey = "lastScreenshotSaveDirectory"
    private var previousValues: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in [rememberKey, lastPathKey] {
            previousValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in [rememberKey, lastPathKey] {
            if let value = previousValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testRememberLastScreenshotSavePathDefaultsToOff() {
        XCTAssertFalse(Defaults.rememberLastScreenshotSavePath)
    }

    func testLastScreenshotSaveDirectoryRoundTrip() {
        XCTAssertNil(Defaults.lastScreenshotSaveDirectory)

        let stored = URL(fileURLWithPath: "/tmp/capcap-remembered", isDirectory: true)
        Defaults.lastScreenshotSaveDirectory = stored
        XCTAssertEqual(Defaults.lastScreenshotSaveDirectory, stored.standardizedFileURL)

        Defaults.lastScreenshotSaveDirectory = nil
        XCTAssertNil(Defaults.lastScreenshotSaveDirectory)
    }
}
