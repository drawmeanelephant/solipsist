import CoreGraphics
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
    /// The trunk this row belongs to (M13-2): the root `role == .trunk`
    /// whose `parent` chain this row reaches, or nil for non-trunk roots.
    /// Drives the trunk-mailbox filter; never the sidebar.
    let trunkID: String?
    /// #296: ingredient count for the Recipes mailbox row, from the
    /// node's `recipe` facet. nil on every other surface — the pages
    /// list never carries it.
    let ingredientCount: Int?

    init(
        id: String,
        title: String,
        status: String = "",
        role: PageRole = .trunk,
        depth: Int = 0,
        tags: [String] = [],
        sourcePath: String = "",
        trunkID: String? = nil,
        ingredientCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.role = role
        self.depth = depth
        self.tags = tags
        self.sourcePath = sourcePath
        self.trunkID = trunkID
        self.ingredientCount = ingredientCount
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
        func emit(_ node: GraphNode, depth: Int, trunkID: String?) {
            rows.append(
                PlayPage(
                    id: node.id,
                    title: node.title,
                    status: node.status ?? "",
                    role: node.role,
                    depth: depth,
                    tags: node.tags ?? [],
                    sourcePath: node.sourcePath,
                    trunkID: trunkID
                )
            )
            for child in children[node.id] ?? [] {
                emit(child, depth: depth + 1, trunkID: trunkID)
            }
        }

        // Trunks first so a mixed-index corpus still reads as a publication.
        for node in roots where node.role == .trunk {
            emit(node, depth: 0, trunkID: node.id)
        }
        for node in roots where node.role != .trunk {
            emit(node, depth: 0, trunkID: nil)
        }
        return rows
    }

    /// The trunk mailbox's letter list (M13-2): the trunk row plus every
    /// descendant whose `parent` chain reaches it. Empty when the id is
    /// missing from the current graph — never a fall-through to all pages.
    static func pages(in pages: [PlayPage], trunkID: String) -> [PlayPage] {
        pages.filter { $0.trunkID == trunkID }
    }

    /// One-pass sidebar snapshot (#275): pages, trunks, and per-trunk
    /// counts derived together so a render never walks the graph twice
    /// and never recounts O(trunks × pages) per body evaluation.
    struct SidebarSnapshot: Equatable, Sendable {
        var allPages: [PlayPage] = []
        var trunks: [PlayPage] = []
        /// trunk id → number of pages inside that trunk.
        var countsByTrunk: [String: Int] = [:]

        var pageCount: Int { allPages.count }
        static let empty = SidebarSnapshot()
    }

    static func snapshot(from graph: Graph) -> SidebarSnapshot {
        let allPages = pages(from: graph)
        var counts: [String: Int] = [:]
        for page in allPages {
            if let trunkID = page.trunkID {
                counts[trunkID, default: 0] += 1
            }
        }
        return SidebarSnapshot(
            allPages: allPages,
            trunks: allPages.filter { $0.depth == 0 && $0.role == .trunk },
            countsByTrunk: counts
        )
    }

    /// The sidebar's folder rows under Pages (M13-1): roots whose role
    /// is `trunk`. Satellites and non-trunk roots are not folders.
    static func trunks(from graph: Graph) -> [PlayPage] {
        pages(from: graph).filter { $0.depth == 0 && $0.role == .trunk }
    }

    /// #296: the Recipes mailbox list — every graph node carrying a
    /// non-nil `recipe` facet, in graph order, with its ingredient
    /// count on the row. An empty-ingredient recipe still lists (the
    /// row shows "0 ingredients"); a corpus whose graph is not built
    /// yet lists nothing (never synthesized). Keys off
    /// `GraphNode.recipe` presence only — never `profile.input_format`
    /// (a mixed corpus is valid).
    static func recipes(from pages: [PlayPage], graph: Graph?) -> [PlayPage] {
        guard let graph else { return [] }
        var recipeByPage: [String: CookRecipe] = [:]
        for node in graph.nodes where node.recipe != nil {
            recipeByPage[node.id] = node.recipe
        }
        guard !recipeByPage.isEmpty else { return [] }
        return pages.compactMap { page in
            guard let recipe = recipeByPage[page.id] else { return nil }
            return PlayPage(
                id: page.id,
                title: page.title,
                status: page.status,
                role: page.role,
                depth: page.depth,
                tags: page.tags,
                sourcePath: page.sourcePath,
                trunkID: page.trunkID,
                ingredientCount: recipe.ingredients.count
            )
        }
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

/// #297 — width-adaptive Pages split geometry. Pure math so
/// ContractTests can pin the branch + clamp rules without a window:
/// the view (`LocalPlay.pagesSplit`) only turns these numbers into
/// frames. Stacked bounds are the M10 values; wide bounds keep the
/// list ≥ 220 and the letter ≥ 360.
enum PagesSplitGeometry {
    /// Width at which the split cuts from stacked to side-by-side.
    static let wideBreakpoint: CGFloat = 720
    static let minTopHeight: CGFloat = 90
    static let minLetterHeight: CGFloat = 120
    static let defaultTopHeight: CGFloat = 200
    static let minListWidth: CGFloat = 220
    static let minLetterWidth: CGFloat = 360
    static let defaultLeftWidth: CGFloat = 280

    /// `true` at or above the breakpoint — the wide cut does not
    /// oscillate at exactly 720.
    static func isWide(width: CGFloat) -> Bool {
        width >= wideBreakpoint
    }

    /// Stacked-mode list height: M10 clamp, ≥ 90 and leaving the letter
    /// ≥ 120 of `availableHeight`.
    static func clampedTopHeight(_ raw: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(max(raw, minTopHeight), max(availableHeight - minLetterHeight, minTopHeight))
    }

    /// Wide-mode list width: ≥ 220 and leaving the letter ≥ 360 of
    /// `totalWidth`. When the window cannot honor both (between the
    /// breakpoint and 220 + 360), the letter floor wins and the list
    /// clamps to whatever remains, never below 220.
    static func clampedLeftWidth(_ raw: CGFloat, totalWidth: CGFloat) -> CGFloat {
        min(max(raw, minListWidth), max(totalWidth - minLetterWidth, minListWidth))
    }
}
