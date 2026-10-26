import Testing
@testable import SkeenStatus

@Suite("SkeenState")
struct SkeenStateTests {

    @Test func phaseIgnoresAssociatedValues() {
        #expect(SkeenState.running(SkeenProcess(pid: 1, memoryMB: 2)).phase == .running)
        #expect(SkeenState.running(SkeenProcess()).phase == .running)
        #expect(SkeenState.stopped.phase == .stopped)
        #expect(SkeenState.unreachable.phase == .unreachable)
        #expect(SkeenState.unknown.phase == .unknown)
    }

    @Test func processOnlyWhileRunning() {
        let process = SkeenProcess(pid: 5733, memoryMB: 117, uptime: "1d 2h 3m")
        #expect(SkeenState.running(process).process == process)
        #expect(SkeenState.stopped.process == nil)
        #expect(SkeenState.unreachable.process == nil)
    }

    @Test func russianTitlePerState() {
        #expect(SkeenState.unknown.title == "проверяю…")
        #expect(SkeenState.running(SkeenProcess()).title == "работает")
        #expect(SkeenState.stopped.title == "остановлен")
        #expect(SkeenState.unreachable.title == "роутер недоступен")
    }

    @Test func statusColorMapping() {
        #expect(statusColor(for: .running(SkeenProcess())) == .green)
        #expect(statusColor(for: .stopped) == .red)
        #expect(statusColor(for: .unreachable) == .yellow)
        #expect(statusColor(for: .unknown) == .gray)
    }
}
