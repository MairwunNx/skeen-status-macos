import Foundation

/// Strips ANSI/VT100 escape sequences left by interactive line editors and
/// colored output.
func stripANSI(_ raw: String) -> String {
    let pattern = "\u{1B}\\[[0-9;?]*[ -/]*[@-~]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
    let range = NSRange(raw.startIndex..., in: raw)
    return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
}

/// Cleans command output for parsing and logging: strips escapes, normalizes
/// CRLF, and trims surrounding whitespace.
func cleanOutput(_ raw: String) -> String {
    stripANSI(raw)
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// `HH:mm:ss` in the given calendar's time zone.
func timeString(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.hour, .minute, .second], from: date)
    return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
}

/// Short Russian duration such as «3 д 4 ч», «12 мин» or «40 с».
func durationString(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded()))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    if days > 0 { return hours > 0 ? "\(days) д \(hours) ч" : "\(days) д" }
    if hours > 0 { return minutes > 0 ? "\(hours) ч \(minutes) мин" : "\(hours) ч" }
    if minutes > 0 { return "\(minutes) мин" }
    return "\(seconds) с"
}

/// Binary byte count with one decimal, e.g. «1.5 ГБ».
func byteString(_ bytes: Int64) -> String {
    let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
    var value = Double(max(0, bytes))
    var unit = 0
    while value >= 1024, unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    return unit == 0 ? "\(Int(value)) \(units[unit])" : String(format: "%.1f %@", value, units[unit])
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Runs an async throwing body and captures the outcome.
func attempt<T>(_ body: () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await body())
    } catch {
        return .failure(error)
    }
}
