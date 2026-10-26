import Foundation

/// Native notification variants, chosen purely from a state transition.
nonisolated enum NotificationKind: Equatable, Sendable {
    case down
    case recovered
    case unreachable
}

/// Side effects produced by a state transition; executed by a thin runner.
nonisolated enum SideEffect: Equatable, Sendable {
    case runDownScripts
    case runRecoverScripts
    case notify(NotificationKind)
}

/// Computes the side effects for a state change. Scripts fire only on the
/// real running<->stopped edges; unreachable triggers scripts only when
/// `treatUnreachableAsDown` is enabled (mapping unreachable onto stopped).
nonisolated func transition(
    from old: SkeenState,
    to new: SkeenState,
    treatUnreachableAsDown: Bool
) -> [SideEffect] {
    let oldPhase = old.phase
    let newPhase = new.phase
    guard oldPhase != newPhase else { return [] }

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
