import Foundation

/// View model for the status-bar dropdown, rendered by pure string logic.
struct MenuModel: Equatable, Sendable {
    var title: String
    var color: StatusColor
    /// PID, memory, and uptime of sing-box.
    var processLine: String?
    /// sing-box version and traffic from the Clash API.
    var runtimeLine: String?
    var lastCheckLine: String
    var errorLine: String?
    var routerLine: String
    /// Where traffic goes: the selector's outbound and the routing mode.
    var routeLine: String?
    var canStart: Bool
}

func menuModel(
    snapshot: SkeenSnapshot,
    singBox: SingBoxSnapshot,
    gateway: String,
    calendar: Calendar = .current
) -> MenuModel {
    let state = snapshot.state

    var processLine: String?
    if let process = state.process {
        let parts = [
            process.pid.map { "PID \($0)" },
            process.memoryMB.map { "\($0) МБ" },
            process.uptime.map { "работает \($0)" },
        ].compactMap { $0 }
        processLine = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var runtimeLine: String?
    let runtime = state.phase == .running ? singBox.runtime : nil
    if let runtime {
        runtimeLine = "\(runtime.version) · ↓ \(byteString(runtime.downloadTotal)) ↑ \(byteString(runtime.uploadTotal))"
    }

    let lastCheck = snapshot.lastCheck.map { timeString($0, calendar: calendar) } ?? "—"

    return MenuModel(
        title: "Skeen: \(state.title)",
        color: statusColor(for: state),
        processLine: processLine,
        runtimeLine: runtimeLine,
        lastCheckLine: "Проверено в \(lastCheck)",
        errorLine: snapshot.lastError,
        routerLine: "Роутер: \(gateway)",
        routeLine: runtime.map(routeSummary),
        canStart: state.phase == .stopped
    )
}

/// `proxy → VLESS-NL · по правилам`: the first selector and the mode.
func routeSummary(_ runtime: SingBoxRuntime) -> String {
    let mode = modeTitle(runtime.mode).lowercased()
    guard let group = runtime.groups.first(where: \.isSelectable) ?? runtime.groups.first else { return "Режим: \(mode)" }
    return "\(group.name) → \(group.now) · \(mode)"
}
