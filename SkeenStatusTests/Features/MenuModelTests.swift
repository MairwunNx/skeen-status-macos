import Testing
import Foundation
@testable import SkeenStatus

@Suite("Menu, banners, and helpers")
struct MenuModelTests {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ h: Int, _ m: Int, _ s: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: h, minute: m, second: s))!
    }

    private let runtime = SingBoxRuntime(
        version: "sing-box 1.14.2",
        mode: "rule",
        modes: ["rule", "global"],
        groups: [
            OutboundGroup(name: "proxy", type: "Selector", now: "NL", options: ["NL", "direct"]),
            OutboundGroup(name: "auto", type: "URLTest", now: "NL", options: ["NL"]),
        ],
        connections: 3,
        downloadTotal: 1_610_612_736,
        uploadTotal: 1024,
        memoryBytes: nil
    )

    @Test func timeStringIsZeroPadded() {
        #expect(timeString(date(23, 12, 45), calendar: utc) == "23:12:45")
        #expect(timeString(date(1, 2, 3), calendar: utc) == "01:02:03")
    }

    @Test func runningMenuShowsProcessRuntimeAndSelectors() {
        let snapshot = SkeenSnapshot(
            state: .running(SkeenProcess(pid: 5733, memoryMB: 117, uptime: "2d 1h 0m")),
            lastCheck: date(23, 12, 45)
        )
        let model = menuModel(snapshot: snapshot, singBox: SingBoxSnapshot(runtime: runtime), gateway: "192.168.1.1", calendar: utc)
        #expect(model.title == "Skeen: работает")
        #expect(model.color == .green)
        #expect(model.processLine == "PID 5733 · 117 МБ · работает 2d 1h 0m")
        #expect(model.runtimeLine == "sing-box 1.14.2 · ↓ 1.5 ГБ ↑ 1.0 КБ")
        #expect(model.lastCheckLine == "Проверено в 23:12:45")
        #expect(model.routerLine == "Роутер: 192.168.1.1")
        #expect(model.routeLine == "proxy → NL · по правилам")
        #expect(model.canStart == false)
    }

    @Test func stoppedMenuOffersStartAndHidesTheAPI() {
        let snapshot = SkeenSnapshot(state: .stopped, lastError: "boom")
        let model = menuModel(snapshot: snapshot, singBox: SingBoxSnapshot(runtime: runtime), gateway: "10.0.0.1", calendar: utc)
        #expect(model.canStart)
        #expect(model.runtimeLine == nil)
        #expect(model.routeLine == nil)
        #expect(model.errorLine == "boom")
        #expect(model.lastCheckLine == "Проверено в —")
    }

    @Test func downBannerSaysHowLongItRan() {
        let banner = notificationContent(
            .down,
            state: .stopped,
            previousPhaseSince: date(20, 0, 0),
            now: date(23, 30, 0),
            gateway: "192.168.1.1",
            reason: nil
        )
        #expect(banner.id == "skeen.state")
        #expect(banner.title == "skeen остановлен")
        #expect(banner.body.hasSuffix("До этого проработал 3 ч 30 мин."))
        #expect(banner.category?.actions.map(\.id) == [MonitorNotificationAction.start, MonitorNotificationAction.open])
    }

    @Test func recoveredBannerSaysHowLongItWasDown() {
        let banner = notificationContent(
            .recovered,
            state: .running(SkeenProcess(pid: 42)),
            previousPhaseSince: date(23, 0, 0),
            now: date(23, 0, 40),
            gateway: "192.168.1.1",
            reason: nil
        )
        #expect(banner.body == "sing-box снова работает (PID 42). Простой: 40 с.")
        #expect(banner.category == nil)
    }

    @Test func unreachableBannerCarriesTheReason() {
        let banner = notificationContent(.unreachable, state: .unreachable, previousPhaseSince: nil, now: date(0, 0, 0), gateway: "10.0.0.1", reason: "Роутер не отвечает")
        #expect(banner.body == "Не удаётся связаться с 10.0.0.1 по SSH. Роутер не отвечает.")
    }

    @Test func durationsAndBytesInRussian() {
        #expect(durationString(40) == "40 с")
        #expect(durationString(125) == "2 мин")
        #expect(durationString(3 * 3600) == "3 ч")
        #expect(durationString(26 * 3600) == "1 д 2 ч")
        #expect(byteString(512) == "512 Б")
        #expect(byteString(1536) == "1.5 КБ")
    }
}
