import Foundation

/// Thin runner that drives polling, maps results to state via pure functions,
/// and executes the side effects of each transition. Holds no duplicate state:
/// everything observable lives in `AppState`.
@MainActor
final class Engine {
    let appState: AppState
    private let session: SSHSession
    private var pollTask: Task<Void, Never>?

    var onStateChange: ((SkeenState) -> Void)?

    init(appState: AppState) {
        self.appState = appState
        self.session = SSHSession(log: { AppLog.shared.log($0) })
    }

    func start() {
        appState.loginItemEnabled = LoginItem.isEnabled
        Task { appState.notificationsAuthorized = await Notifications.requestAuthorization() }

        let connection = currentConnection()
        Task { await session.start(connection: connection) }
        restartPolling()
    }

    func shutdown() async {
        pollTask?.cancel()
        await session.stop()
    }

    // MARK: Configuration

    func applyConfig(_ config: Config, password: String) {
        appState.config = config
        ConfigStore.save(config)
        if !password.isEmpty {
            Keychain.savePassword(password, account: config.login)
        }
        do {
            try LoginItem.setEnabled(config.launchAtLogin)
        } catch {
            AppLog.shared.log("login item error: \(error)")
        }
        appState.loginItemEnabled = LoginItem.isEnabled

        let connection = currentConnection()
        Task { await session.update(connection: connection) }
        restartPolling()
    }

    func testConnection(_ config: Config, password: String) async -> Result<String, Error> {
        let effectivePassword = password.isEmpty
            ? (Keychain.readPassword(account: config.login) ?? "")
            : password
        return await SSHSession.test(connection: config.sshConnection(password: effectivePassword))
    }

    func checkNow() {
        Task { await poll() }
    }

    // MARK: Service control

    /// Runs a `skeen` service-control subcommand (start/stop/restart/reload) and
    /// refreshes the status afterwards on success.
    func runSkeenControl(_ control: SkeenControl) async -> Result<String, Error> {
        let command = "\(appState.config.skeenCommand) \(control.rawValue)"
        let result = await runCommand(command, commandTimeout: .seconds(45))
        if case .success = result {
            await poll()
        }
        return result
    }

    /// Fetches the tail of the sing-box log, parses it and publishes the lines
    /// to `AppState`. Driven by the logs section in Settings while it is visible.
    func refreshLogs() async {
        let config = appState.config
        guard !config.logFilePath.trimmingCharacters(in: .whitespaces).isEmpty else {
            appState.logError = "Не указан путь к файлу лога"
            return
        }
        await session.update(connection: currentConnection())
        do {
            let raw = try await session.runWhenReady(
                config.logCommand,
                readyTimeout: .seconds(12),
                commandTimeout: .seconds(20)
            )
            appState.logLines = parseLogLines(raw)
            appState.lastLogCheck = Date()
            appState.logError = nil
        } catch {
            AppLog.shared.log("log fetch failed: \(error)")
            appState.logError = "\(error)"
        }
    }

    /// Fetches and parses `skeen version`.
    func fetchSkeenVersion() async -> Result<SkeenVersion, Error> {
        let command = "\(appState.config.skeenCommand) version"
        return await runCommand(command, commandTimeout: .seconds(20)).map(parseSkeenVersion)
    }

    private func runCommand(_ command: String, commandTimeout: Duration) async -> Result<String, Error> {
        await session.update(connection: currentConnection())
        do {
            let raw = try await session.runWhenReady(
                command,
                readyTimeout: .seconds(12),
                commandTimeout: commandTimeout
            )
            AppLog.shared.log("command '\(command)' -> \(cleanOutput(raw).prefix(200))")
            return .success(raw)
        } catch {
            AppLog.shared.log("command '\(command)' failed: \(error)")
            return .failure(error)
        }
    }

    // MARK: Polling

    private func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await poll()
            let interval = max(3, appState.config.intervalSeconds)
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func poll() async {
        let config = appState.config
        await session.update(connection: currentConnection())

        let newState: SkeenState
        do {
            let raw = try await session.runWhenReady(
                config.statusCommand,
                readyTimeout: .seconds(12),
                commandTimeout: .seconds(15)
            )
            let preview = raw.replacingOccurrences(of: "\n", with: " | ").prefix(200)
            AppLog.shared.log("status output: \(preview)")
            newState = parseStatus(raw, rule: config.runningRule)
            appState.lastError = nil
        } catch {
            newState = .unreachable
            appState.lastError = "\(error)"
        }
        apply(newState)
    }

    private func apply(_ newState: SkeenState) {
        let old = appState.status
        let effects = transition(
            from: old,
            to: newState,
            treatUnreachableAsDown: appState.config.treatUnreachableAsDown
        )

        appState.status = newState
        appState.lastCheck = Date()

        if old.phase != newState.phase {
            AppLog.shared.log("state \(old.keyword) -> \(newState.keyword)")
        }

        for effect in effects {
            switch effect {
            case .notify(let kind):
                Notifications.send(kind)
            case .runDownScripts:
                runScripts(appState.config.onDownScripts, label: "down")
            case .runRecoverScripts:
                runScripts(appState.config.onRecoverScripts, label: "recover")
            }
        }

        onStateChange?(newState)
    }

    private func runScripts(_ scripts: [String], label: String) {
        let commands = scripts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !commands.isEmpty else { return }
        Task {
            AppLog.shared.log("running \(label) scripts (\(commands.count))")
            for command in commands {
                let result = await LocalShell.run(command)
                let summary = cleanOutput(result.output).prefix(200)
                AppLog.shared.log("[\(label)] $ \(command) -> exit \(result.exitCode): \(summary)")
            }
        }
    }

    private func currentConnection() -> SSHConnection {
        let password = Keychain.readPassword(account: appState.config.login) ?? ""
        return appState.config.sshConnection(password: password)
    }
}
