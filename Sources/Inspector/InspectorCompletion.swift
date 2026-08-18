import Foundation

/// Loads `<source>/.boris/completion.json` into the shared `Completion`
/// mirror. Missing or unreadable files degrade to `nil` (D8).
enum InspectorCompletion {
    static func url(in root: URL) -> URL {
        root
            .appendingPathComponent(".boris", isDirectory: true)
            .appendingPathComponent("completion.json", isDirectory: false)
    }

    static func load(from root: URL) -> Completion? {
        let fileURL = url(in: root)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Completion.self, from: data)
        {
            return decoded
        }
        let parentURL = url(in: root.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: parentURL.path),
           let data = try? Data(contentsOf: parentURL),
           let decoded = try? JSONDecoder().decode(Completion.self, from: data)
        {
            return decoded
        }
        return nil
    }
}
