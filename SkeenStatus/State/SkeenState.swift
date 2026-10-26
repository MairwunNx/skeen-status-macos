import Foundation

/// The observed state of the skeen service.
nonisolated enum SkeenState: Equatable, Sendable {
    case unknown
    case running(pid: Int?, memoryMB: Int?)
    case stopped
    case unreachable
}

/// Coarse classification used by transition logic, ignoring associated values.
nonisolated enum StatePhase: String, Sendable {
    case unknown
    case running
    case stopped
    case unreachable
}

nonisolated extension SkeenState {
    var phase: StatePhase {
        switch self {
        case .unknown: return .unknown
        case .running: return .running
        case .stopped: return .stopped
        case .unreachable: return .unreachable
        }
    }

    var pid: Int? {
        if case let .running(pid, _) = self { return pid }
        return nil
    }

    var memoryMB: Int? {
        if case let .running(_, mem) = self { return mem }
        return nil
    }

    /// Short English keyword shown in the menu and status bar tooltip.
    var keyword: String {
        switch self {
        case .unknown: return "unknown"
        case .running: return "running"
        case .stopped: return "stopped"
        case .unreachable: return "unreachable"
        }
    }
}
