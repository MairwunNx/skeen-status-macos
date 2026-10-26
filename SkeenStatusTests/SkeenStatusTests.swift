import Testing
@testable import SkeenStatus

@Suite("SkeenState")
struct SkeenStateTests {

    @Test func phaseIgnoresAssociatedValues() {
        #expect(SkeenState.running(pid: 1, memoryMB: 2).phase == .running)
        #expect(SkeenState.running(pid: nil, memoryMB: nil).phase == .running)
        #expect(SkeenState.stopped.phase == .stopped)
        #expect(SkeenState.unreachable.phase == .unreachable)
        #expect(SkeenState.unknown.phase == .unknown)
    }

    @Test func pidAndMemoryOnlyForRunning() {
        let running = SkeenState.running(pid: 5733, memoryMB: 117)
        #expect(running.pid == 5733)
        #expect(running.memoryMB == 117)

        #expect(SkeenState.stopped.pid == nil)
        #expect(SkeenState.stopped.memoryMB == nil)
        #expect(SkeenState.running(pid: nil, memoryMB: nil).pid == nil)
    }

    @Test func keywordPerState() {
        #expect(SkeenState.unknown.keyword == "unknown")
        #expect(SkeenState.running(pid: nil, memoryMB: nil).keyword == "running")
        #expect(SkeenState.stopped.keyword == "stopped")
        #expect(SkeenState.unreachable.keyword == "unreachable")
    }
}
