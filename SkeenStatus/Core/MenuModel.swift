import Foundation

/// Abstract status color, mapped to concrete NSColor/SwiftUI Color at the edges.
nonisolated enum StatusColor: Equatable, Sendable {
    case green
    case red
    case yellow
    case gray
}

nonisolated func statusColor(for state: SkeenState) -> StatusColor {
    switch state.phase {
    case .running: return .green
    case .stopped: return .red
    case .unreachable: return .yellow
    case .unknown: return .gray
    }
}

/// View model for the status-bar dropdown, rendered by pure string logic.
nonisolated struct MenuModel: Equatable, Sendable {
    var title: String
    var statusDetail: String
    var memoryLine: String?
    var lastCheckLine: String
    var routerLine: String
}

nonisolated func menuModel(
    state: SkeenState,
    lastCheck: Date?,
    gateway: String,
    now: Date,
    calendar: Calendar = .current
) -> MenuModel {
    var detail = "Статус: \(state.keyword)"
    if let pid = state.pid {
        detail += " (PID \(pid))"
    }

    var memoryLine: String?
    if let mem = state.memoryMB {
        memoryLine = "Память: \(mem) MB"
    }

    let lastCheckText: String
    if let lastCheck {
        lastCheckText = "Последняя проверка: \(timeString(lastCheck, calendar: calendar))"
    } else {
        lastCheckText = "Последняя проверка: —"
    }

    return MenuModel(
        title: "Skeen: \(state.keyword)",
        statusDetail: detail,
        memoryLine: memoryLine,
        lastCheckLine: lastCheckText,
        routerLine: "Роутер: \(gateway)"
    )
}

/// One-line live status used in the settings footer.
nonisolated func statusFooter(
    state: SkeenState,
    lastCheck: Date?,
    gateway: String,
    calendar: Calendar = .current
) -> String {
    let time = lastCheck.map { timeString($0, calendar: calendar) } ?? "—"
    return "Статус: \(state.keyword) · последняя проверка \(time) · роутер \(gateway)"
}

nonisolated func timeString(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.hour, .minute, .second], from: date)
    return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
}
