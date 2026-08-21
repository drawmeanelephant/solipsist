import Foundation

/// Resolves the theme stylesheet the compose preview applies (#230): the
/// canonical HTML target's theme from the publication profile, read from
/// the workspace's `themes/` directory. The CSS is collected verbatim —
/// Boris owns theme semantics; we never rewrite it. When nothing resolves
/// the preview falls back to `ComposePreviewDocument.fallbackCSS`.
enum ComposeThemeCSS {
    /// The theme path whose CSS styles the preview: the first public
    /// target with a non-empty `theme`, else the first target with one.
    /// Mirrors the Preview companion's "first canonical target" rule.
    static func preferredThemePath(in targets: [PublicationTarget]?) -> String? {
        guard let targets, !targets.isEmpty else { return nil }
        var firstTheme: String?
        for target in targets {
            guard let theme = target.theme, !theme.isEmpty else { continue }
            if target.public == true { return theme }
            if firstTheme == nil { firstTheme = theme }
        }
        return firstTheme
    }

    /// Concatenated `.css` content under `<workspaceRoot>/<themePath>`
    /// (recursive, path-sorted so the order is deterministic), or nil when
    /// the directory is missing / unreadable / has no stylesheets.
    static func collect(workspaceRoot: URL, themePath: String) -> String? {
        let themeDir = workspaceRoot.appendingPathComponent(themePath, isDirectory: true)
        let files = cssFiles(in: themeDir)
        guard !files.isEmpty else { return nil }
        let chunks = files.compactMap { url -> String? in
            guard let css = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return css
        }
        guard !chunks.isEmpty else { return nil }
        return chunks.joined(separator: "\n\n")
    }

    /// Convenience over the profile: preferred theme + collection.
    static func collect(workspaceRoot: URL, targets: [PublicationTarget]?) -> String? {
        guard let themePath = preferredThemePath(in: targets) else { return nil }
        return collect(workspaceRoot: workspaceRoot, themePath: themePath)
    }

    private static func cssFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return (enumerator?.allObjects as? [URL])?
            .filter { $0.pathExtension.lowercased() == "css" }
            .sorted { $0.path < $1.path } ?? []
    }
}
