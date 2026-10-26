import ComposableArchitecture
import Foundation
import Security

/// Secrets in the login Keychain under service `skeen-status-macos`. Nothing
/// stored here ever reaches `config.json`.
@DependencyClient
struct Keychain: Sendable {
    var read: @Sendable (_ account: String) -> String? = { _ in nil }
    var save: @Sendable (_ secret: String, _ account: String) -> Void
    var delete: @Sendable (_ account: String) -> Void
}

extension Keychain: DependencyKey {
    static let service = "skeen-status-macos"

    static let liveValue = Keychain(
        read: { account in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        },
        save: { secret, account in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
            guard !secret.isEmpty else { return }

            var attributes = query
            attributes[kSecValueData as String] = Data(secret.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        },
        delete: { account in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    )

    static let testValue = Keychain()

    /// An in-memory Keychain for previews, tests, and the demo mode.
    static func inMemory(_ initial: [String: String] = [:]) -> Keychain {
        let storage = LockIsolated(initial)
        return Keychain(
            read: { account in storage.value[account] },
            save: { secret, account in storage.withValue { $0[account] = secret.isEmpty ? nil : secret } },
            delete: { account in storage.withValue { $0[account] = nil } }
        )
    }
}

extension DependencyValues {
    var keychain: Keychain {
        get { self[Keychain.self] }
        set { self[Keychain.self] = newValue }
    }
}
