import AppKit
import CryptoKit
import Foundation

enum InstallManager {

    static func verifySHA256(fileURL: URL, expected: String) throws {
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        let hexString = hash.compactMap { String(format: "%02x", $0) }.joined()

        if hexString.lowercased() != expected.lowercased() {
            throw InstallerError.sha256Mismatch
        }
    }

    static func install(zipURL: URL) throws -> URL {
        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory.appendingPathComponent("FazmExtract-\(UUID().uuidString)")

        // Extract ZIP using ditto (preserves code signatures, resource forks, etc.)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, extractDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw InstallerError.extractionFailed
        }

        // Find Fazm.app in extracted contents
        let appName = "Fazm.app"
        let appURL = findApp(named: appName, in: extractDir)

        guard let sourceApp = appURL else {
            throw InstallerError.appNotFound
        }

        // Remove old installations
        let applicationsDir = URL(fileURLWithPath: "/Applications")
        let targetApp = applicationsDir.appendingPathComponent(appName)

        // Remove old Fazm
        if fm.fileExists(atPath: targetApp.path) {
            try fm.removeItem(at: targetApp)
        }

        // Remove legacy Omi installations
        for legacy in ["Omi.app", "omi.app"] {
            let legacyPath = applicationsDir.appendingPathComponent(legacy)
            if fm.fileExists(atPath: legacyPath.path) {
                try? fm.removeItem(at: legacyPath)
            }
        }

        // Move to /Applications using ditto (preserves everything)
        let installProcess = Process()
        installProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        installProcess.arguments = [sourceApp.path, targetApp.path]
        try installProcess.run()
        installProcess.waitUntilExit()

        guard installProcess.terminationStatus == 0 else {
            throw InstallerError.installFailed("Failed to copy app to /Applications")
        }

        // Cleanup temp files
        try? fm.removeItem(at: zipURL)
        try? fm.removeItem(at: extractDir)

        return targetApp
    }

    static func launch(appURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error = error {
                print("Failed to launch app: \(error)")
            }
        }
    }

    // Recursively find the .app bundle
    private static func findApp(named name: String, in directory: URL) -> URL? {
        let fm = FileManager.default
        let directPath = directory.appendingPathComponent(name)
        if fm.fileExists(atPath: directPath.path) {
            return directPath
        }

        // Search one level deep (ZIP might have a top-level folder)
        if let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            for item in contents {
                let nested = item.appendingPathComponent(name)
                if fm.fileExists(atPath: nested.path) {
                    return nested
                }
            }
        }
        return nil
    }
}
