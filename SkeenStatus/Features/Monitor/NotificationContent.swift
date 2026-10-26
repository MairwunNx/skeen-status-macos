import Foundation

/// Button ids on the monitor's banners.
enum MonitorNotificationAction {
    static let start = "skeen.start"
    static let open = "skeen.open"
}

private let downCategory = NotificationCategory(
    id: "skeen.down",
    actions: [
        NotificationButton(id: MonitorNotificationAction.start, title: "Запустить"),
        NotificationButton(id: MonitorNotificationAction.open, title: "Открыть"),
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
        var body = "sing-box на \(gateway) не работает, трафик идёт мимо прокси."
        if let lasted { body += " До этого проработал \(lasted)." }
        return LocalNotification(id: "skeen.state", title: "skeen остановлен", body: body, category: downCategory)
    case .stoppedAtLaunch:
        return LocalNotification(
            id: "skeen.state",
            title: "skeen не запущен",
            body: "sing-box на \(gateway) не работает, трафик идёт мимо прокси.",
            category: downCategory
        )
    case .recovered:
        var body = "sing-box снова работает"
        if let pid = state.process?.pid { body += " (PID \(pid))" }
        body += "."
        if let lasted { body += " Простой: \(lasted)." }
        return LocalNotification(id: "skeen.state", title: "skeen снова работает", body: body, category: nil)
    case .unreachable:
        var body = "Не удаётся связаться с \(gateway) по SSH."
        if let reason { body += " \(reason)." }
        return LocalNotification(id: "skeen.state", title: "Роутер недоступен", body: body, category: nil)
    }
}
