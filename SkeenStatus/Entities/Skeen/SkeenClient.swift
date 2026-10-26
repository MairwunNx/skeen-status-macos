import ComposableArchitecture
import Foundation

/// skeen's commands over the router shell, returned as domain values.
@DependencyClient
struct SkeenClient: Sendable {
    /// Runs the status command and reads the state from its output.
    var status: @Sendable (_ command: String, _ detection: StatusDetection, _ rule: RunningRule) async throws -> SkeenState
    var version: @Sendable (_ skeen: String) async throws -> SkeenVersion
    /// Runs `skeen <control>` and returns what it printed.
    var control: @Sendable (_ skeen: String, _ control: SkeenControl) async throws -> String
    /// Runs the log tail command and parses the lines.
    var logs: @Sendable (_ command: String) async throws -> [LogLine]
}

extension SkeenClient: DependencyKey {
    static var liveValue: SkeenClient {
        @Dependency(\.routerShell) var shell
        return SkeenClient(
            status: { command, detection, rule in
                parseStatus(try await shell.run(command, .seconds(15)), detection: detection, rule: rule)
            },
            version: { skeen in
                parseSkeenVersion(try await shell.run("\(skeen) version", .seconds(20)))
            },
            control: { skeen, control in
                try await shell.run("\(skeen) \(control.rawValue)", .seconds(60))
            },
            logs: { command in
                parseLogLines(try await shell.run(command, .seconds(20)))
            }
        )
    }

    static let testValue = SkeenClient()
}

extension DependencyValues {
    var skeen: SkeenClient {
        get { self[SkeenClient.self] }
        set { self[SkeenClient.self] = newValue }
    }
}
