import Foundation
import XCTest
@testable import capcap

/// Structural checks that the shipped fork identity and update source stay on
/// Licoy/capcap (not upstream realskyrin / cn.skyrin).
final class ForkIdentityTests: XCTestCase {
    private var repositoryRoot: URL {
        // Tests/capcapTests/ThisFile.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testUpdateCheckerRepositoryIsLicoyFork() {
        XCTAssertEqual(UpdateChecker.githubRepository, "Licoy/capcap")
    }

    func testNormalizeVersionStripsVPrefixUsedByBump() {
        XCTAssertEqual(UpdateChecker.normalizeVersion("v1.0.0"), "1.0.0")
        XCTAssertEqual(UpdateChecker.normalizeVersion("V1.2.3"), "1.2.3")
        // Legacy upstream-style tags still parse if encountered
        XCTAssertEqual(UpdateChecker.normalizeVersion("release-v1.7.4"), "1.7.4")
    }

    func testAppInfoPlistIdentityAndVersion() throws {
        let plistURL = repositoryRoot.appendingPathComponent("capcap/App/Info.plist")
        let dict = try loadPlist(plistURL)

        XCTAssertEqual(dict["CFBundleIdentifier"] as? String, "com.github.licoy.capcap.desktop")
        XCTAssertEqual(dict["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(dict["CFBundleVersion"] as? String, "1000000")

        let urlTypes = try XCTUnwrap(dict["CFBundleURLTypes"] as? [[String: Any]])
        let urlName = urlTypes.first?["CFBundleURLName"] as? String
        XCTAssertEqual(urlName, "com.github.licoy.capcap.desktop.edit")
        XCTAssertFalse((urlName ?? "").contains("cn.skyrin"))
    }

    func testShareExtensionInfoPlistIdentityAndVersion() throws {
        let plistURL = repositoryRoot.appendingPathComponent("capcap-share-extension/Info.plist")
        let dict = try loadPlist(plistURL)

        XCTAssertEqual(
            dict["CFBundleIdentifier"] as? String,
            "com.github.licoy.capcap.desktop.ShareExtension"
        )
        XCTAssertEqual(dict["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(dict["CFBundleVersion"] as? String, "1000000")
        XCTAssertTrue((dict["CFBundleIdentifier"] as? String ?? "").hasPrefix("com.github.licoy.capcap.desktop"))
    }

    private func loadPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any], "Expected dictionary plist at \(url.path)")
    }
}
