import Foundation

/// An authenticated remote publication (M15 / #179): identity
/// (`owner/repo`, default branch, granted scopes) plus a local working
/// copy. Boris is a subprocess over a filesystem tree — every surface
/// operates on the working copy exactly as it does for a Local source.
///
/// The token is never here. It lives in the Keychain under
/// `tokenAccount`; only display-only granted scopes are carried.
struct GithubSource: PublicationSource, Hashable, Sendable, Codable {
    var id: SourceID
    /// "owner/repo" — the account header title.
    var title: String
    var owner: String
    var repository: String
    /// From the remote (`GET /repos/owner/repo`), never guessed.
    var defaultBranch: String
    /// Working-copy folder, LocalSource-style security-scoped bookmark.
    var bookmarkData: Data
    var displayPath: String
    /// What GitHub granted the token; display-only, never the token.
    var grantedScopes: [String]
    // Transient — resolved at load time, not persisted (LocalSource pattern).
    var isAvailable: Bool = true
    var branch: String? = nil
    var isSyncing: Bool = false
    var lastSyncError: String? = nil

    var kind: SourceKind { .github }

    enum CodingKeys: String, CodingKey {
        case id, title, owner, repository, defaultBranch, bookmarkData, displayPath, grantedScopes
    }

    /// Keychain account for this source's token: `github:<owner>/<repo>`.
    var tokenAccount: String {
        "github:\(owner)/\(repository)"
    }

    /// Repo page for "Open on GitHub".
    var remoteURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository)")!
    }

    func resolve() throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return (url, stale)
    }

    /// Folder the working-copy bookmark points at.
    func workspaceRoot() throws -> URL {
        try resolve().url.standardizedFileURL
    }
}
