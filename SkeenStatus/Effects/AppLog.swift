import Foundation

/// Thin append-only file logger with size-based rotation, living in
/// Application Support next to the config.
nonisolated final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    private let queue = DispatchQueue(label: "skeen-status.log")
    private let maxBytes = 512 * 1024
    private let fileURL: URL
    private let rotatedURL: URL
    private let formatter: DateFormatter

    init() {
        let dir = ConfigStore.directoryURL
        fileURL = dir.appendingPathComponent("skeen-status.log")
        rotatedURL = dir.appendingPathComponent("skeen-status.log.1")
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var url: URL { fileURL }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async { [self] in
            rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: [.atomic])
            }
        }
    }

    private func rotateIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }
}
