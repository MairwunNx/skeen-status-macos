import ComposableArchitecture
import Foundation

/// The app's own diagnostic log in Application Support, next to the config,
/// rotated at 512 KB.
@DependencyClient
struct AppLog: Sendable {
    var write: @Sendable (_ message: String) -> Void
    var url: @Sendable () -> URL = { URL(fileURLWithPath: "/dev/null") }
}

extension AppLog: DependencyKey {
    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("skeen-status-macos", isDirectory: true)
    }

    static let liveValue: AppLog = {
        let file = AppLogFile(directory: directoryURL)
        return AppLog(write: { file.append($0) }, url: { file.url })
    }()

    static let testValue = AppLog(write: { _ in }, url: { URL(fileURLWithPath: "/dev/null") })
}

extension DependencyValues {
    var appLog: AppLog {
        get { self[AppLog.self] }
        set { self[AppLog.self] = newValue }
    }
}

private final class AppLogFile: Sendable {
    let url: URL
    private let rotatedURL: URL
    private let queue = DispatchQueue(label: "skeen-status.log")
    private let maxBytes = 512 * 1024

    init(directory: URL) {
        url = directory.appendingPathComponent("skeen-status.log")
        rotatedURL = directory.appendingPathComponent("skeen-status.log.1")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func append(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async { [url, rotatedURL, maxBytes] in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size > maxBytes {
                try? FileManager.default.removeItem(at: rotatedURL)
                try? FileManager.default.moveItem(at: url, to: rotatedURL)
            }
            let data = Data(line.utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: [.atomic])
            }
        }
    }
}
