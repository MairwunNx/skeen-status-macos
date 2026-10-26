import Foundation

/// Native notification variants, chosen purely from a state transition.
enum NotificationKind: Equatable, Sendable {
    case down
    case recovered
    case unreachable
    /// The first check after launch found skeen stopped.
    case stoppedAtLaunch
}

/// Side effects produced by a state transition; executed by the monitor.
enum SideEffect: Equatable, Sendable {
    case runDownScripts
    case runRecoverScripts
    case notify(NotificationKind)
}

/// Computes the side effects for a state change. Scripts fire only on the
/// real running↔stopped edges; unreachable triggers scripts only when
/// `treatUnreachableAsDown` is enabled (mapping unreachable onto stopped).
func transition(
    from old: SkeenState,
    to new: SkeenState,
    treatUnreachableAsDown: Bool
) -> [SideEffect] {
    let oldPhase = old.phase
    let newPhase = new.phase
    guard oldPhase != newPhase else { return [] }

    if oldPhase == .unknown, newPhase == .stopped {
        return [.notify(.stoppedAtLaunch)]
    }

    func effective(_ phase: StatePhase) -> StatePhase {
        if treatUnreachableAsDown, phase == .unreachable { return .stopped }
        return phase
    }

    let eo = effective(oldPhase)
    let en = effective(newPhase)
    var effects: [SideEffect] = []

    if eo == .running, en == .stopped {
        effects.append(.runDownScripts)
        effects.append(.notify(.down))
    } else if eo == .stopped, en == .running {
        effects.append(.runRecoverScripts)
        effects.append(.notify(.recovered))
    }

    let enteredUnreachable = oldPhase != .unreachable && newPhase == .unreachable
    let alreadyNotifiedAsDown = treatUnreachableAsDown && oldPhase == .running
    if enteredUnreachable && !alreadyNotifiedAsDown {
        effects.append(.notify(.unreachable))
    }

    return effects
}

/// The outcome of one check before it is confirmed.
struct CheckReading: Equatable, Sendable {
    /// What `skeen status` said, or nil when SSH failed.
    var ssh: SkeenState?
    var sshError: String?
    /// Whether the Clash API answered; nil when it is turned off.
    var apiAlive: Bool?
}

/// Combines the SSH reading with the Clash API. A live API proves sing-box
/// runs even when SSH is down or skeen's output is unreadable.
func resolveState(_ reading: CheckReading, previous: SkeenState) -> SkeenState {
    switch reading.ssh {
    case .some(.unknown), nil:
        if reading.apiAlive == true {
            return .running(previous.process ?? SkeenProcess())
        }
        return reading.ssh == nil ? .unreachable : .unknown
    case .some(let state):
        return state
    }
}

/// The state to show after a reading, and whether to check again soon.
struct Confirmation: Equatable, Sendable {
    var state: SkeenState
    var pending: StatePhase?
    var recheckSoon: Bool
}

/// A move into stopped or unreachable must show up twice in a row before it
/// counts. A restart from the menu or a Mac waking from sleep shows one bad
/// reading, and that should not run scripts or ring a banner. Good news and
/// the first reading after launch apply at once.
func confirm(current: SkeenState, candidate: SkeenState, pending: StatePhase?) -> Confirmation {
    let phase = candidate.phase
    if phase == current.phase || current.phase == .unknown || phase == .running || phase == .unknown {
        return Confirmation(state: candidate, pending: nil, recheckSoon: false)
    }
    if pending == phase {
        return Confirmation(state: candidate, pending: nil, recheckSoon: false)
    }
    return Confirmation(state: current, pending: phase, recheckSoon: true)
}
