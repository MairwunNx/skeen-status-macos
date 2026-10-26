import Foundation

/// Button ids on the monitor's banners.
enum MonitorNotificationAction {
    static let start = "skeen.start"
    static let open = "skeen.open"
}

private let downCategory = NotificationCategory(
    id: "skeen.down",
    actions: [
        NotificationButton(id: MonitorNotificationAction.start, title: String(localized: "Start")),
        NotificationButton(id: MonitorNotificationAction.open, title: String(localized: "Open")),
    ]
)

/// The banner for a transition. Every banner shares one id, so a newer one
/// replaces the older one instead of piling up.
func notificationContent(
    _ kind: NotificationKind,
    state: SkeenState,
    previousPhaseSince: Date?,
    now: Date,
    gateway: String,
    reason: String?
) -> LocalNotification {
    let lasted = previousPhaseSince.map { durationString(now.timeIntervalSince($0)) }
    switch kind {
    case .down:
        var body = String(localized: "sing-box on \(gateway) is down, and traffic bypasses the proxy.")
        if let lasted { body += " " + String(localized: "It ran for \(lasted) before that.") }
        return LocalNotification(id: "skeen.state", title: String(localized: "skeen stopped"), body: body, category: downCategory)
    case .stoppedAtLaunch:
        return LocalNotification(
            id: "skeen.state",
            title: String(localized: "skeen isn’t running"),
            body: String(localized: "sing-box on \(gateway) is down, and traffic bypasses the proxy."),
            category: downCategory
        )
    case .recovered:
        var body = state.process?.pid.map { String(localized: "sing-box runs again (PID \($0)).") } ?? String(localized: "sing-box runs again.")
        if let lasted { body += " " + String(localized: "Downtime: \(lasted).") }
        return LocalNotification(id: "skeen.state", title: String(localized: "skeen runs again"), body: body, category: nil)
    case .unreachable:
        var body = String(localized: "Can’t reach \(gateway) over SSH.")
        if let reason { body += " \(reason)." }
        return LocalNotification(id: "skeen.state", title: String(localized: "Router unreachable"), body: body, category: nil)
    }
}
