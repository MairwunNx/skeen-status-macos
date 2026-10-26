import ComposableArchitecture
import Foundation

/// Keeps the chart history in `metrics.json` next to the config, so the
/// overview remembers more than the current launch.
@DependencyClient
struct MetricsStore: Sendable {
    var load: @Sendable () -> [MetricSample] = { [] }
    var save: @Sendable (_ history: [MetricSample]) -> Void
}

extension MetricsStore: DependencyKey {
    static var fileURL: URL {
        AppLog.directoryURL.appendingPathComponent("metrics.json")
    }

    static let liveValue = MetricsStore(
        load: {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder().decode([MetricSample].self, from: data)) ?? []
        },
        save: { history in
            guard let data = try? JSONEncoder().encode(history) else { return }
            try? FileManager.default.createDirectory(at: AppLog.directoryURL, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: [.atomic])
        }
    )

    static let testValue = MetricsStore(load: { [] }, save: { _ in })
}

extension DependencyValues {
    var metricsStore: MetricsStore {
        get { self[MetricsStore.self] }
        set { self[MetricsStore.self] = newValue }
    }
}
