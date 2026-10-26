import Testing
@testable import SkeenStatus

@Suite("State transitions")
struct TransitionTests {

    private let running = SkeenState.running(SkeenProcess(pid: 1, memoryMB: 2))

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
            from: .running(SkeenProcess(pid: 1, memoryMB: 2)),
            to: .running(SkeenProcess(pid: 9, memoryMB: 9)),
            treatUnreachableAsDown: false
        )
        #expect(effects.isEmpty)
    }

    @Test func firstReadingNeverRunsScripts() {
        #expect(transition(from: .unknown, to: running, treatUnreachableAsDown: false).isEmpty)
    }

    @Test func stoppedAtLaunchOnlyNotifies() {
        #expect(transition(from: .unknown, to: .stopped, treatUnreachableAsDown: true) == [.notify(.stoppedAtLaunch)])
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
}

@Suite("Reading and confirming a check")
struct ConfirmationTests {

    private let running = SkeenState.running(SkeenProcess(pid: 1, memoryMB: 2))

    @Test func sshVerdictWins() {
        #expect(resolveState(CheckReading(ssh: .stopped, apiAlive: true), previous: running) == .stopped)
        #expect(resolveState(CheckReading(ssh: running, apiAlive: false), previous: .stopped) == running)
    }

    @Test func liveAPIMeansRunningWhenSSHFails() {
        let reading = CheckReading(ssh: nil, sshError: "timeout", apiAlive: true)
        #expect(resolveState(reading, previous: running) == running)
        #expect(resolveState(reading, previous: .unknown) == .running(SkeenProcess()))
    }

    @Test func liveAPIMeansRunningWhenOutputIsUnreadable() {
        #expect(resolveState(CheckReading(ssh: .unknown, apiAlive: true), previous: .stopped) == .running(SkeenProcess()))
        #expect(resolveState(CheckReading(ssh: .unknown, apiAlive: false), previous: .stopped) == .unknown)
    }

    @Test func noSSHAndNoAPIIsUnreachable() {
        #expect(resolveState(CheckReading(ssh: nil, sshError: "x", apiAlive: false), previous: running) == .unreachable)
        #expect(resolveState(CheckReading(ssh: nil, sshError: "x", apiAlive: nil), previous: running) == .unreachable)
    }

    @Test func firstBadReadingWaitsForASecond() {
        let first = confirm(current: running, candidate: .stopped, pending: nil)
        #expect(first == Confirmation(state: running, pending: .stopped, recheckSoon: true))

        let second = confirm(current: running, candidate: .stopped, pending: first.pending)
        #expect(second == Confirmation(state: .stopped, pending: nil, recheckSoon: false))
    }

    @Test func aDifferentBadReadingStartsOver() {
        let result = confirm(current: running, candidate: .unreachable, pending: .stopped)
        #expect(result == Confirmation(state: running, pending: .unreachable, recheckSoon: true))
    }

    @Test func goodNewsAndFirstReadingApplyAtOnce() {
        #expect(confirm(current: .stopped, candidate: running, pending: nil).state == running)
        #expect(confirm(current: .unknown, candidate: .stopped, pending: nil).state == .stopped)
        #expect(confirm(current: running, candidate: running, pending: .stopped).pending == nil)
    }
}
