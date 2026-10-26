import ComposableArchitecture
import Foundation

/// Watches skeen: polls over SSH and the Clash API, confirms each change,
/// and on a real edge runs the user's scripts and shows a banner.
@Reducer
struct MonitorFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.config) var config
        @Shared(.skeenSnapshot) var snapshot
        @Shared(.singBoxSnapshot) var singBox
        /// A bad phase seen once and waiting for a second reading.
        var pendingPhase: StatePhase?
        var isChecking = false
        var history: [MetricSample] = []
        var totals: TrafficTotals?
        var lastHistorySave: Date?
        var chartRange: ChartRange = .fifteenMinutes
    }

    enum Action {
        case start
        case checkNow
        case configChanged
        case systemDidWake
        case checked(CheckResult)
        case versionLoaded(SkeenVersion)
        /// The overview is on screen: read the Clash API every 2 seconds.
        case dashboardTask
        case liveLoaded(Result<SingBoxRuntime, Error>)
        case setChartRange(ChartRange)
        case saveHistory
        case notificationResponse(String)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case openSettings
            case startService
        }
    }

    /// Everything one check learned.
    struct CheckResult: Equatable, Sendable {
        var reading: CheckReading
        var runtime: SingBoxRuntime?
        var apiError: String?
        var hostKey: String?
    }

    enum CancelID {
        case timer
        case recheck
        case live
    }

    @Dependency(\.appLog) var appLog
    @Dependency(\.clashAPI) var clashAPI
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.keychain) var keychain
    @Dependency(\.localShell) var localShell
    @Dependency(\.metricsStore) var metricsStore
    @Dependency(\.notifier) var notifier
    @Dependency(\.routerShell) var routerShell
    @Dependency(\.skeen) var skeen

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                appLog.write("monitor started")
                if state.history.isEmpty {
                    state.history = compact(metricsStore.load(), now: now)
                }
                return .merge(
                    .run { _ in _ = await notifier.authorize() },
                    .run { send in
                        for await response in notifier.responses() {
                            await send(.notificationResponse(response))
                        }
                    },
                    startTimer(state)
                )

            case .configChanged:
                state.pendingPhase = nil
                state.$snapshot.withLock { $0.version = nil }
                return startTimer(state)

            case .checkNow:
                return check(&state)

            case .systemDidWake:
                appLog.write("system woke up, reconnecting")
                return .run { send in
                    await routerShell.reconnect()
                    try await clock.sleep(for: .seconds(3))
                    await send(.checkNow)
                }
                .cancellable(id: CancelID.recheck, cancelInFlight: true)

            case .checked(let result):
                state.isChecking = false
                return apply(result, to: &state)

            case .versionLoaded(let version):
                state.$snapshot.withLock { $0.version = version }
                return .none

            case .dashboardTask:
                return .run { [state] send in
                    for await _ in clock.timer(interval: .seconds(2)) {
                        let config = state.config
                        guard let endpoint = ClashEndpoint(config: config, secret: keychain.read(Config.clashSecretAccount)) else { return }
                        await send(.liveLoaded(attempt { try await clashAPI.runtime(endpoint) }))
                    }
                }
                .cancellable(id: CancelID.live, cancelInFlight: true)

            case .liveLoaded(.success(let runtime)):
                guard state.snapshot.state.phase == .running else { return .none }
                let now = now
                state.$singBox.withLock {
                    $0.runtime = runtime
                    $0.lastError = nil
                    $0.lastUpdate = now
                }
                return record(runtime, in: &state)

            case .liveLoaded(.failure):
                return .none

            case .setChartRange(let range):
                state.chartRange = range
                return .none

            case .saveHistory:
                state.lastHistorySave = now
                let history = state.history
                return .run { _ in metricsStore.save(history) }

            case .notificationResponse(let id):
                switch id {
                case MonitorNotificationAction.start:
                    return .send(.delegate(.startService))
                default:
                    return .send(.delegate(.openSettings))
                }

            case .delegate:
                return .none
            }
        }
    }

    /// Checks now, then on every interval. Restarting it picks up a new interval.
    private func startTimer(_ state: State) -> Effect<Action> {
        let interval = state.config.pollInterval
        return .run { send in
            await send(.checkNow)
            for await _ in clock.timer(interval: interval) {
                await send(.checkNow)
            }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    private func check(_ state: inout State) -> Effect<Action> {
        guard !state.isChecking else { return .none }
        state.isChecking = true
        let config = state.config
        let password = keychain.read(config.login) ?? ""
        let endpoint = ClashEndpoint(config: config, secret: keychain.read(Config.clashSecretAccount))

        return .run { send in
            await routerShell.configure(config.sshConnection(password: password))

            @Sendable func readStatus() async -> Result<SkeenState, Error> {
                await attempt { try await skeen.status(config.statusCommand, config.statusDetection, config.runningRule) }
            }
            @Sendable func readRuntime() async -> Result<SingBoxRuntime, Error>? {
                guard let endpoint else { return nil }
                return await attempt { try await clashAPI.runtime(endpoint) }
            }
            async let ssh = readStatus()
            async let api = readRuntime()

            let (sshResult, apiResult) = await (ssh, api)
            var reading = CheckReading()
            switch sshResult {
            case .success(let state): reading.ssh = state
            case .failure(let error): reading.sshError = error.localizedDescription
            }
            var result = CheckResult(reading: reading)
            switch apiResult {
            case .success(let runtime):
                result.reading.apiAlive = true
                result.runtime = runtime
            case .failure(let error):
                result.reading.apiAlive = false
                result.apiError = error.localizedDescription
            case nil:
                break
            }
            if reading.ssh != nil, config.hostKey.isBlank {
                result.hostKey = await routerShell.hostKey()
            }
            await send(.checked(result))
        }
    }

    private func apply(_ result: CheckResult, to state: inout State) -> Effect<Action> {
        let now = now
        let old = state.snapshot.state
        let candidate = resolveState(result.reading, previous: old)
        let confirmation = confirm(current: old, candidate: candidate, pending: state.pendingPhase)
        state.pendingPhase = confirmation.pending

        let new = confirmation.state
        let previousSince = state.snapshot.phaseSince
        let error = result.reading.sshError ?? (new.phase == .unknown ? String(localized: "Can’t read the output of “\(state.config.statusCommand)”") : nil)

        state.$snapshot.withLock { snapshot in
            snapshot.lastCheck = now
            snapshot.lastError = error
            if old.phase != new.phase || snapshot.phaseSince == nil {
                snapshot.phaseSince = now
            }
            snapshot.state = new
        }
        state.$singBox.withLock { singBox in
            singBox.lastUpdate = now
            singBox.lastError = result.apiError
            singBox.runtime = result.runtime
        }
        var effects: [Effect<Action>] = [record(result.runtime, in: &state)]
        if let key = result.hostKey, !key.isBlank, state.config.hostKey.isBlank {
            appLog.write("pinned router host key \(key.prefix(40))…")
            state.$config.withLock { $0.hostKey = key }
        }

        if old.phase != new.phase {
            appLog.write("state \(old.phase.rawValue) -> \(new.phase.rawValue)\(error.map { " (\($0))" } ?? "")")
        }
        if confirmation.recheckSoon {
            appLog.write("saw \(candidate.phase.rawValue) once, checking again")
            effects.append(
                .run { send in
                    try await clock.sleep(for: .seconds(3))
                    await send(.checkNow)
                }
                .cancellable(id: CancelID.recheck, cancelInFlight: true)
            )
        }
        if new.phase == .running, state.snapshot.version == nil {
            let command = state.config.skeenCommand
            effects.append(.run { send in
                if let version = try? await skeen.version(command), !version.isEmpty {
                    await send(.versionLoaded(version))
                }
            })
        }

        let config = state.config
        for effect in transition(from: old, to: new, treatUnreachableAsDown: config.treatUnreachableAsDown) {
            switch effect {
            case .notify(let kind):
                guard config.notificationsEnabled, kind != .unreachable || config.notifyUnreachable else { continue }
                let banner = notificationContent(
                    kind,
                    state: new,
                    previousPhaseSince: previousSince,
                    now: now,
                    gateway: config.gateway,
                    reason: error
                )
                effects.append(.run { _ in await notifier.send(banner) })
            case .runDownScripts:
                effects.append(runScripts(config.onDownScripts, label: "down"))
            case .runRecoverScripts:
                effects.append(runScripts(config.onRecoverScripts, label: "recover"))
            }
        }
        return .merge(effects)
    }

    /// Adds a chart point and writes the history to disk at most once a minute.
    private func record(_ runtime: SingBoxRuntime?, in state: inout State) -> Effect<Action> {
        let now = now
        let (sample, totals) = makeSample(at: now, state: state.snapshot.state, runtime: runtime, previous: state.totals)
        state.totals = totals
        state.history = appending(sample, to: state.history)
        guard let lastSave = state.lastHistorySave, now.timeIntervalSince(lastSave) < 60 else {
            return .send(.saveHistory)
        }
        return .none
    }

    private func runScripts(_ scripts: [String], label: String) -> Effect<Action> {
        let commands = scripts.filter { !$0.isBlank }
        guard !commands.isEmpty else { return .none }
        return .run { _ in
            appLog.write("running \(label) scripts (\(commands.count))")
            for command in commands {
                let result = await localShell.run(command)
                appLog.write("[\(label)] $ \(command) -> exit \(result.exitCode): \(cleanOutput(result.output).prefix(200))")
            }
        }
    }
}
