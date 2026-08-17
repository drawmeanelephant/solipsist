import Foundation

/// Codable mirrors of the Boris JSON output contracts (IR schemaVersion 0.2.0).
///
/// These shapes are normative in the Boris repo:
///   boris/docs/contracts/ir-schema.md      (manifest / graph / build-report)
///   boris/docs/contracts/diagnostics.md    (diagnostic objects + codes)
///   boris/docs/contracts/                  (documentation-intelligence reports)
///
/// All structs are `Sendable` so they can cross actor boundaries freely.
/// Decode defensively: fields the contracts mark nullable are `Optional`, and
/// consumers must branch on `schemaVersion` before trusting a shape.
/// If a required field is missing, decoding fails loudly — never guess.

// MARK: - Diagnostics

/// A single structured diagnostic (boris/docs/contracts/diagnostics.md).
/// Field order is normative: severity, code, message, remediation,
/// sourcePath, line, column, id.
public struct Diagnostic: Codable, Sendable {
    public var severity: String
    public var code: String
    public var message: String
    /// Author guidance; may be the empty string.
    public var remediation: String
    /// Content-relative path, or null when not applicable.
    public var sourcePath: String?
    /// 1-based line in the source file, or null.
    public var line: Int?
    /// 1-based column (byte offset within line), or null.
    public var column: Int?
    /// Related entity id when known, or null.
    public var id: String?

    public var isError: Bool { severity == "error" }
}

// MARK: - Build report

/// `build-report.json` — written on every compile attempt, success or failure.
/// On content failure (`ok: false`) manifest.json / graph.json are NOT
/// published and any prior copies are removed.
public struct BuildReport: Codable, Sendable {
    public var schemaVersion: String
    /// Present on success paths (e.g. "boris/0.8.0").
    public var compiler: String?
    public var ok: Bool
    public var contentRoot: String?
    public var outDir: String?
    public var pageCount: Int?
    public var errorCount: Int?
    public var diagnostics: [Diagnostic]

    public var errors: [Diagnostic] { diagnostics.filter(\.isError) }
}

// MARK: - Manifest

/// `manifest.json` — required page summaries, sorted by id.
public struct Manifest: Codable, Sendable {
    public var schemaVersion: String
    public var compiler: String?
    public var contentRoot: String?
    public var pageCount: Int?
    public var pages: [PageSummary]
}

public enum PageRole: String, Codable, Sendable {
    case trunk
    case satellite
}

/// Page summary as published in manifest.json.
public struct PageSummary: Codable, Sendable {
    public var index: Int
    public var id: String
    /// Path relative to the content root (forward slashes).
    public var sourcePath: String
    public var role: PageRole
    /// Trunk id for satellites; null for trunks.
    public var parent: String?
    public var title: String
    public var status: String

    public var isTrunk: Bool { role == .trunk }
}

// MARK: - Graph

/// `graph.json` — frozen nodes + typed dependency edges + reverse index + nav.
/// Only published on success (`ok: true`, `frozen: true`).
public struct Graph: Codable, Sendable {
    public var schemaVersion: String
    public var frozen: Bool
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]
    public var reverseIndex: [ReverseIndexEntry]
    public var nav: [NavEntry]
}

public struct GraphNode: Codable, Sendable {
    public var index: Int
    public var id: String
    public var sourcePath: String
    public var role: PageRole
    public var parent: String?
    public var parentIndex: Int?
    public var title: String
    public var status: String
    public var tags: [String]?
    /// Byte offset of the body start in the source file (IR has no bodies).
    public var bodyOffset: Int?
}

public struct GraphEndpoint: Codable, Sendable {
    /// "page" or "source".
    public var type: String
    public var value: String
}

public struct GraphEdge: Codable, Sendable {
    public var from: GraphEndpoint
    public var to: GraphEndpoint
    /// "parent", "include", or "reference".
    public var kind: String
}

public struct ReverseIndexEntry: Codable, Sendable {
    public var target: GraphEndpoint
    /// Indices into `Graph.edges`.
    public var incomingEdges: [Int]
}

public struct NavEntry: Codable, Sendable {
    public var index: Int
    public var id: String
    /// Node indices from the page up to its root trunk.
    public var breadcrumb: [Int]
    public var children: [Int]
    public var siblings: [Int]
}

// MARK: - Documentation intelligence (check / impact)

/// `boris check` / `boris impact` analysis report (`--format json`).
public struct AnalysisReport: Codable, Sendable {
    public var format: String
    public var schemaVersion: String
    public var compiler: String?
    public var input: String?
    public var summary: AnalysisSummary
    public var pages: [AnalysisPage]
    public var sources: [String]
    public var findings: [AnalysisFinding]
    /// Populated by `impact`; null for `check`.
    public var impact: [AnalysisImpact]?
}

public struct AnalysisSummary: Codable, Sendable {
    public var pages: Int
    public var roots: Int
    public var satellites: Int
    public var sourceEndpoints: Int
    public var unreferencedPages: Int
    public var hotspots: Int
}

public struct AnalysisPage: Codable, Sendable {
    public var id: String
    public var parent: String?
}

public struct AnalysisFinding: Codable, Sendable {
    public var code: String
    public var type: String
    public var value: String
    public var count: Int
}

public struct AnalysisImpact: Codable, Sendable {
    public var type: String
    public var value: String
}
