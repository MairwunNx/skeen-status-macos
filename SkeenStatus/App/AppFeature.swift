import ComposableArchitecture
import Foundation

/// The root: holds every feature and passes word between them. Features never
/// talk to each other directly; their delegate actions land here.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var monitor = MonitorFeature.State()
        var service = ServiceControlFeature.State()
        var logs = LogsFeature.State()
        var settings = SettingsFeature.State()
        var tab: SettingsTab = .overview
        /// Bumped to ask the app delegate to bring the settings window up.
        var settingsRequest = 0
    }

    enum Action {
        case launched
        case systemDidWake
        case openSettings(SettingsTab?)
        case selectTab(SettingsTab)
        case monitor(MonitorFeature.Action)
        case service(ServiceControlFeature.Action)
        case logs(LogsFeature.Action)
        case settings(SettingsFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.monitor, action: \.monitor) { MonitorFeature() }
        Scope(state: \.service, action: \.service) { ServiceControlFeature() }
        Scope(state: \.logs, action: \.logs) { LogsFeature() }
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }

        Reduce { state, action in
            switch action {
            case .launched:
                return .send(.monitor(.start))

            case .systemDidWake:
                return .send(.monitor(.systemDidWake))

            case .openSettings(let tab):
                if let tab { state.tab = tab }
                state.settingsRequest += 1
                return .none

            case .selectTab(let tab):
                state.tab = tab
                return .none

            case .monitor(.delegate(.openSettings)):
                return .send(.openSettings(.overview))

            case .monitor(.delegate(.startService)):
                return .send(.service(.run(.start)))

            case .service(.delegate(.serviceChanged)):
                return .send(.monitor(.checkNow))

            case .settings(.delegate(.saved)):
                return .send(.monitor(.configChanged))

            case .monitor, .service, .logs, .settings:
                return .none
            }
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case logs
    case connection
    case scripts
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "Overview")
        case .logs: return String(localized: "sing-box Log")
        case .connection: return String(localized: "Connection")
        case .scripts: return String(localized: "Scripts")
        case .general: return String(localized: "General")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .logs: return "text.alignleft"
        case .connection: return "network"
        case .scripts: return "applescript"
        case .general: return "gearshape"
        }
    }
}
