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
        let dict = try loadPlist(repositoryRoot.appendingPathComponent("capcap/App/Info.plist"))

        XCTAssertEqual(dict["CFBundleIdentifier"] as? String, "com.github.licoy.capcap.desktop")
        try assertMarketingVersionMatchesBuild(in: dict)

        let urlTypes = try XCTUnwrap(dict["CFBundleURLTypes"] as? [[String: Any]])
        let urlName = urlTypes.first?["CFBundleURLName"] as? String
        XCTAssertEqual(urlName, "com.github.licoy.capcap.desktop.edit")
        XCTAssertFalse((urlName ?? "").contains("cn.skyrin"))
    }

    func testShareExtensionInfoPlistIdentityAndVersion() throws {
        let app = try loadPlist(repositoryRoot.appendingPathComponent("capcap/App/Info.plist"))
        let dict = try loadPlist(
            repositoryRoot.appendingPathComponent("capcap-share-extension/Info.plist")
        )

        XCTAssertEqual(
            dict["CFBundleIdentifier"] as? String,
            "com.github.licoy.capcap.desktop.ShareExtension"
        )
        XCTAssertTrue((dict["CFBundleIdentifier"] as? String ?? "").hasPrefix("com.github.licoy.capcap.desktop"))
        try assertMarketingVersionMatchesBuild(in: dict)
        XCTAssertEqual(
            dict["CFBundleShortVersionString"] as? String,
            app["CFBundleShortVersionString"] as? String
        )
        XCTAssertEqual(dict["CFBundleVersion"] as? String, app["CFBundleVersion"] as? String)
    }

    /// `bump.sh` encodes x.y.z as `major * 1_000_000 + minor * 1_000 + patch`.
    /// Read the live plists instead of pinning a release number so version
    /// bumps do not break CI.
    private func assertMarketingVersionMatchesBuild(
        in dict: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let version = try XCTUnwrap(dict["CFBundleShortVersionString"] as? String, file: file, line: line)
        let build = try XCTUnwrap(dict["CFBundleVersion"] as? String, file: file, line: line)
        let parts = version.split(separator: ".").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 3, "Expected x.y.z marketing version, got \(version)", file: file, line: line)
        guard parts.count == 3 else { return }
        let expectedBuild = parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2]
        XCTAssertEqual(build, String(expectedBuild), file: file, line: line)
    }

    private func loadPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any], "Expected dictionary plist at \(url.path)")
    }
}
