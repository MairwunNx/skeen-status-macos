import Foundation

/// Maps raw status output to a state. Never returns `.unreachable`:
/// unreachability is decided by the I/O layer on connection failure.
nonisolated func parseStatus(_ raw: String, rule: RunningRule) -> SkeenState {
    if matchesRunning(raw, rule: rule) {
        return .running(pid: parseFirstInt(raw, key: "PID"), memoryMB: parseMemoryMB(raw))
    }
    return .stopped
}

nonisolated func matchesRunning(_ raw: String, rule: RunningRule) -> Bool {
    let pattern = rule.pattern
    guard !pattern.isEmpty else { return false }
    switch rule.mode {
    case .substring:
        return raw.contains(pattern)
    case .regex:
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(raw.startIndex..., in: raw)
        return regex.firstMatch(in: raw, range: range) != nil
    }
}

nonisolated func parseFirstInt(_ raw: String, key: String) -> Int? {
    firstCapture(in: raw, pattern: "\(NSRegularExpression.escapedPattern(for: key)):\\s*(\\d+)")
        .flatMap(Int.init)
}

nonisolated func parseMemoryMB(_ raw: String) -> Int? {
    firstCapture(in: raw, pattern: "Memory:\\s*(\\d+)\\s*MB").flatMap(Int.init)
}

private nonisolated func firstCapture(in raw: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(raw.startIndex..., in: raw)
    guard
        let match = regex.firstMatch(in: raw, range: range),
        match.numberOfRanges > 1,
        let captured = Range(match.range(at: 1), in: raw)
    else { return nil }
    return String(raw[captured])
}
