import Foundation

/// Locates the `boris-package` companion binary — builds deterministic IR (+
/// optional RAG) review archives (`packages/boris-package.tar`).
///
/// Search order:
///   1. `SOLIPSIST_PACKAGE_BIN` environment override
///   2. `Resources/boris-package` inside the running app bundle
///   3. A sibling of the located `boris` binary (kit/bin dirs ship both)
///   4. Common dev-checkout locations relative to the current directory
public enum PackageBinary {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        borisBinary: URL? = nil
    ) -> URL? {
        let fileManager = FileManager.default

        func isExecutable(_ url: URL) -> Bool {
            fileManager.isExecutableFile(atPath: url.path)
        }

        if let override = environment["SOLIPSIST_PACKAGE_BIN"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isExecutable(url) { return url }
        }

        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("boris-package")
            if isExecutable(bundled) { return bundled }
        }

        if let borisBinary {
            let sibling = borisBinary.deletingLastPathComponent().appendingPathComponent("boris-package")
            if isExecutable(sibling) { return sibling }
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let devCandidates = [
            "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris-package",
            "../boris-agent-kit/bin/boris-package",
            "../boris/zig-out/bin/boris-package",
            "boris/zig-out/bin/boris-package",
            "zig-out/bin/boris-package",
        ]
        for relative in devCandidates {
            let url = cwd.appendingPathComponent(relative).standardizedFileURL
            if isExecutable(url) { return url }
        }

        return nil
    }
}
