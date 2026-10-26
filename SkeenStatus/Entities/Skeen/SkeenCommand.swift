import Foundation

/// The service-control actions exposed in Settings, mapped to `skeen` subcommands.
enum SkeenControl: String, CaseIterable, Identifiable, Sendable {
    case start
    case stop
    case restart
    case reload
    case check

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return String(localized: "Start")
        case .stop: return String(localized: "Stop")
        case .restart: return String(localized: "Restart")
        case .reload: return String(localized: "Reload")
        case .check: return String(localized: "Check Config")
        }
    }

    var hint: String {
        switch self {
        case .start: return String(localized: "Starts sing-box. Changes nothing if it already runs.")
        case .stop: return String(localized: "Stops sing-box. Traffic will bypass the proxy.")
        case .restart: return String(localized: "A full restart: skeen sets up the firewall and sing-box again.")
        case .reload: return String(localized: "Restarts only sing-box and keeps the firewall rules.")
        case .check: return String(localized: "Checks the sing-box config without restarting anything.")
        }
    }

    var systemImage: String {
        switch self {
        case .start: return "play.fill"
        case .stop: return "stop.fill"
        case .restart: return "arrow.clockwise"
        case .reload: return "arrow.triangle.2.circlepath"
        case .check: return "checkmark.seal"
        }
    }

    /// `stop`, `restart`, and `reload` interrupt traffic, so the UI confirms them first.
    var isDisruptive: Bool {
        switch self {
        case .start, .check: return false
        case .stop, .restart, .reload: return true
        }
    }

    /// Whether the command may change the running state, so a fresh status
    /// check should follow it.
    var changesState: Bool {
        self != .check
    }
}

/// Parsed output of `skeen version`.
struct SkeenVersion: Equatable, Sendable {
    var skeen: String?
    var singBox: String?
    var environment: String?
    var tags: String?
    var revision: String?
    var cgo: String?

    /// Short one-line summary for compact display, e.g. "SKeen v4.0.3 · Sing-box v1.12.22".
    var summary: String {
        var parts: [String] = []
        if let skeen { parts.append("SKeen \(skeen)") }
        if let singBox { parts.append("Sing-box \(singBox)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var isEmpty: Bool {
        skeen == nil && singBox == nil && environment == nil
            && tags == nil && revision == nil && cgo == nil
    }
}

/// Extracts version fields from the textual output of `skeen version`. Decorative
/// separator lines and any surrounding shell noise are ignored.
func parseSkeenVersion(_ raw: String) -> SkeenVersion {
    let clean = cleanOutput(raw)

    func value(_ key: String) -> String? {
        for line in clean.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix(key.lowercased() + ":") else { continue }
            let v = trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
        return nil
    }

    return SkeenVersion(
        skeen: value("SKeen"),
        singBox: value("Sing-box"),
        environment: value("Environment"),
        tags: value("Tags"),
        revision: value("Revision"),
        cgo: value("CGO")
    )
}
