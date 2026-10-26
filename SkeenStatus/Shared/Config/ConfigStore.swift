import ComposableArchitecture
import Foundation

/// Reads and writes `config.json` in Application Support with mode `0600`.
@DependencyClient
struct ConfigStore: Sendable {
    var load: @Sendable () -> Config = { .default }
    var save: @Sendable (_ config: Config) throws -> Void
}

extension ConfigStore: DependencyKey {
    static var fileURL: URL {
        AppLog.directoryURL.appendingPathComponent("config.json")
    }

    static let liveValue = ConfigStore(
        load: {
            guard let data = try? Data(contentsOf: fileURL),
                  let config = try? JSONDecoder().decode(Config.self, from: data) else {
                return .default
            }
            return config
        },
        save: { config in
            try FileManager.default.createDirectory(at: AppLog.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    )

    static let testValue = ConfigStore(load: { .default }, save: { _ in })

    static func inMemory(_ initial: Config = .default) -> ConfigStore {
        let storage = LockIsolated(initial)
        return ConfigStore(load: { storage.value }, save: { storage.setValue($0) })
    }
}

extension DependencyValues {
    var configStore: ConfigStore {
        get { self[ConfigStore.self] }
        set { self[ConfigStore.self] = newValue }
    }
}

/// `@Shared(.config)`: the one config every feature reads, saved to disk on
/// every change.
struct ConfigKey: SharedKey {
    var id: String { "config" }

    func load(context: LoadContext<Config>, continuation: LoadContinuation<Config>) {
        @Dependency(\.configStore) var store
        continuation.resume(returning: store.load())
    }

    func subscribe(context: LoadContext<Config>, subscriber: SharedSubscriber<Config>) -> SharedSubscription {
        SharedSubscription {}
    }

    func save(_ value: Config, context: SaveContext, continuation: SaveContinuation) {
        @Dependency(\.configStore) var store
        do {
            try store.save(value)
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

extension SharedKey where Self == ConfigKey.Default {
    static var config: Self {
        Self[ConfigKey(), default: .default]
    }
}
