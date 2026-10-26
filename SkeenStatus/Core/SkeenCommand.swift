import Foundation

/// The service-control actions exposed in Settings, mapped to `skeen` subcommands.
nonisolated enum SkeenControl: String, CaseIterable, Identifiable, Sendable {
    case start
    case stop
    case restart
    case reload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Запустить"
        case .stop: return "Остановить"
        case .restart: return "Перезапустить"
        case .reload: return "Перезагрузить"
        }
    }

    var hint: String {
        switch self {
        case .start: return "Запускает Sing-box. Проверяет конфигурацию и не стартует повторно, если уже работает."
        case .stop: return "Останавливает Sing-box. Если процесс не найден — сообщает, что демон уже остановлен."
        case .restart: return "Останавливает и затем снова запускает Sing-box."
        case .reload: return "Перезагружает Sing-box (полный рестарт, не hot-reload) без изменения правил файрвола."
        }
    }

    var systemImage: String {
        switch self {
        case .start: return "play.fill"
        case .stop: return "stop.fill"
        case .restart: return "arrow.clockwise"
        case .reload: return "arrow.triangle.2.circlepath"
        }
    }

    /// `restart`/`reload` briefly interrupt traffic, so the UI confirms them first.
    var isDisruptive: Bool {
        switch self {
        case .start, .stop: return false
        case .restart, .reload: return true
        }
    }
}

/// Parsed output of `skeen version`.
nonisolated struct SkeenVersion: Equatable, Sendable {
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
nonisolated func parseSkeenVersion(_ raw: String) -> SkeenVersion {
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
