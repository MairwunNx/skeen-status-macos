import Foundation
import UserNotifications

/// Native notifications sent only on real state transitions.
nonisolated enum Notifications {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func send(_ kind: NotificationKind) {
        let content = UNMutableNotificationContent()
        switch kind {
        case .down:
            content.title = "skeen упал"
            content.body = "Сервис skeen остановлен на роутере."
        case .recovered:
            content.title = "skeen восстановлен"
            content.body = "Сервис skeen снова работает."
        case .unreachable:
            content.title = "Роутер недоступен"
            content.body = "Не удалось подключиться к роутеру по SSH."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
