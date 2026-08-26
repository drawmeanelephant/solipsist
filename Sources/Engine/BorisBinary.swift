import Foundation

/// Locates the `boris` engine binary.
///
/// Search order:
///   1. `SOLIPSIST_BORIS_BIN` environment override
///   2. `Resources/boris` inside the running app bundle (embedded by
///      scripts/embed-boris.sh at build time)
///   3. Common dev-checkout locations relative to the current directory
public enum BorisBinary {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fm = FileManager.default

        func isExecutable(_ url: URL) -> Bool {
            fm.isExecutableFile(atPath: url.path)
        }

        if let override = environment["SOLIPSIST_BORIS_BIN"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isExecutable(url) { return url }
        }

        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("boris")
            if isExecutable(bundled) { return bundled }
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let devCandidates = [
            "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris",
            "../boris-agent-kit/bin/boris",
            "boris/zig-out/bin/boris",
            "../boris/zig-out/bin/boris",
            "zig-out/bin/boris",
        ]
        for relative in devCandidates {
            let url = cwd.appendingPathComponent(relative).standardizedFileURL
            if isExecutable(url) { return url }
        }

        return nil
    }
}
