import Foundation

/// One row in the local play list. Flattened from `Graph.nodes` so the
/// view can stay a system `List` — trunks first, satellites indented
/// under their `parent`.
struct PlayPage: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let status: String
    let role: PageRole
    let depth: Int
    let tags: [String]
    let sourcePath: String

    init(
        id: String,
        title: String,
        status: String = "",
        role: PageRole = .trunk,
        depth: Int = 0,
        tags: [String] = [],
        sourcePath: String = ""
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.role = role
        self.depth = depth
        self.tags = tags
        self.sourcePath = sourcePath
    }
}

enum LocalPlayGraph {
    /// Walk `graph.nodes` by `parent`. Does not consult `edges` / `nav`.
    static func pages(from graph: Graph) -> [PlayPage] {
        let known = Set(graph.nodes.map(\.id))
        var children: [String: [GraphNode]] = [:]
        var roots: [GraphNode] = []

        for node in graph.nodes.sorted(by: { $0.index < $1.index }) {
            if let parent = node.parent, known.contains(parent) {
                children[parent, default: []].append(node)
            } else {
                roots.append(node)
            }
        }

        var rows: [PlayPage] = []
        func emit(_ node: GraphNode, depth: Int) {
            rows.append(
                PlayPage(
                    id: node.id,
                    title: node.title,
                    status: node.status ?? "",
                    role: node.role,
                    depth: depth,
                    tags: node.tags ?? [],
                    sourcePath: node.sourcePath
                )
            )
            for child in children[node.id] ?? [] {
                emit(child, depth: depth + 1)
            }
        }

        // Trunks first so a mixed-index corpus still reads as a publication.
        for node in roots where node.role == .trunk {
            emit(node, depth: 0)
        }
        for node in roots where node.role != .trunk {
            emit(node, depth: 0)
        }
        return rows
    }

    /// Filter pages by query string matching title, id, tag, or status.
    /// Supports prefixes: `tag:`, `status:`, `id:`, `title:`.
    static func filter(pages: [PlayPage], query: String) -> [PlayPage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return pages }
        let tokens = trimmed.split(separator: " ").map { String($0) }
        return pages.filter { page in
            tokens.allSatisfy { token in
                pageMatches(page: page, token: token)
            }
        }
    }

    private static func pageMatches(page: PlayPage, token: String) -> Bool {
        let lower = token.lowercased()
        if lower.hasPrefix("tag:") {
            let val = String(lower.dropFirst(4))
            return page.tags.contains { $0.lowercased().contains(val) }
        }
        if lower.hasPrefix("status:") {
            let val = String(lower.dropFirst(7))
            return page.status.lowercased().contains(val)
        }
        if lower.hasPrefix("id:") {
            let val = String(lower.dropFirst(3))
            return page.id.lowercased().contains(val)
        }
        if lower.hasPrefix("title:") {
            let val = String(lower.dropFirst(6))
            return page.title.lowercased().contains(val)
        }
        return page.title.localizedCaseInsensitiveContains(token)
            || page.id.localizedCaseInsensitiveContains(token)
            || page.status.localizedCaseInsensitiveContains(token)
            || page.tags.contains { $0.localizedCaseInsensitiveContains(token) }
    }

    /// Resolves a diagnostic source path (e.g. "guides/getting-started.md" or "index.md")
    /// against known pages to find the corresponding page.
    static func resolvePage(forSourcePath path: String, in pages: [PlayPage]) -> PlayPage? {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        // 1. Exact match on sourcePath
        if let match = pages.first(where: { $0.sourcePath == normalized }) {
            return match
        }

        // 2. Exact match on id
        if let match = pages.first(where: { $0.id == normalized }) {
            return match
        }

        // 3. Match without path extension
        let withoutExt = (normalized as NSString).deletingPathExtension
        if let match = pages.first(where: { $0.id == withoutExt || $0.sourcePath == withoutExt }) {
            return match
        }

        // 4. Suffix match
        if let match = pages.first(where: {
            $0.sourcePath.hasSuffix("/" + normalized) || normalized.hasSuffix("/" + $0.sourcePath)
        }) {
            return match
        }

        return nil
    }
}
