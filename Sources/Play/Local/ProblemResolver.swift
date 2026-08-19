import Foundation

enum ProblemResolution: Equatable, Sendable {
    case page(id: String, title: String)
    case revealFile(url: URL)
}

enum ProblemResolver {
    static func resolve(
        path: String,
        source: (any PlayFolderSource)?,
        graph: Graph?
    ) -> ProblemResolution? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let graph, let node = findMatchingNode(in: graph, forPath: trimmed) {
            return .page(id: node.id, title: node.title)
        }

        if let url = resolveFileURL(path: trimmed, source: source) {
            return .revealFile(url: url)
        }

        return nil
    }

    static func findMatchingNode(in graph: Graph, forPath path: String) -> GraphNode? {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/."))
        return graph.nodes.first { node in
            if node.sourcePath == path || node.sourcePath == normalized {
                return true
            }
            let nodeNorm = node.sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/."))
            if nodeNorm == normalized {
                return true
            }
            if path.hasSuffix("/" + node.sourcePath) || path.hasSuffix("/" + nodeNorm) {
                return true
            }
            return false
        }
    }

    static func resolveFileURL(path: String, source: (any PlayFolderSource)?) -> URL? {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let source else { return nil }
        if let contentRoot = try? source.contentRoot() {
            return contentRoot.appendingPathComponent(path)
        }
        if let root = try? source.resolve().url {
            return root.appendingPathComponent(path)
        }
        return nil
    }
}
