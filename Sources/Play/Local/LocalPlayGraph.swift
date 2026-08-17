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
                    depth: depth
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
}
