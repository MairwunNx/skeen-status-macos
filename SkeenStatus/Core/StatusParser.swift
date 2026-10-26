import Foundation

/// Maps raw status output to a state. Never returns `.unreachable`:
/// unreachability is decided by the I/O layer on connection failure.
///
/// `.automatic` reads the shape of `skeen status`, not its wording: skeen
/// prints a `PID:` line only while sing-box runs, and the words `running` and
/// `stopped` survive every translation. Output that says neither is
/// `.unknown`, so a missing binary never looks like a crash.
nonisolated func parseStatus(_ raw: String, detection: StatusDetection, rule: RunningRule) -> SkeenState {
    let clean = cleanOutput(raw)
    let running: Bool
    switch detection {
    case .automatic:
        if parseFirstInt(clean, key: "PID") != nil || containsWord(clean, "running") {
            running = true
        } else if containsWord(clean, "stopped") {
            running = false
        } else {
            return .unknown
        }
    case .rule:
        running = matchesRunning(clean, rule: rule)
    }
    guard running else { return .stopped }
    return .running(pid: parseFirstInt(clean, key: "PID"), memoryMB: parseMemoryMB(clean))
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

/// Reads the resident memory from `Memory: 117 MB` or its Russian form `Память: 63 MB`.
nonisolated func parseMemoryMB(_ raw: String) -> Int? {
    firstCapture(in: raw, pattern: "(?:Memory|Память):\\s*(\\d+)\\s*MB").flatMap(Int.init)
}

private nonisolated func containsWord(_ raw: String, _ word: String) -> Bool {
    firstCapture(in: raw, pattern: "(?i)\\b(\(word))\\b") != nil
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
