import Foundation

/// Locates the `oliver` CLI binary — the rendering engine behind Boris,
/// used by the compose preview (`oliver render --from …`).
///
/// Search order:
///   1. `SOLIPSIST_OLIVER_BIN` environment override
///   2. `Resources/oliver` inside the running app bundle
///   3. A sibling of the located `boris` binary (kit/bin dirs ship both)
///   4. Common dev-checkout locations relative to the current directory
public enum OliverBinary {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        borisBinary: URL? = nil
    ) -> URL? {
        let fm = FileManager.default

        func isExecutable(_ url: URL) -> Bool {
            fm.isExecutableFile(atPath: url.path)
        }

        if let custom = UserDefaults.standard.string(forKey: "customOliverBinaryPath"), !custom.isEmpty {
            let url = URL(fileURLWithPath: custom)
            if isExecutable(url) { return url }
        }

        if let override = environment["SOLIPSIST_OLIVER_BIN"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isExecutable(url) { return url }
        }

        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("oliver")
            if isExecutable(bundled) { return bundled }
        }

        if let borisBinary {
            let sibling = borisBinary.deletingLastPathComponent().appendingPathComponent("oliver")
            if isExecutable(sibling) { return sibling }
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let devCandidates = [
            "SUPPORT-NOT-FOR-GITHUB/oliver/zig-out/bin/oliver",
            "../oliver/zig-out/bin/oliver",
            "oliver/zig-out/bin/oliver",
            "zig-out/bin/oliver",
        ]
        for relative in devCandidates {
            let url = cwd.appendingPathComponent(relative).standardizedFileURL
            if isExecutable(url) { return url }
        }

        return nil
    }
}
