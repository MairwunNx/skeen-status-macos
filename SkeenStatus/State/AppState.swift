import Foundation
import Observation

/// Single in-memory source of truth for current configuration and live status.
/// UI, status-bar menu and the poller all read from this one object.
@MainActor
@Observable
final class AppState {
    var config: Config
    var status: SkeenState = .unknown
    var lastCheck: Date?
    var lastError: String?
    var logLines: [LogLine] = []
    var lastLogCheck: Date?
    var logError: String?
    var loginItemEnabled: Bool = false
    var notificationsAuthorized: Bool = false

    init(config: Config) {
        self.config = config
    }
}
