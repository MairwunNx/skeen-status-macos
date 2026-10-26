import Testing
import Foundation
@testable import SkeenStatus

@Suite("Sing-box log parsing")
struct LogLineTests {

    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    @Test func parsesLevelAndMessageWithUTCTime() {
        let raw = "+0000 2026-06-22 19:14:52 INFO [1392057276 0ms] inbound/redirect[0]: hello"
        let lines = parseLogLines(raw, timeZone: utc)
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.time == "19:14:52")
        #expect(line.level == .info)
        #expect(line.message == "[1392057276 0ms] inbound/redirect[0]: hello")
    }

    @Test func convertsToTargetTimeZone() {
        let raw = "+0000 2026-06-22 19:14:52 ERROR connection: i/o timeout"
        let moscow = TimeZone(identifier: "Europe/Moscow")! // UTC+3
        let lines = parseLogLines(raw, timeZone: moscow)
        #expect(lines[0].time == "22:14:52")
        #expect(lines[0].level == .error)
        #expect(lines[0].level.isHighlighted)
    }

    @Test func mapsLevelTokens() {
        #expect(LogLevel(token: "info") == .info)
        #expect(LogLevel(token: "WARN") == .warn)
        #expect(LogLevel(token: "WARNING") == .warn)
        #expect(LogLevel(token: "ERROR") == .error)
        #expect(LogLevel(token: "FATAL") == .fatal)
        #expect(LogLevel(token: "something") == .other)
    }

    @Test func keepsUnparsedLineVerbatim() {
        let raw = "/ # tail -n 50 /opt/var/log/sing-box.log\n   "
        let lines = parseLogLines(raw, timeZone: utc)
        #expect(lines.count == 1)
        #expect(lines[0].time == "")
        #expect(lines[0].level == .other)
        #expect(lines[0].level.label == "")
        #expect(lines[0].message == "/ # tail -n 50 /opt/var/log/sing-box.log")
    }

    @Test func assignsSequentialIdsAndSkipsBlankLines() {
        let raw = """
        +0000 2026-06-22 19:14:52 INFO a

        +0000 2026-06-22 19:14:53 WARN b
        """
        let lines = parseLogLines(raw, timeZone: utc)
        #expect(lines.map(\.id) == [0, 1])
        #expect(lines.map(\.level) == [.info, .warn])
    }
}
