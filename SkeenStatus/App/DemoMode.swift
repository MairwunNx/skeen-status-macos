import ComposableArchitecture
import Foundation

/// `--demo` runs the app against a made-up router: no network, no Keychain,
/// no files. UI tests and the README screenshots use it, so they never show a
/// real password, address, or someone's browsing in the log.
enum DemoMode {
    static var isOn: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
    }

    static func apply(to dependencies: inout DependencyValues) {
        let config = demoConfig

        dependencies.configStore = .inMemory(config)
        dependencies.language = LanguageClient(
            choice: { .system },
            setChoice: { _ in },
            active: { Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en" },
            systemPreferred: { Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en" },
            relaunch: {}
        )
        dependencies.metricsStore = MetricsStore(load: { [] }, save: { _ in })
        dependencies.keychain = .inMemory([config.login: "demo-password"])
        dependencies.appLog = AppLog(write: { _ in }, url: { URL(fileURLWithPath: "/dev/null") })
        dependencies.loginItem = LoginItem(isEnabled: { true }, setEnabled: { _ in })
        dependencies.notifier = Notifier(authorize: { true }, send: { _ in }, responses: { .finished })
        dependencies.localShell = LocalShell(run: { _ in LocalCommandResult(exitCode: 0, output: "") })
        dependencies.routerShell = RouterShell(
            configure: { _ in },
            run: { _, _ in "" },
            reconnect: {},
            hostKey: { config.hostKey },
            test: { _ in config.hostKey }
        )
        dependencies.skeen = SkeenClient(
            status: { _, detection, rule in
                try await Task.sleep(for: .milliseconds(150))
                return parseStatus(demoStatus, detection: detection, rule: rule)
            },
            version: { _ in parseSkeenVersion(demoVersion) },
            control: { _, control in
                try await Task.sleep(for: .milliseconds(600))
                return control == .check ? "Конфигурация sing-box в порядке" : "Sing-box запущен"
            },
            logs: { _ in parseLogLines(demoLog, timeZone: TimeZone(identifier: "Europe/Moscow")!) }
        )
        let totals = LockIsolated((date: Date(), down: Int64(18_734_221_312), up: Int64(2_311_854_080)))
        dependencies.clashAPI = ClashAPI(runtime: { _ in
            let now = Date()
            let t = now.timeIntervalSince1970
            let current = totals.withValue { totals in
                let seconds = now.timeIntervalSince(totals.date)
                totals.down += Int64(demoDownload(t) * seconds)
                totals.up += Int64(demoUpload(t) * seconds)
                totals.date = now
                return totals
            }
            return demoRuntime(at: now, download: current.down, upload: current.up)
        })
    }

    /// Three days of made-up history, so the charts have a shape from the start.
    static func history(until now: Date) -> [MetricSample] {
        let samples = stride(from: 3 * 86_400.0, through: 2, by: -15).map { offset in
            let date = now.addingTimeInterval(-offset)
            let t = date.timeIntervalSince1970
            return MetricSample(
                date: date,
                phase: (offset > 1500 && offset < 1590) || (offset > 52_000 && offset < 52_300) ? .stopped : .running,
                memoryMB: 56 + Int((4 * sin(t / 5_400) + 2 * sin(t / 900)).rounded()),
                connections: offset > 3_600 ? 30 + Int(18 * max(0, sin(t / 13_750))) : demoConnections(t),
                downloadRate: offset > 3_600 ? 400_000 + 1_800_000 * max(0, sin(t / 13_750)) : demoDownload(t),
                uploadRate: offset > 3_600 ? 60_000 + 220_000 * max(0, sin(t / 13_750 + 0.3)) : demoUpload(t)
            )
        }
        return compact(samples, now: now)
    }

    private static func demoRuntime(at date: Date, download: Int64, upload: Int64) -> SingBoxRuntime {
        let t = date.timeIntervalSince1970
        return SingBoxRuntime(
            version: "sing-box 1.14.2",
            mode: "rule",
            modes: ["rule", "global", "direct"],
            groups: [
                OutboundGroup(name: "proxy", type: "Selector", now: "VLESS-NL", options: ["VLESS-NL", "VLESS-FI", "VLESS-DE", "auto", "direct"]),
                OutboundGroup(name: "auto", type: "URLTest", now: "VLESS-NL", options: ["VLESS-NL", "VLESS-FI", "VLESS-DE"]),
            ],
            connections: demoConnections(t),
            downloadTotal: download,
            uploadTotal: upload,
            memoryBytes: 24_117_248
        )
    }

    private static func demoConnections(_ t: TimeInterval) -> Int {
        38 + Int(14 * sin(t / 420) + 6 * sin(t / 97))
    }

    private static func demoDownload(_ t: TimeInterval) -> Double {
        max(60_000, 1_400_000 + 1_100_000 * sin(t / 170) + 500_000 * sin(t / 37) + 250_000 * sin(t / 11))
    }

    private static func demoUpload(_ t: TimeInterval) -> Double {
        max(15_000, 180_000 + 120_000 * sin(t / 130 + 1) + 60_000 * sin(t / 23))
    }

    private static var demoConfig: Config {
        var config = Config.default
        config.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDemoDemoDemoDemoDemoDemoDemoDemoDemoDemo"
        config.launchAtLogin = true
        config.onDownScripts = ["osascript -e 'display notification \"VPN off\"'"]
        return config
    }

    private static let demoStatus = """
    Статус: \u{1B}[32mrunning\u{1B}[0m
    PID: 4127
    Время работы: 6d 3h 12m
    Память: 57 MB (пиковая: 71 MB)
    Потоки: 11
    """

    private static let demoVersion = """
    ------------------------------------------------
    SKeen: v5.7.0
    ------------------------------------------------
    Sing-box: v1.14.2
    Environment: go1.25.5 linux/arm64
    """

    private static let demoLog = """
    +0000 2026-10-26 18:41:02 INFO [1204331871 0ms] inbound/redirect[redirect-in]: inbound connection from 192.168.1.23:51544
    +0000 2026-10-26 18:41:02 INFO [1204331871 0ms] inbound/redirect[redirect-in]: inbound connection to example.org:443
    +0000 2026-10-26 18:41:02 INFO [1204331871 31ms] outbound/vless[VLESS-NL]: outbound connection to example.org:443
    +0000 2026-10-26 18:41:05 DEBUG dns: exchanged example.net A 300
    +0000 2026-10-26 18:41:07 INFO [2387711092 0ms] inbound/tproxy[tproxy-in]: inbound packet connection from 192.168.1.41:60311
    +0000 2026-10-26 18:41:07 INFO [2387711092 2ms] outbound/direct[direct]: outbound packet connection
    +0000 2026-10-26 18:41:09 WARN [3561200148 5.02s] outbound/vless[VLESS-DE]: dial tcp: i/o timeout
    +0000 2026-10-26 18:41:11 INFO outbound/urltest[auto]: switched to VLESS-NL (48ms)
    +0000 2026-10-26 18:41:14 INFO [4012998211 0ms] inbound/redirect[redirect-in]: inbound connection to updates.example.com:443
    +0000 2026-10-26 18:41:14 INFO [4012998211 44ms] outbound/vless[VLESS-NL]: outbound connection to updates.example.com:443
    +0000 2026-10-26 18:41:18 ERROR [4401255370 0ms] inbound/redirect[redirect-in]: process connection from 192.168.1.23:51601: EOF
    +0000 2026-10-26 18:41:21 INFO router: updated rule-set antizapret
    +0000 2026-10-26 18:41:24 INFO [5120044718 0ms] inbound/redirect[redirect-in]: inbound connection to video.example.net:443
    +0000 2026-10-26 18:41:24 INFO [5120044718 39ms] outbound/vless[VLESS-NL]: outbound connection to video.example.net:443
    """
}
