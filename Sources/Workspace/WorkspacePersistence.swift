import Foundation

/// Codable snapshot of the source list. Bookmarks persist; `isAvailable`
/// is resolved at load and is not stored.
struct PersistedWorkspace: Codable, Equatable, Sendable {
    var sources: [LocalSource]
    var selected: SourceID?
    /// Raw mailbox token. Missing key decodes as nil; do not canonicalize.
    var mailbox: String? = nil
    /// GitHub sources (M15): remote identity + working-copy bookmark.
    /// The token is never here — Keychain only.
    var github: [GithubSource] = []

    init(
        sources: [LocalSource],
        selected: SourceID?,
        mailbox: String? = nil,
        github: [GithubSource] = []
    ) {
        self.sources = sources
        self.selected = selected
        self.mailbox = mailbox
        self.github = github
    }

    /// Synthesized encode; decode tolerates V1 payloads that predate
    /// `github` (missing key → empty, never a decode failure).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decode([LocalSource].self, forKey: .sources)
        selected = try container.decodeIfPresent(SourceID.self, forKey: .selected)
        mailbox = try container.decodeIfPresent(String.self, forKey: .mailbox)
        github = try container.decodeIfPresent([GithubSource].self, forKey: .github) ?? []
    }
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
