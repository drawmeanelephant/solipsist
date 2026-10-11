import Foundation

/// Decoded `Resources/engine-provenance.json`, written at bundle time by
/// `scripts/embed-boris.sh`: which engine binaries the app shipped, what
/// they report, and which checkout revisions produced them.
///
/// Fully optional on decode (D8): a dev build without the file, or a newer
/// document shape, simply produces `nil` fields — never a gate.
public struct EngineProvenance: Codable, Sendable {
    public var format: String?
    public var schema_version: Int?
    public var generatedBy: String?
    public var boris: BorisProvenance?
    public var borisEditor: ToolProvenance?
    public var editorUI: ToolProvenance?
    public var oliver: ToolProvenance?
    public var companions: CompanionVersions?

    public struct BorisProvenance: Codable, Sendable {
        /// The `boris-build-info` document (`version`, `vcsRevision`).
        public var buildInfo: BorisBuildInfo?
        public var version: String?
        /// HEAD of the source checkout the binary was bundled from.
        public var repoCommit: String?
    }

    public struct ToolProvenance: Codable, Sendable {
        /// `<tool>/<release>` version line; empty for tools whose closed
        /// flag surface has no `--version` (boris-editor).
        public var version: String?
        public var repoCommit: String?
        public var sourcePath: String?
    }

    public struct CompanionVersions: Codable, Sendable {
        public var borisPackage: String?
        public var borisSourceRag: String?
        public var borisContentAudit: String?
    }

    /// The bundled provenance document, if this build was embedded by
    /// `scripts/embed-boris.sh` (`SKIP_EMBED_BORIS` builds have none).
    public static func load(bundle: Bundle = .main) -> EngineProvenance? {
        guard let url = bundle.url(forResource: "engine-provenance", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(EngineProvenance.self, from: data)
    }
}
