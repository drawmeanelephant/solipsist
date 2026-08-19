import Foundation

/// Stable identity for a source in the sidebar. Chrome and the store key on
/// this; providers do not mint a second id.
struct SourceID: Hashable, Codable, Sendable {
    let raw: UUID

    init(_ raw: UUID = UUID()) {
        self.raw = raw
    }
}

/// Kind discriminator for dispatch (play host, symbols). New kinds are added
/// with their provider; chrome only reads this, it does not switch on payload.
enum SourceKind: String, Codable, Sendable {
    case local
    case github

    var symbolName: String {
        switch self {
        case .local: return "folder"
        case .github: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .github: return "GitHub"
        }
    }
}

/// Sidebar identity. Kind-specific payload lives on the provider's type.
protocol PublicationSource: Identifiable, Sendable {
    var id: SourceID { get }
    var title: String { get }
    var kind: SourceKind { get }
}

/// Inventory item in the workspace store. Add a case when a new source
/// type lands; the sidebar still only reads `id` / `title` / `kind`.
enum SourceItem: Identifiable, Hashable, Sendable {
    case local(LocalSource)
    case github(GithubSource)

    var id: SourceID {
        switch self {
        case .local(let source): return source.id
        case .github(let source): return source.id
        }
    }

    var title: String {
        switch self {
        case .local(let source): return source.title
        case .github(let source): return source.title
        }
    }

    var kind: SourceKind {
        switch self {
        case .local: return .local
        case .github: return .github
        }
    }

    var symbolName: String { kind.symbolName }

    var isAvailable: Bool {
        switch self {
        case .local(let source): return source.isAvailable
        case .github(let source): return source.isAvailable
        }
    }

    var detailLine: String? {
        switch self {
        case .local(let source): return source.displayPath
        case .github(let source): return source.displayPath
        }
    }

    /// Current checkout branch for git-backed sources; nil otherwise.
    var branch: String? {
        switch self {
        case .local(let source): return source.branch
        case .github(let source): return source.branch
        }
    }
}
