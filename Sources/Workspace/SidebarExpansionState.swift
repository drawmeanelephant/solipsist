import Foundation

/// #274: the sidebar's tree shape — which sources are collapsed and whether
/// each source's Pages disclosure is open. Machine state (D2): one
/// UserDefaults key, JSON payload, injected defaults for tests.
///
/// Pure rules + codec live here so ContractTests can pin the round-trip;
/// `WorkspaceStore` (deliberately not in the test target) delegates to this.
enum SidebarExpansionState {
    static let defaultsKey = "sidebarExpansion"

    struct Payload: Codable, Equatable, Sendable {
        /// Source ids whose Section is collapsed. Absent = expanded.
        var collapsedSources: [String] = []
        /// Source id → Pages-disclosure openness. Absent = expanded (the
        /// shipping default).
        var pagesExpanded: [String: Bool] = [:]
    }

    // MARK: - Codec

    static func encode(_ payload: Payload) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data) -> Payload? {
        try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Reads the persisted shape; a missing or undecodable payload means
    /// "everything expanded" — never an error surface.
    static func load(defaults: UserDefaults) -> Payload {
        guard let data = defaults.data(forKey: defaultsKey) else { return Payload() }
        return decode(data) ?? Payload()
    }

    static func save(_ payload: Payload, defaults: UserDefaults) {
        guard let data = try? encode(payload) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    // MARK: - Rules

    static func isCollapsed(_ payload: Payload, id: SourceID) -> Bool {
        payload.collapsedSources.contains(id.raw.uuidString)
    }

    static func collapsing(_ payload: Payload, id: SourceID) -> Payload {
        var next = payload
        let key = id.raw.uuidString
        if !next.collapsedSources.contains(key) {
            next.collapsedSources.append(key)
        }
        return next
    }

    static func expanding(_ payload: Payload, id: SourceID) -> Payload {
        var next = payload
        next.collapsedSources.removeAll { $0 == id.raw.uuidString }
        return next
    }

    static func pagesExpanded(_ payload: Payload, id: SourceID) -> Bool {
        payload.pagesExpanded[id.raw.uuidString] ?? true
    }

    static func settingPages(
        _ payload: Payload,
        id: SourceID,
        expanded: Bool
    ) -> Payload {
        var next = payload
        next.pagesExpanded[id.raw.uuidString] = expanded
        return next
    }
}
