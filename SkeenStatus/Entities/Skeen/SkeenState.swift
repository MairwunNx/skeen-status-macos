import ComposableArchitecture
import Foundation

/// What `skeen status` told about the sing-box process.
struct SkeenProcess: Equatable, Sendable {
    var pid: Int?
    var memoryMB: Int?
    /// skeen's own uptime text, e.g. `18d 8h 51m`.
    var uptime: String?
}

/// The observed state of the skeen service.
enum SkeenState: Equatable, Sendable {
    case unknown
    case running(SkeenProcess)
    case stopped
    case unreachable
}

/// Coarse classification used by transition logic, ignoring associated values.
enum StatePhase: String, Codable, Sendable {
    case unknown
    case running
    case stopped
    case unreachable
}

extension SkeenState {
    var phase: StatePhase {
        switch self {
        case .unknown: return .unknown
        case .running: return .running
        case .stopped: return .stopped
        case .unreachable: return .unreachable
        }
    }

    var process: SkeenProcess? {
        if case let .running(process) = self { return process }
        return nil
    }

    /// Short Russian word for the menu, the tooltip, and the settings window.
    var title: String {
        switch self {
        case .unknown: return "проверяю…"
        case .running: return "работает"
        case .stopped: return "остановлен"
        case .unreachable: return "роутер недоступен"
        }
    }
}

/// Abstract status color, mapped to NSColor or SwiftUI Color at the edges.
enum StatusColor: Equatable, Sendable {
    case green
    case red
    case yellow
    case gray
}

func statusColor(for state: SkeenState) -> StatusColor {
    switch state.phase {
    case .running: return .green
    case .stopped: return .red
    case .unreachable: return .yellow
    case .unknown: return .gray
    }
}

/// The latest word on skeen, written by the monitor and read everywhere else.
struct SkeenSnapshot: Equatable, Sendable {
    var state: SkeenState = .unknown
    var lastCheck: Date?
    /// Why the last check failed, in Russian; nil when it went through.
    var lastError: String?
    /// When the current phase began, for uptime and downtime in banners.
    var phaseSince: Date?
    var version: SkeenVersion?
}

extension SharedKey where Self == InMemoryKey<SkeenSnapshot>.Default {
    static var skeenSnapshot: Self {
        Self[.inMemory("skeenSnapshot"), default: SkeenSnapshot()]
    }
}
