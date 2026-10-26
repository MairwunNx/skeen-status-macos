import Foundation

/// Reads and writes the JSON config in Application Support with 0600 perms.
nonisolated enum ConfigStore {
    static let appFolderName = "skeen-status-macos"
    static let fileName = "config.json"

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appFolderName, isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return .default
        }
        return config
    }

    static func save(_ config: Config) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            NSLog("ConfigStore save failed: \(error)")
        }
    }
}
