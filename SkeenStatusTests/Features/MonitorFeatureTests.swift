import ComposableArchitecture
import Foundation
import Testing
@testable import SkeenStatus

@MainActor
@Suite("Monitor")
struct MonitorFeatureTests {

    private let running = SkeenState.running(SkeenProcess(pid: 7, memoryMB: 50, uptime: "1d 0h 0m"))
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(
        config: Config,
        readings: [Result<SkeenState, Error>],
        sent: LockIsolated<[LocalNotification]>,
        ran: LockIsolated<[String]>
    ) -> TestStoreOf<MonitorFeature> {
        var state = MonitorFeature.State()
        state.$config = Shared(value: config)
        state.$snapshot = Shared(value: SkeenSnapshot())
        state.$singBox = Shared(value: SingBoxSnapshot())

        let queue = LockIsolated(readings)
        let store = TestStore(initialState: state) {
            MonitorFeature()
        } withDependencies: {
            $0.keychain = .inMemory(["admin": "pw"])
            $0.routerShell = RouterShell(configure: { _ in }, run: { _, _ in "" }, reconnect: {}, hostKey: { nil }, test: { _ in "" })
            $0.skeen.status = { _, _, _ in try queue.withValue { $0.removeFirst() }.get() }
            $0.skeen.version = { _ in SkeenVersion(skeen: "v5.7.0") }
            $0.notifier.send = { banner in sent.withValue { $0.append(banner) } }
            $0.localShell.run = { command in
                ran.withValue { $0.append(command) }
                return LocalCommandResult(exitCode: 0, output: "")
            }
            $0.continuousClock = ImmediateClock()
            $0.date.now = now
        }
        store.exhaustivity = .off
        return store
    }

    private var config: Config {
        var config = Config.default
        config.hostKey = "ssh-ed25519 AAAA"
        config.clashAPIEnabled = false
        config.onDownScripts = ["echo down", "  "]
        config.onRecoverScripts = ["echo up"]
        return config
    }

    @Test func oneStoppedReadingIsRecheckedBeforeAnythingFires() async {
        let sent = LockIsolated<[LocalNotification]>([])
        let ran = LockIsolated<[String]>([])
        let store = makeStore(config: config, readings: [.success(running), .success(.stopped), .success(running)], sent: sent, ran: ran)

        await store.send(.checkNow)
        await store.receive(\.checked)
        #expect(store.state.snapshot.state == running)

        await store.send(.checkNow)
        await store.receive(\.checked)
        #expect(store.state.snapshot.state == running)
        #expect(store.state.pendingPhase == .stopped)

        await store.receive(\.checkNow)
        await store.receive(\.checked)
        #expect(store.state.snapshot.state == running)
        #expect(store.state.pendingPhase == nil)
        await store.finish()

        #expect(sent.value.isEmpty)
        #expect(ran.value.isEmpty)
    }

    @Test func confirmedStopRunsScriptsAndShowsOneBanner() async {
        let sent = LockIsolated<[LocalNotification]>([])
        let ran = LockIsolated<[String]>([])
        let store = makeStore(config: config, readings: [.success(running), .success(.stopped), .success(.stopped)], sent: sent, ran: ran)

        await store.send(.checkNow)
        await store.receive(\.checked)
        await store.send(.checkNow)
        await store.receive(\.checked)
        await store.receive(\.checkNow)
        await store.receive(\.checked)
        await store.finish()

        #expect(store.state.snapshot.state == .stopped)
        #expect(ran.value == ["echo down"])
        #expect(sent.value.map(\.title) == ["skeen остановлен"])
    }

    @Test func sshFailureMakesTheRouterUnreachableAndSaysWhy() async {
        let sent = LockIsolated<[LocalNotification]>([])
        let ran = LockIsolated<[String]>([])
        let failure = SSHSessionError.connectFailed("Роутер не отвечает")
        let store = makeStore(config: config, readings: [.success(running), .failure(failure), .failure(failure)], sent: sent, ran: ran)

        await store.send(.checkNow)
        await store.receive(\.checked)
        await store.send(.checkNow)
        await store.receive(\.checked)
        await store.receive(\.checkNow)
        await store.receive(\.checked)
        await store.finish()

        #expect(store.state.snapshot.state == .unreachable)
        #expect(store.state.snapshot.lastError == "Роутер не отвечает")
        #expect(ran.value.isEmpty)
        #expect(sent.value.map(\.body) == ["Не удаётся связаться с 192.168.1.1 по SSH. Роутер не отвечает."])
    }

    @Test func mutedNotificationsStillRunScripts() async {
        var config = config
        config.notificationsEnabled = false
        let sent = LockIsolated<[LocalNotification]>([])
        let ran = LockIsolated<[String]>([])
        let store = makeStore(config: config, readings: [.success(.stopped), .success(running)], sent: sent, ran: ran)

        await store.send(.checkNow)
        await store.receive(\.checked)
        await store.send(.checkNow)
        await store.receive(\.checked)
        await store.finish()

        #expect(ran.value == ["echo up"])
        #expect(sent.value.isEmpty)
    }

    @Test func runningLoadsTheVersionOnce() async {
        let store = makeStore(config: config, readings: [.success(running)], sent: LockIsolated([]), ran: LockIsolated([]))
        await store.send(.checkNow)
        await store.receive(\.checked)
        await store.receive(\.versionLoaded)
        #expect(store.state.snapshot.version?.skeen == "v5.7.0")
    }

    @Test func bannerButtonsAskTheAppToActOnThem() async {
        let store = makeStore(config: config, readings: [], sent: LockIsolated([]), ran: LockIsolated([]))
        await store.send(.notificationResponse(MonitorNotificationAction.start))
        await store.receive(\.delegate.startService)
        await store.send(.notificationResponse("default"))
        await store.receive(\.delegate.openSettings)
    }
}
