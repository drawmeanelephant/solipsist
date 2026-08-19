import Foundation

/// Locates the `boris-source-rag` kit tool — packs project source files
/// for LLM upload (LATER-2 / #166). Distinct from the M7 `--rag` build
/// projection.
///
/// Search order:
///   1. `SOLIPSIST_SOURCE_RAG_BIN` environment override
///   2. `Resources/boris-source-rag` inside the running app bundle
///   3. A sibling of the located `boris` binary (kit/bin dirs ship both)
///   4. Common dev-checkout locations relative to the current directory
public enum SourceRagBinary {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        borisBinary: URL? = nil
    ) -> URL? {
        let fm = FileManager.default

        func isExecutable(_ url: URL) -> Bool {
            fm.isExecutableFile(atPath: url.path)
        }

        if let custom = UserDefaults.standard.string(forKey: "customSourceRagBinaryPath"), !custom.isEmpty {
            let url = URL(fileURLWithPath: custom)
            if isExecutable(url) { return url }
        }

        if let override = environment["SOLIPSIST_SOURCE_RAG_BIN"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isExecutable(url) { return url }
        }

        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("boris-source-rag")
            if isExecutable(bundled) { return bundled }
        }

        if let borisBinary {
            let sibling = borisBinary.deletingLastPathComponent().appendingPathComponent("boris-source-rag")
            if isExecutable(sibling) { return sibling }
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let devCandidates = [
            "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris-source-rag",
            "../boris-agent-kit/bin/boris-source-rag",
            "../boris/zig-out/bin/boris-source-rag",
            "boris/zig-out/bin/boris-source-rag",
            "zig-out/bin/boris-source-rag",
        ]
        for relative in devCandidates {
            let url = cwd.appendingPathComponent(relative).standardizedFileURL
            if isExecutable(url) { return url }
        }

        return nil
    }
}
