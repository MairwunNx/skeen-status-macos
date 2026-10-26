import Testing
import Foundation
@testable import SkeenStatus

@Suite("Menu and status rendering")
struct MenuModelTests {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ h: Int, _ m: Int, _ s: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: h, minute: m, second: s))!
    }

    @Test func statusColorMapping() {
        #expect(statusColor(for: .running(pid: nil, memoryMB: nil)) == .green)
        #expect(statusColor(for: .stopped) == .red)
        #expect(statusColor(for: .unreachable) == .yellow)
        #expect(statusColor(for: .unknown) == .gray)
    }

    @Test func timeStringIsZeroPadded() {
        #expect(timeString(date(23, 12, 45), calendar: utc) == "23:12:45")
        #expect(timeString(date(1, 2, 3), calendar: utc) == "01:02:03")
    }

    @Test func menuModelForRunningHasPidAndMemory() {
        let model = menuModel(
            state: .running(pid: 5733, memoryMB: 117),
            lastCheck: date(23, 12, 45),
            gateway: "192.168.1.1",
            now: date(23, 12, 45),
            calendar: utc
        )
        #expect(model.title == "Skeen: running")
        #expect(model.statusDetail == "Статус: running (PID 5733)")
        #expect(model.memoryLine == "Память: 117 MB")
        #expect(model.lastCheckLine == "Последняя проверка: 23:12:45")
        #expect(model.routerLine == "Роутер: 192.168.1.1")
    }

    @Test func menuModelForUnknownHasNoMemoryAndDash() {
        let model = menuModel(
            state: .unknown,
            lastCheck: nil,
            gateway: "10.0.0.1",
            now: date(0, 0, 0),
            calendar: utc
        )
        #expect(model.statusDetail == "Статус: unknown")
        #expect(model.memoryLine == nil)
        #expect(model.lastCheckLine == "Последняя проверка: —")
    }

    @Test func footerSummary() {
        let footer = statusFooter(
            state: .running(pid: 1, memoryMB: nil),
            lastCheck: date(23, 12, 45),
            gateway: "192.168.1.1",
            calendar: utc
        )
        #expect(footer == "Статус: running · последняя проверка 23:12:45 · роутер 192.168.1.1")
    }

    @Test func footerWithoutCheckShowsDash() {
        let footer = statusFooter(state: .stopped, lastCheck: nil, gateway: "192.168.1.1", calendar: utc)
        #expect(footer == "Статус: stopped · последняя проверка — · роутер 192.168.1.1")
    }
}
