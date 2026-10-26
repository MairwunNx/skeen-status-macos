import ComposableArchitecture
import Foundation

/// A group of outbounds from the Clash API, such as skeen's `proxy` selector.
struct OutboundGroup: Equatable, Identifiable, Sendable {
    var name: String
    /// `Selector`, `URLTest`, or `Fallback`.
    var type: String
    var now: String
    var options: [String]

    var id: String { name }

    /// A selector follows a choice made by hand; the others pick by themselves.
    var isSelectable: Bool { type.caseInsensitiveCompare("Selector") == .orderedSame }
}

/// What sing-box reports about itself through the Clash API.
struct SingBoxRuntime: Equatable, Sendable {
    var version: String
    var mode: String
    var modes: [String]
    var groups: [OutboundGroup]
    var connections: Int
    var downloadTotal: Int64
    var uploadTotal: Int64
    var memoryBytes: Int64?
}

/// The latest Clash API reading.
struct SingBoxSnapshot: Equatable, Sendable {
    var runtime: SingBoxRuntime?
    var lastError: String?
    var lastUpdate: Date?
}

extension SharedKey where Self == InMemoryKey<SingBoxSnapshot>.Default {
    static var singBoxSnapshot: Self {
        Self[.inMemory("singBoxSnapshot"), default: SingBoxSnapshot()]
    }
}

/// Russian name of a Clash mode; unknown modes keep their own name.
func modeTitle(_ mode: String) -> String {
    switch mode.lowercased() {
    case "rule": return "По правилам"
    case "global": return "Всё через прокси"
    case "direct": return "Всё напрямую"
    default: return mode
    }
}

/// The groups worth showing, selectors first. `GLOBAL` is Clash's own
/// switch for the global mode, so it stays hidden.
func outboundGroups(from proxies: [String: ClashProxy]) -> [OutboundGroup] {
    let groupTypes: Set<String> = ["selector", "urltest", "fallback"]
    return proxies.values
        .filter { groupTypes.contains($0.type.lowercased()) && $0.name != "GLOBAL" }
        .map { OutboundGroup(name: $0.name, type: $0.type, now: $0.now ?? "", options: $0.all ?? []) }
        .sorted { lhs, rhs in
            if lhs.isSelectable != rhs.isSelectable { return lhs.isSelectable }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
}
