import Foundation

/// Loads `<source>/.boris/graph.json` into the shared `Graph` mirror.
/// Missing or unreadable files degrade to `nil` (D8).
public enum InspectorGraph {
    public static func url(in root: URL) -> URL {
        root
            .appendingPathComponent(".boris", isDirectory: true)
            .appendingPathComponent("graph.json", isDirectory: false)
    }

    public static func load(from root: URL) -> Graph? {
        let fileURL = url(in: root)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Graph.self, from: data)
        {
            return decoded
        }
        let parentURL = url(in: root.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: parentURL.path),
           let data = try? Data(contentsOf: parentURL),
           let decoded = try? JSONDecoder().decode(Graph.self, from: data)
        {
            return decoded
        }
        return nil
    }
}
