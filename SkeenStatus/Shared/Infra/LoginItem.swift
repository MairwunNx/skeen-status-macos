import ComposableArchitecture
import Foundation
import ServiceManagement

/// Login-item registration via `SMAppService.mainApp`.
@DependencyClient
struct LoginItem: Sendable {
    var isEnabled: @Sendable () -> Bool = { false }
    var setEnabled: @Sendable (_ enabled: Bool) throws -> Void
}

extension LoginItem: DependencyKey {
    static let liveValue = LoginItem(
        isEnabled: { SMAppService.mainApp.status == .enabled },
        setEnabled: { enabled in
            let service = SMAppService.mainApp
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        }
    )

    static let testValue = LoginItem()
}

extension DependencyValues {
    var loginItem: LoginItem {
        get { self[LoginItem.self] }
        set { self[LoginItem.self] = newValue }
    }
}
