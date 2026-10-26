import ComposableArchitecture
import Foundation

/// The router's shell over the one long-lived SSH session.
@DependencyClient
struct RouterShell: Sendable {
    /// Points the session at a router; reconnects only when something changed.
    var configure: @Sendable (_ connection: SSHConnection) async -> Void
    /// Runs one command in the shell and returns its cleaned output.
    var run: @Sendable (_ command: String, _ timeout: Duration) async throws -> String
    /// Dials again right away, e.g. after the Mac wakes up.
    var reconnect: @Sendable () async -> Void
    /// The host key the router showed on the current connection.
    var hostKey: @Sendable () async -> String?
    /// Connects once without touching the session and returns the host key.
    var test: @Sendable (_ connection: SSHConnection) async throws -> String
}

extension RouterShell: DependencyKey {
    static var liveValue: RouterShell {
        @Dependency(\.appLog) var appLog
        let session = SSHSession(log: { appLog.write($0) })
        return RouterShell(
            configure: { await session.configure($0) },
            run: { command, timeout in
                try await session.runWhenReady(command, readyTimeout: .seconds(12), commandTimeout: timeout)
            },
            reconnect: { await session.reconnect() },
            hostKey: { await session.hostKey() },
            test: { try await SSHSession.test(connection: $0) }
        )
    }

    static let testValue = RouterShell()
}

extension DependencyValues {
    var routerShell: RouterShell {
        get { self[RouterShell.self] }
        set { self[RouterShell.self] = newValue }
    }
}
