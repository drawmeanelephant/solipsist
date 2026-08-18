import Foundation

/// Codable snapshot of the source list. Bookmarks persist; `isAvailable`
/// is resolved at load and is not stored.
struct PersistedWorkspace: Codable, Equatable, Sendable {
    var sources: [LocalSource]
    var selected: SourceID?
}

enum WorkspacePersistence {
    static let defaultsKey = "solipsist.workspace.sources.v1"

    static func encode(_ payload: PersistedWorkspace) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data) throws -> PersistedWorkspace {
        try JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }
}
