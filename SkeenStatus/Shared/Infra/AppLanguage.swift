import AppKit
import ComposableArchitecture
import Foundation

/// The interface language: whatever macOS prefers, or one picked in the app.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// The language that a choice ends up showing on this Mac.
    func resolved(systemPreferred: String) -> String {
        self == .system ? systemPreferred : rawValue
    }
}

/// Reads and writes the app's own `AppleLanguages`, which macOS applies on
/// the next launch, the same switch as System Settings → Language & Region
/// → Applications.
@DependencyClient
struct LanguageClient: Sendable {
    var choice: @Sendable () -> AppLanguage = { .system }
    var setChoice: @Sendable (_ language: AppLanguage) -> Void
    /// The localization the running app shows: `en` or `ru`.
    var active: @Sendable () -> String = { "en" }
    /// What macOS alone would pick for this app.
    var systemPreferred: @Sendable () -> String = { "en" }
    var relaunch: @Sendable () -> Void
}

extension LanguageClient: DependencyKey {
    static let liveValue: LanguageClient = {
        let key = "AppleLanguages"
        let domain = Bundle.main.bundleIdentifier ?? "com.mairwunnx.SkeenStatus"
        let supported = Bundle.main.localizations.filter { $0 != "Base" }

        return LanguageClient(
            choice: {
                let own = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String]
                return own?.first.flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .system
            },
            setChoice: { language in
                if language == .system {
                    UserDefaults.standard.removeObject(forKey: key)
                } else {
                    UserDefaults.standard.set([language.rawValue], forKey: key)
                }
            },
            active: {
                Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en"
            },
            systemPreferred: {
                let global = UserDefaults(suiteName: UserDefaults.globalDomain)?.stringArray(forKey: key) ?? Locale.preferredLanguages
                let match = Bundle.preferredLocalizations(from: supported, forPreferences: global).first ?? "en"
                return String(match.prefix(2))
            },
            relaunch: {
                let path = Bundle.main.bundlePath
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
                try? process.run()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        )
    }()

    /// English everywhere and nothing stored, so tests see one language.
    static let testValue = LanguageClient(
        choice: { .system },
        setChoice: { _ in },
        active: { "en" },
        systemPreferred: { "en" },
        relaunch: {}
    )
}

extension DependencyValues {
    var language: LanguageClient {
        get { self[LanguageClient.self] }
        set { self[LanguageClient.self] = newValue }
    }
}
