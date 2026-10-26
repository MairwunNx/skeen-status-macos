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
        let state = parseStatus(runningSample, detection: .rule, rule: substring("Status: running"))
        #expect(state == .running(pid: 5733, memoryMB: 117))
    }

    @Test func stoppedOutputIsStopped() {
        #expect(parseStatus("Status: stopped", detection: .rule, rule: substring("Status: running")) == .stopped)
    }

    @Test func missingMarkerIsStopped() {
        #expect(parseStatus("some unrelated text", detection: .rule, rule: substring("Status: running")) == .stopped)
    }

    @Test func runningWithoutDetailsHasNilFields() {
        let state = parseStatus("Status: running", detection: .rule, rule: substring("Status: running"))
        #expect(state == .running(pid: nil, memoryMB: nil))
    }

    @Test func emptyPatternNeverMatches() {
        #expect(parseStatus(runningSample, detection: .rule, rule: substring("")) == .stopped)
    }

    @Test func regexRuleMatches() {
        let rule = RunningRule(pattern: #"Status:\s+running"#, mode: .regex)
        let state = parseStatus("Status:    running\nPID: 42", detection: .rule, rule: rule)
        #expect(state == .running(pid: 42, memoryMB: nil))
    }

    @Test func invalidRegexDoesNotCrash() {
        let rule = RunningRule(pattern: "[unclosed", mode: .regex)
        #expect(parseStatus(runningSample, detection: .rule, rule: rule) == .stopped)
    }

    // Real output of skeen 5.7: Russian labels and a colored status word.
    private let russianRunning = "Статус: \u{1B}[32mrunning\u{1B}[0m\r\nPID: 16460\r\nВремя работы: 18d 8h 51m\r\nПамять: 63 MB (пиковая: 82 MB)\r\n"

    @Test func automaticReadsLocalizedColoredOutput() {
        let state = parseStatus(russianRunning, detection: .automatic, rule: substring("Status: running"))
        #expect(state == .running(pid: 16460, memoryMB: 63))
    }

    @Test func automaticReadsStopped() {
        let raw = "Статус: \u{1B}[31mstopped\u{1B}[0m"
        #expect(parseStatus(raw, detection: .automatic, rule: substring("")) == .stopped)
    }

    @Test func automaticTreatsPidLineAsRunning() {
        #expect(parseStatus("PID: 7", detection: .automatic, rule: substring("")) == .running(pid: 7, memoryMB: nil))
    }

    @Test func automaticLeavesUnrecognizedOutputUnknown() {
        #expect(parseStatus("sh: skeen: not found", detection: .automatic, rule: substring("")) == .unknown)
    }

    @Test func automaticIgnoresRunningInsideOtherWords() {
        #expect(parseStatus("Status: stopped (was runningx)", detection: .automatic, rule: substring("")) == .stopped)
    }

    @Test func pidParsedRegardlessOfMarkerPosition() {
        #expect(parseFirstInt("PID: 19324", key: "PID") == 19324)
        #expect(parseFirstInt("no pid here", key: "PID") == nil)
    }

    @Test func memoryParsedFromMBLine() {
        #expect(parseMemoryMB("Memory: 115 MB (peak: 115 MB)") == 115)
        #expect(parseMemoryMB("Память: 63 MB (пиковая: 82 MB)") == 63)
        #expect(parseMemoryMB("Memory: unknown") == nil)
    }
}
