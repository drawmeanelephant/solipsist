import Foundation

/// Pure CLI-argument derivation from a workspace's `boris.json` profile.
///
/// Keeps `validate`, `validate --watch`, `watch --serve`, `build`, `check`,
/// and `impact` aligned with declared `input_format`, theme, layout rules,
/// static directories, and output profiles (boris 0.9+ starter archetypes
/// ship themes other than `themes/boris`, and `validate --watch` / profiles
/// with `editions` cannot take `--profile` directly).
public enum BorisProfileArgs {
    public static func loadProfile(in workspaceRoot: URL) -> PublicationProfile? {
        let url = workspaceRoot.appendingPathComponent("boris.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(PublicationProfile.self, from: data)
    }

    public static func inputFormatFlags(for inputFormat: String?) -> [String] {
        switch inputFormat?.lowercased() {
        case "textile":
            return ["--textile"]
        case "cook", "cooklang":
            return ["--cooklang"]
        default:
            return []
        }
    }

    public static func primaryTarget(in profile: PublicationProfile?) -> PublicationTarget? {
        guard let targets = profile?.targets, !targets.isEmpty else { return nil }
        return targets.first(where: { $0.public == true }) ?? targets.first
    }

    public static func normalizedHTMLProfile(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "_", with: "-")
    }

    /// CLI flags for single-target invocations (`validate`, `validate --watch`,
    /// `watch --serve`, `buildHTML`) whose target name is Boris's `"default"`.
    public static func defaultTargetFlags(for profile: PublicationProfile?) -> [String] {
        guard let profile else { return [] }
        var args = inputFormatFlags(for: profile.input_format)
        guard let target = primaryTarget(in: profile) else { return args }
        if let theme = target.theme, !theme.isEmpty {
            args.append(contentsOf: ["--theme", theme])
        }
        if let layout = target.layout, !layout.isEmpty {
            args.append(contentsOf: ["--html-layout", layout])
        }
        if let rules = target.layout_rules {
            for rule in rules {
                args.append(contentsOf: ["--layout-rule", "default", rule.selector, rule.layout])
            }
        }
        if let staticDir = target.static?.dir, !staticDir.isEmpty {
            args.append(contentsOf: ["--static-dir", staticDir])
        }
        if let htmlProfile = normalizedHTMLProfile(target.html_profile) {
            args.append(contentsOf: ["--target-profile", "default=\(htmlProfile)"])
        }
        return args
    }

    /// Avoid `TargetOutputCollision` (exit 2) when validating a flat content
    /// folder (`workingDirectory == contentRoot`, no `content/` subdirectory):
    /// Boris's default `dist` output resolves under `cwd`, which nests inside
    /// `--input` when they are the same directory. Running from the parent
    /// directory keeps `dist` outside `--input` without writing anything.
    public static func validationWorkingDirectory(
        contentRoot: URL,
        workingDirectory: URL
    ) -> URL {
        let stdContent = contentRoot.standardizedFileURL
        let stdWork = workingDirectory.standardizedFileURL
        if stdWork == stdContent, stdContent.path != "/" {
            return stdContent.deletingLastPathComponent()
        }
        return workingDirectory
    }

    /// Relative `--input` path when `contentRoot` lies inside `workingDirectory`
    /// (required by Boris standalone `--llms-path` and `--rss-path`, which
    /// reject absolute `--input` paths with `AbsolutePath`).
    public static func inputArgument(
        contentRoot: URL,
        relativeTo workingDirectory: URL
    ) -> String {
        let stdRoot = contentRoot.standardizedFileURL.path
        let stdWork = workingDirectory.standardizedFileURL.path
        if stdRoot == stdWork {
            return "."
        }
        let prefix = stdWork.hasSuffix("/") ? stdWork : stdWork + "/"
        if stdRoot.hasPrefix(prefix) {
            return String(stdRoot.dropFirst(prefix.count))
        }
        return contentRoot.path
    }
}
