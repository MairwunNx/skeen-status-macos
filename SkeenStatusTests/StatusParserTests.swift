import Testing
@testable import SkeenStatus

@Suite("Status parsing")
struct StatusParserTests {

    private let runningSample = """
    Status: running
    PID: 5733
    Memory: 117 MB (peak: 128 MB)
    Threads: 10
    """

    private func substring(_ pattern: String) -> RunningRule {
        RunningRule(pattern: pattern, mode: .substring)
    }

    @Test func runningOutputParsesPidAndMemory() {
        let state = parseStatus(runningSample, rule: substring("Status: running"))
        #expect(state == .running(pid: 5733, memoryMB: 117))
    }

    @Test func stoppedOutputIsStopped() {
        #expect(parseStatus("Status: stopped", rule: substring("Status: running")) == .stopped)
    }

    @Test func missingMarkerIsStopped() {
        #expect(parseStatus("some unrelated text", rule: substring("Status: running")) == .stopped)
    }

    @Test func runningWithoutDetailsHasNilFields() {
        let state = parseStatus("Status: running", rule: substring("Status: running"))
        #expect(state == .running(pid: nil, memoryMB: nil))
    }

    @Test func emptyPatternNeverMatches() {
        #expect(parseStatus(runningSample, rule: substring("")) == .stopped)
    }

    @Test func regexRuleMatches() {
        let rule = RunningRule(pattern: #"Status:\s+running"#, mode: .regex)
        let state = parseStatus("Status:    running\nPID: 42", rule: rule)
        #expect(state == .running(pid: 42, memoryMB: nil))
    }

    @Test func invalidRegexDoesNotCrash() {
        let rule = RunningRule(pattern: "[unclosed", mode: .regex)
        #expect(parseStatus(runningSample, rule: rule) == .stopped)
    }

    @Test func pidParsedRegardlessOfMarkerPosition() {
        #expect(parseFirstInt("PID: 19324", key: "PID") == 19324)
        #expect(parseFirstInt("no pid here", key: "PID") == nil)
    }

    @Test func memoryParsedFromMBLine() {
        #expect(parseMemoryMB("Memory: 115 MB (peak: 115 MB)") == 115)
        #expect(parseMemoryMB("Memory: unknown") == nil)
    }
}
