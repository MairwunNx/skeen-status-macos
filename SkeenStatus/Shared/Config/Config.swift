import Foundation

/// How the "running" marker in the status output is matched.
enum MatchMode: String, Codable, Sendable, CaseIterable {
    case substring
    case regex
}

/// How the poller tells running from stopped in the status output.
enum StatusDetection: String, Codable, Sendable, CaseIterable {
    /// Reads skeen's own output: a `PID:` line or the word `running`.
    case automatic
    /// Matches the user's `RunningRule`.
    case rule
}

/// The rule that decides whether the status output means the service is running.
struct RunningRule: Codable, Equatable, Sendable {
    var pattern: String
    var mode: MatchMode
}

/// Every user setting. Secrets (the SSH password and the Clash API secret)
/// live only in the Keychain.
struct Config: Codable, Equatable, Sendable {
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
    /// The router's SSH host key in OpenSSH form, pinned on first connect.
    var hostKey: String
    var clashAPIEnabled: Bool
    /// Base URL of sing-box's Clash API; empty means `http://<gateway>:9090`.
    var clashAPIURL: String
    var notificationsEnabled: Bool
    var notifyUnreachable: Bool

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
        launchAtLogin: false,
        hostKey: "",
        clashAPIEnabled: true,
        clashAPIURL: "",
        notificationsEnabled: true,
        notifyUnreachable: true
    )

    /// Keychain account of the Clash API secret.
    static let clashSecretAccount = "clash-api"
}

extension Config {
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
        hostKey = try c.decodeIfPresent(String.self, forKey: .hostKey) ?? d.hostKey
        clashAPIEnabled = try c.decodeIfPresent(Bool.self, forKey: .clashAPIEnabled) ?? d.clashAPIEnabled
        clashAPIURL = try c.decodeIfPresent(String.self, forKey: .clashAPIURL) ?? d.clashAPIURL
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? d.notificationsEnabled
        notifyUnreachable = try c.decodeIfPresent(Bool.self, forKey: .notifyUnreachable) ?? d.notifyUnreachable
    }

    /// Poll interval, clamped to at least 3 seconds.
    var pollInterval: Duration {
        .seconds(max(3, intervalSeconds))
    }

    /// Command that fetches the tail of the sing-box log.
    var logCommand: String {
        "tail -n \(max(1, logLineCount)) \(logFilePath)"
    }

    /// Connection parameters for the SSH layer, kept apart so the session
    /// actor never depends on the full config.
    func sshConnection(password: String) -> SSHConnection {
        SSHConnection(
            host: gateway,
            port: port,
            username: login,
            password: password,
            postConnectCommands: postConnectCommands.filter { !$0.isBlank },
            trustedHostKey: hostKey.isBlank ? nil : hostKey
        )
    }

    /// The Clash API base URL, or nil when the API is off or the URL is broken.
    var clashAPIBaseURL: URL? {
        guard clashAPIEnabled else { return nil }
        let raw = clashAPIURL.isBlank ? "http://\(gateway):9090" : clashAPIURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }
}
