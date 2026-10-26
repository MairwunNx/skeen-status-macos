import Foundation

/// Severity of a sing-box log line, used to tint the row faintly in the UI.
enum LogLevel: String, Equatable, Sendable {
    case trace
    case debug
    case info
    case warn
    case error
    case fatal
    case panic
    case other

    init(token: String) {
        switch token.uppercased() {
        case "TRACE": self = .trace
        case "DEBUG": self = .debug
        case "INFO": self = .info
        case "WARN", "WARNING": self = .warn
        case "ERROR", "ERRO", "ERR": self = .error
        case "FATAL": self = .fatal
        case "PANIC": self = .panic
        default: self = .other
        }
    }

    /// Short uppercase badge shown before the message; empty for unrecognized lines.
    var label: String {
        switch self {
        case .other: return ""
        default: return rawValue.uppercased()
        }
    }

    /// Whether the whole row gets a faint background tint (only the noisy levels).
    var isHighlighted: Bool {
        switch self {
        case .warn, .error, .fatal, .panic: return true
        default: return false
        }
    }
}

/// One parsed sing-box log line: a formatted local timestamp, a severity and
/// the remaining message text. Lines that don't match the expected shape are
/// kept verbatim as `.other` with an empty time.
struct LogLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: String
    let level: LogLevel
    let message: String
}

private let logLineRegex = try! NSRegularExpression(
    pattern: #"^([+-]\d{4})\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(\w+)\s+(.*)$"#
)

private func logInputFormatter() -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return f
}

private func logTimeFormatter(_ timeZone: TimeZone) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm:ss"
    f.timeZone = timeZone
    return f
}

/// Parses raw `tail` output of the sing-box log into displayable lines.
///
/// The on-disk format is `+0000 2026-06-22 19:14:52 INFO <message>`; the leading
/// offset/date/time is converted into a clean `HH:mm:ss` marker in `timeZone`
/// (the local Mac time by default).
func parseLogLines(_ raw: String, timeZone: TimeZone = .current) -> [LogLine] {
    let input = logInputFormatter()
    let output = logTimeFormatter(timeZone)

    let lines = cleanOutput(raw)
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    return lines.enumerated().map { index, line in
        parseLogLine(line, id: index, input: input, output: output)
    }
}

private func parseLogLine(
    _ line: String,
    id: Int,
    input: DateFormatter,
    output: DateFormatter
) -> LogLine {
    let ns = line as NSString
    let full = NSRange(location: 0, length: ns.length)
    guard
        let match = logLineRegex.firstMatch(in: line, range: full),
        match.numberOfRanges == 6
    else {
        return LogLine(id: id, time: "", level: .other, message: line)
    }

    let offset = ns.substring(with: match.range(at: 1))
    let date = ns.substring(with: match.range(at: 2))
    let clock = ns.substring(with: match.range(at: 3))
    let level = LogLevel(token: ns.substring(with: match.range(at: 4)))
    let message = ns.substring(with: match.range(at: 5))

    let time: String
    if let parsed = input.date(from: "\(date) \(clock) \(offset)") {
        time = output.string(from: parsed)
    } else {
        time = clock
    }

    return LogLine(id: id, time: time, level: level, message: message)
}
