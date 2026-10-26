import Foundation

/// A unique sentinel used to delimit command output in a noisy PTY stream.
func makeMarker() -> String {
    "__SKEEN_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
}

/// Wraps a command so the shell prints unique begin/end markers around its
/// output.
///
/// Everything is chained on one line with `;` so the remote line editor never
/// splits it across prompts, and so the trailing marker still runs even when
/// the command exits non-zero. This runs only after `exec sh`, i.e. in a real
/// POSIX shell.
func wrapCommand(_ command: String, begin: String, end: String) -> String {
    "echo \(echoArgument(for: begin)); \(command); echo \(echoArgument(for: end))\n"
}

/// Splits a marker with an empty-string quote so the PTY's input echo can never
/// contain the contiguous marker and trigger detection early; the shell removes
/// the `""` before printing, so the executed output is contiguous.
func echoArgument(for marker: String) -> String {
    let mid = marker.index(marker.startIndex, offsetBy: marker.count / 2)
    return String(marker[..<mid]) + "\"\"" + String(marker[mid...])
}

/// Returns the text printed between the begin and end markers, or nil if the
/// end marker has not arrived yet.
func extractBetween(from buffer: String, begin: String, end: String) -> String? {
    guard let beginRange = buffer.range(of: begin) else { return nil }
    guard let endRange = buffer.range(of: end, range: beginRange.upperBound..<buffer.endIndex) else { return nil }
    return String(buffer[beginRange.upperBound..<endRange.lowerBound])
}
