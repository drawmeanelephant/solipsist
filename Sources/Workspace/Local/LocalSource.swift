import Foundation

/// A folder on disk, remembered via an app-scoped security-scoped bookmark.
/// Local play owns the work surface for this source; this type is only the
/// sidebar identity plus the bookmark that keeps sandbox access alive.
struct LocalSource: PublicationSource, Hashable, Sendable, Codable {
    var id: SourceID
    var title: String
    var bookmarkData: Data
    var displayPath: String
    /// Transient: resolved at load time. Not persisted.
    var isAvailable: Bool = true

    var kind: SourceKind { .local }

    enum CodingKeys: String, CodingKey {
        case id, title, bookmarkData, displayPath
    }

    static func make(from url: URL) throws -> LocalSource {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return LocalSource(
            id: SourceID(),
            title: url.lastPathComponent,
            bookmarkData: data,
            displayPath: url.standardizedFileURL.path,
            isAvailable: true
        )
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

    func refreshedBookmark() throws -> LocalSource {
        let resolved = try resolve()
        var next = try LocalSource.make(from: resolved.url)
        next.id = id
        return next
    }

    /// Folder the bookmark points at.
    func workspaceRoot() throws -> URL {
        try resolve().url.standardizedFileURL
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

    static func isProjectRoot(_ root: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let content = root.appendingPathComponent("content", isDirectory: true)
        let profile = root.appendingPathComponent("boris.json")
        let hasContent = fm.fileExists(atPath: content.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        return hasContent && fm.fileExists(atPath: profile.path)
    }
}
