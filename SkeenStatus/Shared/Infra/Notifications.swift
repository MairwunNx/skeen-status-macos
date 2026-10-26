import ComposableArchitecture
import Foundation
import UserNotifications

/// One banner. A notification with the same `id` replaces the previous one,
/// so Notification Center keeps only the latest word on a subject.
struct LocalNotification: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var category: NotificationCategory?
}

/// A set of buttons shown under a banner.
struct NotificationCategory: Equatable, Sendable {
    var id: String
    var actions: [NotificationButton]
}

struct NotificationButton: Equatable, Sendable {
    var id: String
    var title: String
}

/// Native notifications: authorization, delivery, and the buttons the user
/// presses on a banner.
@DependencyClient
struct Notifier: Sendable {
    var authorize: @Sendable () async -> Bool = { false }
    var send: @Sendable (_ notification: LocalNotification) async -> Void
    /// The `id` of each button the user presses, or `default` for a click on
    /// the banner itself.
    var responses: @Sendable () -> AsyncStream<String> = { .finished }
}

extension Notifier: DependencyKey {
    static let liveValue: Notifier = {
        let delegate = NotificationDelegate()
        UNUserNotificationCenter.current().delegate = delegate
        return Notifier(
            authorize: {
                (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            },
            send: { notification in
                let center = UNUserNotificationCenter.current()
                if let category = notification.category {
                    delegate.register(category)
                }
                let content = UNMutableNotificationContent()
                content.title = notification.title
                content.body = notification.body
                content.sound = .default
                content.threadIdentifier = "skeen-status"
                content.categoryIdentifier = notification.category?.id ?? ""
                center.removeDeliveredNotifications(withIdentifiers: [notification.id])
                try? await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: nil))
            },
            responses: { delegate.stream }
        )
    }()

    static let testValue = Notifier()
}

extension DependencyValues {
    var notifier: Notifier {
        get { self[Notifier.self] }
        set { self[Notifier.self] = newValue }
    }
}

/// Shows banners even while the app is frontmost and turns button presses
/// into a stream.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var categories: [String: UNNotificationCategory] = [:]

    override init() {
        (stream, continuation) = AsyncStream.makeStream(of: String.self)
        super.init()
    }

    func register(_ category: NotificationCategory) {
        let all: Set<UNNotificationCategory> = lock.withLock {
            guard categories[category.id] == nil else { return [] }
            categories[category.id] = UNNotificationCategory(
                identifier: category.id,
                actions: category.actions.map { UNNotificationAction(identifier: $0.id, title: $0.title, options: [.foreground]) },
                intentIdentifiers: []
            )
            return Set(categories.values)
        }
        if !all.isEmpty {
            UNUserNotificationCenter.current().setNotificationCategories(all)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? "default" : response.actionIdentifier
        continuation.yield(id)
    }
}
