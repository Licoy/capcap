import Foundation

enum SaveDestination {
    /// Directory the screenshot save panel should open on.
    /// Uses the last chosen folder when memory is enabled and that folder still
    /// exists; otherwise falls back to the configured screenshot save path.
    static func screenshotSavePanelDirectory() -> URL {
        screenshotSavePanelDirectory(
            rememberLastPath: Defaults.rememberLastScreenshotSavePath,
            lastDirectory: Defaults.lastScreenshotSaveDirectory,
            defaultDirectory: Defaults.screenshotSaveDirectory,
            isExistingDirectory: isExistingDirectory
        )
    }

    static func screenshotSavePanelDirectory(
        rememberLastPath: Bool,
        lastDirectory: URL?,
        defaultDirectory: URL,
        isExistingDirectory: (URL) -> Bool
    ) -> URL {
        if rememberLastPath,
           let lastDirectory,
           isExistingDirectory(lastDirectory) {
            return lastDirectory.standardizedFileURL
        }
        return defaultDirectory.standardizedFileURL
    }

    /// Persist the folder of a file the user just picked in the save panel.
    /// Stored even when memory is off so turning the setting on later can reuse it.
    static func rememberScreenshotSaveDirectory(fromFileURL url: URL) {
        let directory = url.deletingLastPathComponent().standardizedFileURL
        guard !directory.path.isEmpty else { return }
        Defaults.lastScreenshotSaveDirectory = directory
    }

    static func isExistingDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    static func uniqueFile(in directory: URL, fileName: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let original = directory.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: original.path) else {
            return original
        }

        let nameParts = splitFileName(fileName)
        let rawBase = nameParts.base
        let fileExtension = nameParts.fileExtension
        let base = rawBase.isEmpty ? "capcap" : rawBase

        for index in 2...999 {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(base) \(index)"
            } else {
                candidateName = "\(base) \(index).\(fileExtension)"
            }

            let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let token = UUID().uuidString.prefix(8).lowercased()
        let fallbackName: String
        if fileExtension.isEmpty {
            fallbackName = "\(base)-\(token)"
        } else {
            fallbackName = "\(base)-\(token).\(fileExtension)"
        }
        return directory.appendingPathComponent(fallbackName, isDirectory: false)
    }

    private static func splitFileName(_ fileName: String) -> (base: String, fileExtension: String) {
        let compressedSuffix = ".compressed.png"
        if fileName.lowercased().hasSuffix(compressedSuffix) {
            let end = fileName.index(fileName.endIndex, offsetBy: -compressedSuffix.count)
            return (String(fileName[..<end]), "compressed.png")
        }

        let nsName = fileName as NSString
        return (nsName.deletingPathExtension, nsName.pathExtension)
    }
}
