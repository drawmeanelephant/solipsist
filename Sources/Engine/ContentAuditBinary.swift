import Foundation

/// Locates the `boris-content-audit` kit tool — poetry / parent-alignment
/// source auditing (LATER-1 / #165).
///
/// Search order:
///   1. `SOLIPSIST_CONTENT_AUDIT_BIN` environment override
///   2. `Resources/boris-content-audit` inside the running app bundle
///   3. A sibling of the located `boris` binary (kit/bin dirs ship both)
///   4. Common dev-checkout locations relative to the current directory
public enum ContentAuditBinary {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        borisBinary: URL? = nil
    ) -> URL? {
        let fm = FileManager.default

        func isExecutable(_ url: URL) -> Bool {
            fm.isExecutableFile(atPath: url.path)
        }

        if let custom = UserDefaults.standard.string(forKey: "customContentAuditBinaryPath"), !custom.isEmpty {
            let url = URL(fileURLWithPath: custom)
            if isExecutable(url) { return url }
        }

        if let override = environment["SOLIPSIST_CONTENT_AUDIT_BIN"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isExecutable(url) { return url }
        }

        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("boris-content-audit")
            if isExecutable(bundled) { return bundled }
        }

        if let borisBinary {
            let sibling = borisBinary.deletingLastPathComponent().appendingPathComponent("boris-content-audit")
            if isExecutable(sibling) { return sibling }
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let devCandidates = [
            "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris-content-audit",
            "../boris-agent-kit/bin/boris-content-audit",
            "../boris/tools/content-audit/zig-out/bin/boris-content-audit",
            "boris/tools/content-audit/zig-out/bin/boris-content-audit",
            "../boris/zig-out/bin/boris-content-audit",
        ]
        for relative in devCandidates {
            let url = cwd.appendingPathComponent(relative).standardizedFileURL
            if isExecutable(url) { return url }
        }

        return nil
    }
}
