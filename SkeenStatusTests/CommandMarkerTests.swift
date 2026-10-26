import Testing
import Foundation
@testable import SkeenStatus

@Suite("Command markers")
struct CommandMarkerTests {

    @Test func markerIsUniqueAndShellSafe() {
        let a = makeMarker()
        let b = makeMarker()
        #expect(a != b)
        #expect(a.hasPrefix("__SKEEN_"))
        #expect(!a.contains("-"))
    }

    @Test func echoArgumentBreaksContiguousMarker() {
        let marker = makeMarker()
        let arg = echoArgument(for: marker)
        #expect(arg.contains("\"\""))
        #expect(!arg.contains(marker))
        #expect(arg.replacingOccurrences(of: "\"\"", with: "") == marker)
    }

    @Test func wrapCommandChainsOnOneLine() {
        let payload = wrapCommand("skeen status", begin: "BEGIN", end: "END")
        #expect(payload == "echo \(echoArgument(for: "BEGIN")); skeen status; echo \(echoArgument(for: "END"))\n")
        #expect(payload.contains("; skeen status; "))
        #expect(payload.hasSuffix("\n"))
        #expect(payload.filter { $0 == "\n" }.count == 1)
    }

    @Test func extractBetweenReturnsInnerText() {
        let buffer = "noise BEGIN\nhello world\nEND trailing"
        #expect(extractBetween(from: buffer, begin: "BEGIN", end: "END") == "\nhello world\n")
    }

    @Test func extractBetweenNilUntilEndArrives() {
        #expect(extractBetween(from: "BEGIN partial output", begin: "BEGIN", end: "END") == nil)
    }

    @Test func extractBetweenRequiresEndAfterBegin() {
        #expect(extractBetween(from: "END comes BEGIN first", begin: "BEGIN", end: "END") == nil)
    }

    @Test func stripANSIRemovesEscapeSequences() {
        let raw = "a\u{1B}[Kb\u{1B}[2Jc\u{1B}[0m"
        #expect(stripANSI(raw) == "abc")
    }

    @Test func cleanOutputStripsEscapesNormalizesAndTrims() {
        let raw = "\u{1B}[K  Status: running\r\nPID: 1\r\n  "
        #expect(cleanOutput(raw) == "Status: running\nPID: 1")
    }

    @Test func capturePipelineRecoversRunningFromNoisyEcho() {
        let begin = makeMarker()
        let end = makeMarker()
        let echoedInput = "e\u{1B}[Kc\u{1B}[Kh\u{1B}[Ko\u{1B}[K \(echoArgument(for: begin))"
        let buffer = """
        \(echoedInput)
        \(begin)
        Status: running\r
        PID: 19324\r
        Memory: 115 MB (peak: 115 MB)\r
        \(end)
        / #
        """

        let inner = extractBetween(from: buffer, begin: begin, end: end)
        let cleaned = cleanOutput(inner ?? "")
        let state = parseStatus(cleaned, detection: .automatic, rule: RunningRule(pattern: "Status: running", mode: .substring))
        #expect(state == .running(pid: 19324, memoryMB: 115))
    }
}
