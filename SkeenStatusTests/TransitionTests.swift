import Testing
@testable import SkeenStatus

@Suite("State transitions")
struct TransitionTests {

    private let running = SkeenState.running(pid: 1, memoryMB: 2)

    @Test func runningToStoppedFiresDown() {
        let effects = transition(from: running, to: .stopped, treatUnreachableAsDown: false)
        #expect(effects == [.runDownScripts, .notify(.down)])
    }

    @Test func stoppedToRunningFiresRecover() {
        let effects = transition(from: .stopped, to: running, treatUnreachableAsDown: false)
        #expect(effects == [.runRecoverScripts, .notify(.recovered)])
    }

    @Test func samePhaseProducesNothing() {
        let effects = transition(
            from: .running(pid: 1, memoryMB: 2),
            to: .running(pid: 9, memoryMB: 9),
            treatUnreachableAsDown: false
        )
        #expect(effects.isEmpty)
    }

    @Test func firstStartFromUnknownDoesNotFireScripts() {
        #expect(transition(from: .unknown, to: running, treatUnreachableAsDown: false).isEmpty)
        #expect(transition(from: .unknown, to: .stopped, treatUnreachableAsDown: false).isEmpty)
    }

    @Test func enteringUnreachableOnlyNotifies() {
        let fromRunning = transition(from: running, to: .unreachable, treatUnreachableAsDown: false)
        #expect(fromRunning == [.notify(.unreachable)])

        let fromStopped = transition(from: .stopped, to: .unreachable, treatUnreachableAsDown: false)
        #expect(fromStopped == [.notify(.unreachable)])
    }

    @Test func leavingUnreachableDoesNotFireScriptsByDefault() {
        #expect(transition(from: .unreachable, to: running, treatUnreachableAsDown: false).isEmpty)
        #expect(transition(from: .unreachable, to: .stopped, treatUnreachableAsDown: false).isEmpty)
    }

    @Test func treatUnreachableAsDownRunningToUnreachableFiresDown() {
        let effects = transition(from: running, to: .unreachable, treatUnreachableAsDown: true)
        #expect(effects == [.runDownScripts, .notify(.down)])
    }

    @Test func treatUnreachableAsDownUnreachableToRunningFiresRecover() {
        let effects = transition(from: .unreachable, to: running, treatUnreachableAsDown: true)
        #expect(effects == [.runRecoverScripts, .notify(.recovered)])
    }

    @Test func treatUnreachableAsDownStoppedToUnreachableStillNotifies() {
        let effects = transition(from: .stopped, to: .unreachable, treatUnreachableAsDown: true)
        #expect(effects == [.notify(.unreachable)])
    }

    @Test func treatUnreachableAsDownRunningToUnreachableSkipsRedundantUnreachableNotice() {
        let effects = transition(from: running, to: .unreachable, treatUnreachableAsDown: true)
        #expect(!effects.contains(.notify(.unreachable)))
    }
}
