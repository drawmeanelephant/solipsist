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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Completion.self, from: data)
    }
}
