import Foundation

/// Maps the page selected in play to the source file the compose window
/// edits, through the published graph contract (`graph.json`).
///
/// The selection noun carries only the page `id`; the file the author edits
/// lives in the graph as `GraphNode.sourcePath` (relative to the content
/// root, forward slashes — per `Models/BorisContracts.swift`). This type is
/// pure and testable; it never touches SwiftUI or the store.
enum ComposePageResolver {
    /// `workspaceRoot/.boris/graph.json` — the frozen graph play reads.
    static func graphURL(workspaceRoot: URL) -> URL {
        workspaceRoot
            .appendingPathComponent(".boris", isDirectory: true)
            .appendingPathComponent("graph.json")
    }

    /// The authored file for a graph node, relative to the content root
    /// (`content/` when the workspace root is a project root).
    static func fileURL(contentRoot: URL, sourcePath: String) -> URL {
        contentRoot.appendingPathComponent(sourcePath)
    }

    /// Finds the graph node for a page id.
    static func page(id: String, in graph: Graph) -> GraphNode? {
        graph.nodes.first { $0.id == id }
    }

    /// Decodes `graph.json` for a workspace root and finds the page.
    static func page(id: String, workspaceRoot: URL) throws -> GraphNode? {
        let data = try Data(contentsOf: graphURL(workspaceRoot: workspaceRoot))
        let graph = try JSONDecoder().decode(Graph.self, from: data)
        return page(id: id, in: graph)
    }
}
