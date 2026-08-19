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

/// The folder contract every play surface operates on (M15): both Local
/// and GitHub sources resolve to a folder boris can read, so the panes
/// (Pages/Outputs/Publish/Plan/Activity) are identical for both — the
/// working copy IS the tree. The github payload only adds identity on
/// top of this.
protocol PlayFolderSource: PublicationSource {
    var displayPath: String { get }
    var isAvailable: Bool { get }
    /// Current checkout branch when the folder has `.git`; nil otherwise.
    var branch: String? { get }
    func resolve() throws -> (url: URL, stale: Bool)
    func workspaceRoot() throws -> URL
    /// `content/` when this looks like a project root (`content/` + `boris.json`).
    func contentRoot() throws -> URL
    func profileURL() -> URL?
    func artifactDirectory(named name: String) throws -> URL
}

extension PlayFolderSource {
    /// True when `root` looks like a project root (`content/` + `boris.json`).
    static func isProjectRoot(_ root: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let content = root.appendingPathComponent("content", isDirectory: true)
        let profile = root.appendingPathComponent("boris.json")
        let hasContent = fm.fileExists(atPath: content.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        return hasContent && fm.fileExists(atPath: profile.path)
    }

    /// `content/` when this looks like a project root (`content/` + `boris.json`).
    func contentRoot() throws -> URL {
        let root = try workspaceRoot()
        return Self.isProjectRoot(root)
            ? root.appendingPathComponent("content", isDirectory: true)
            : root
    }

    func profileURL() -> URL? {
        guard let root = try? workspaceRoot() else { return nil }
        let url = root.appendingPathComponent("boris.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func artifactDirectory(named name: String) throws -> URL {
        try workspaceRoot().appendingPathComponent(name, isDirectory: true)
    }
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
