import Foundation

/// How the "running" marker in the status output is matched.
nonisolated enum MatchMode: String, Codable, Sendable, CaseIterable {
    case substring
    case regex
}

/// How the poller tells running from stopped in the status output.
nonisolated enum StatusDetection: String, Codable, Sendable, CaseIterable {
    /// Reads skeen's own output: a `PID:` line or the word `running`.
    case automatic
    /// Matches the user's `RunningRule`.
    case rule
}

/// The rule that decides whether the status output means the service is running.
nonisolated struct RunningRule: Codable, Equatable, Sendable {
    var pattern: String
    var mode: MatchMode
}

/// The single source of truth for all user settings (without the password,
/// which lives only in the Keychain).
nonisolated struct Config: Codable, Equatable, Sendable {
    var gateway: String
    var port: Int
    var login: String
    var postConnectCommands: [String]
    var skeenCommand: String
    var statusCommand: String
    var statusDetection: StatusDetection
    var runningRule: RunningRule
    var intervalSeconds: Int
    var logFilePath: String
    var logLineCount: Int
    var onDownScripts: [String]
    var onRecoverScripts: [String]
    var treatUnreachableAsDown: Bool
    var launchAtLogin: Bool

    static let `default` = Config(
        gateway: "192.168.1.1",
        port: 2022,
        login: "admin",
        postConnectCommands: ["exec sh"],
        skeenCommand: "skeen",
        statusCommand: "skeen status",
        statusDetection: .automatic,
        runningRule: RunningRule(pattern: "Status: running", mode: .substring),
        intervalSeconds: 15,
        logFilePath: "/opt/var/log/sing-box.log",
        logLineCount: 50,
        onDownScripts: [],
        onRecoverScripts: [],
        treatUnreachableAsDown: false,
        launchAtLogin: false
    )
}

nonisolated extension Config {
    /// Command used to fetch the tail of the sing-box log; the line count slider
    /// drives `tail -n`.
    var logCommand: String {
        "tail -n \(max(1, logLineCount)) \(logFilePath)"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        gateway = try c.decodeIfPresent(String.self, forKey: .gateway) ?? d.gateway
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? d.port
        login = try c.decodeIfPresent(String.self, forKey: .login) ?? d.login
        postConnectCommands = try c.decodeIfPresent([String].self, forKey: .postConnectCommands) ?? d.postConnectCommands
        skeenCommand = try c.decodeIfPresent(String.self, forKey: .skeenCommand) ?? d.skeenCommand
        statusCommand = try c.decodeIfPresent(String.self, forKey: .statusCommand) ?? d.statusCommand
        statusDetection = try c.decodeIfPresent(StatusDetection.self, forKey: .statusDetection) ?? d.statusDetection
        runningRule = try c.decodeIfPresent(RunningRule.self, forKey: .runningRule) ?? d.runningRule
        intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? d.intervalSeconds
        logFilePath = try c.decodeIfPresent(String.self, forKey: .logFilePath) ?? d.logFilePath
        logLineCount = try c.decodeIfPresent(Int.self, forKey: .logLineCount) ?? d.logLineCount
        onDownScripts = try c.decodeIfPresent([String].self, forKey: .onDownScripts) ?? d.onDownScripts
        onRecoverScripts = try c.decodeIfPresent([String].self, forKey: .onRecoverScripts) ?? d.onRecoverScripts
        treatUnreachableAsDown = try c.decodeIfPresent(Bool.self, forKey: .treatUnreachableAsDown) ?? d.treatUnreachableAsDown
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }

    /// Connection parameters needed by the SSH layer, kept separate so the
    /// session actor never depends on the full UI config.
    func sshConnection(password: String) -> SSHConnection {
        SSHConnection(
            host: gateway,
            port: port,
            username: login,
            password: password,
            postConnectCommands: postConnectCommands.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            statusCommand: statusCommand
        )
    }
}

/// Immutable connection description handed to the SSH session actor.
nonisolated struct SSHConnection: Sendable, Equatable {
    var host: String
    var port: Int
    var username: String
    var password: String
    var postConnectCommands: [String]
    var statusCommand: String
}
