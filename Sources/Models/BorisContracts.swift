import Foundation

/// Codable mirrors of the Boris JSON output contracts (IR schemaVersion
/// 0.2.0–0.4.0; the app's happy fixtures carry 0.3.0).
///
/// These shapes are normative in the Boris repo:
///   boris/docs/contracts/ir-schema.md      (manifest / graph / build-report)
///   boris/docs/contracts/diagnostics.md    (diagnostic objects + codes)
///   boris/docs/contracts/                  (documentation-intelligence reports)
///   boris/docs/contracts/publication-profile.md
///   boris/docs/contracts/schemas/          (completion, HTML report, profile)
///
/// All structs are `Sendable` so they can cross actor boundaries freely.
/// Decode defensively: fields the contracts mark nullable are `Optional`, and
/// consumers must branch on `schemaVersion` / `schema_version` before trusting
/// a shape (D8: unknown/newer degrades, never crashes).
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
    /// IR artifacts may name the compiler as `compiler`, `compiler_id`, or
    /// `compilerId` (A3). Accept all three; do not unify them.
    public var compiler: String?
    public var compiler_id: String?
    public var compilerId: String?
    public var ok: Bool
    public var contentRoot: String?
    public var outDir: String?
    public var pageCount: Int?
    public var errorCount: Int?
    public var diagnostics: [Diagnostic]

    public var errors: [Diagnostic] { diagnostics.filter(\.isError) }
}

// MARK: - HTML build report (`html-build-report-0.1.0`)

/// Written by `boris build --report PATH` and `boris validate --report PATH`
/// on success and failure. No `pageCount` — only errors/diagnostics.
public struct HTMLBuildReport: Codable, Sendable {
    public var schemaVersion: String
    public var compilerId: String?
    public var ok: Bool
    public var contentRoot: String?
    public var outDir: String?
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
    /// Omitted in starter frontmatter; Boris emits JSON null.
    public var status: String?

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
    /// Author semantic relations (IR 0.3 facet), reshaped as edges. Same
    /// shape as `edges`; never used for build dependency walks. Present
    /// only when the corpus carries relations.
    public var relations: [GraphEdge]?
}

public struct GraphNode: Codable, Sendable {
    public var index: Int
    public var id: String
    public var sourcePath: String
    public var role: PageRole
    public var parent: String?
    public var parentIndex: Int?
    public var title: String
    /// Omitted in starter frontmatter; Boris emits JSON null.
    public var status: String?
    public var tags: [String]?
    /// Byte offset of the body start in the source file (IR has no bodies).
    public var bodyOffset: Int?
    /// Cooklang recipe (IR 0.4 facet). `nil` for a page that carries no
    /// recipe; present on every node once any page in the corpus does.
    public var recipe: CookRecipe?
}

// MARK: - Cooklang recipes (IR 0.4 facet)

/// `recipe` on a graph node (`ir-graph-0.4.0.schema.json`).
public struct CookRecipe: Codable, Sendable, Equatable {
    public var ingredients: [CookIngredient]
    public var cookware: [CookCookware]
    public var timers: [CookTimer]

    public init(
        ingredients: [CookIngredient] = [],
        cookware: [CookCookware] = [],
        timers: [CookTimer] = []
    ) {
        self.ingredients = ingredients
        self.cookware = cookware
        self.timers = timers
    }
}

public struct CookIngredient: Codable, Sendable, Equatable {
    public var name: String
    public var quantity: CookQuantity
    /// Short-hand preparation from `(...)`; empty when absent.
    public var preparation: String
    /// Entity id of the referenced recipe when the author wrote `@./path`.
    public var recipeRef: String?

    public init(
        name: String,
        quantity: CookQuantity,
        preparation: String = "",
        recipeRef: String? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.preparation = preparation
        self.recipeRef = recipeRef
    }
}

public struct CookCookware: Codable, Sendable, Equatable {
    public var name: String
    public var quantity: CookQuantity

    public init(name: String, quantity: CookQuantity) {
        self.name = name
        self.quantity = quantity
    }
}

public struct CookTimer: Codable, Sendable, Equatable {
    /// Empty for an anonymous timer.
    public var name: String
    public var quantity: CookQuantity

    public init(name: String, quantity: CookQuantity) {
        self.name = name
        self.quantity = quantity
    }
}

public struct CookQuantity: Codable, Sendable, Equatable {
    public var amount: String
    public var unit: String

    public init(amount: String, unit: String = "") {
        self.amount = amount
        self.unit = unit
    }
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
    /// Documentation-intelligence 0.2.0 additions. Optional so a 0.1.0
    /// report still decodes: older shapes degrade (D8), never crash.
    public var nodes: [AnalysisNode]?
    public var edges: [GraphEdge]?
    public var sourceLocations: [AnalysisLocation]?
    public var diagnostics: [Diagnostic]?
}

/// 0.2.0: one entry per page node in the validated graph.
public struct AnalysisNode: Codable, Sendable {
    /// Const "page" in the schema.
    public var type: String
    public var id: String
    public var sourcePath: String
    public var parent: String?
}

/// 0.2.0: a source location the report points at.
public struct AnalysisLocation: Codable, Sendable {
    /// "page" or "source".
    public var type: String
    public var value: String
    public var sourcePath: String
    public var line: Int
    public var column: Int
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

// MARK: - Completion (`boris-completion-index`, schema_version integer 1)

/// `completion.json` — editor completion surface published on a successful IR
/// freeze. `schema_version` is an integer, unlike the IR string `schemaVersion`.
public struct Completion: Codable, Sendable {
    public var format: String
    public var schema_version: Int?
    public var compiler_id: String?
    public var frozen: Bool?
    public var entities: [CompletionEntity]
    public var relation_kinds: [String]
    public var parent_targets: [String]
    public var layout_slots: [String]
}

public struct CompletionEntity: Codable, Sendable {
    public var id: String
    public var title: String?
    public var parent: String?
    public var role: String?
    public var status: String?
    public var tags: [String]
    public var relations: [CompletionRelation]
}

public struct CompletionRelation: Codable, Sendable {
    public var kind: String
    public var target: String
}

// MARK: - Publication profile (`boris-publication-profile`, schema v1)

/// Strict mirror of profile schema v1. Unknown keys are ignored on decode
/// (D8); do not invent keys when encoding.
public struct PublicationProfile: Codable, Sendable, Equatable {
    public var format: String
    public var schema_version: Int?
    public var input: String?
    public var input_format: String?
    public var site: PublicationSite?
    public var publication: PublicationDeclaration?
    public var targets: [PublicationTarget]?
    public var editions: PublicationEditions?

    public init(
        format: String = "boris-publication-profile",
        schema_version: Int? = 1,
        input: String? = nil,
        input_format: String? = nil,
        site: PublicationSite? = nil,
        publication: PublicationDeclaration? = nil,
        targets: [PublicationTarget]? = nil,
        editions: PublicationEditions? = nil
    ) {
        self.format = format
        self.schema_version = schema_version
        self.input = input
        self.input_format = input_format
        self.site = site
        self.publication = publication
        self.targets = targets
        self.editions = editions
    }
}

public struct PublicationSite: Codable, Sendable, Equatable {
    public var url: String?
    public var title: String?
    public var description: String?

    public init(url: String? = nil, title: String? = nil, description: String? = nil) {
        self.url = url
        self.title = title
        self.description = description
    }
}

public struct PublicationDeclaration: Codable, Sendable, Equatable {
    public var target: String
    public var base_url: String?
    public var origin: String?
    public var base_path: String?
    public var site_kind: String?
    public var did: String?
    public var pds: String?
    public var pds_origin: String?
    public var name: String?
    public var description: String?
    public var show_in_discover: Bool?
    public var include: [String]?
    public var exclude: [String]?
    public var prune: Bool?

    public init(
        target: String,
        base_url: String? = nil,
        origin: String? = nil,
        base_path: String? = nil,
        site_kind: String? = nil,
        did: String? = nil,
        pds: String? = nil,
        pds_origin: String? = nil,
        name: String? = nil,
        description: String? = nil,
        show_in_discover: Bool? = nil,
        include: [String]? = nil,
        exclude: [String]? = nil,
        prune: Bool? = nil
    ) {
        self.target = target
        self.base_url = base_url
        self.origin = origin
        self.base_path = base_path
        self.site_kind = site_kind
        self.did = did
        self.pds = pds
        self.pds_origin = pds_origin
        self.name = name
        self.description = description
        self.show_in_discover = show_in_discover
        self.include = include
        self.exclude = exclude
        self.prune = prune
    }
}

public struct PublicationLayoutRule: Codable, Sendable, Equatable {
    public var selector: String
    public var layout: String

    public init(selector: String, layout: String) {
        self.selector = selector
        self.layout = layout
    }
}

public struct PublicationPathOutput: Codable, Sendable, Equatable {
    public var path: String
    public var limit: Int?

    public init(path: String, limit: Int? = nil) {
        self.path = path
        self.limit = limit
    }
}

public struct PublicationTarget: Codable, Sendable, Equatable {
    public var name: String
    public var output: String
    public var `public`: Bool?
    public var theme: String?
    public var layout: String?
    public var layout_rules: [PublicationLayoutRule]?
    public var sitemap: PublicationPathOutput?
    public var rss: PublicationPathOutput?
    public var llms: PublicationPathOutput?

    public init(
        name: String,
        output: String,
        public: Bool? = nil,
        theme: String? = nil,
        layout: String? = nil,
        layout_rules: [PublicationLayoutRule]? = nil,
        sitemap: PublicationPathOutput? = nil,
        rss: PublicationPathOutput? = nil,
        llms: PublicationPathOutput? = nil
    ) {
        self.name = name
        self.output = output
        self.public = `public`
        self.theme = theme
        self.layout = layout
        self.layout_rules = layout_rules
        self.sitemap = sitemap
        self.rss = rss
        self.llms = llms
    }
}

public struct PublicationEdition: Codable, Sendable, Equatable {
    public var output: String

    public init(output: String) {
        self.output = output
    }
}

public struct PublicationRagEdition: Codable, Sendable, Equatable {
    public var output: String
    public var scope: String?
    public var split_size: Int?
    public var bundles_only: Bool?

    public init(
        output: String,
        scope: String? = nil,
        split_size: Int? = nil,
        bundles_only: Bool? = nil
    ) {
        self.output = output
        self.scope = scope
        self.split_size = split_size
        self.bundles_only = bundles_only
    }
}

public struct PublicationContextEdition: Codable, Sendable, Equatable {
    public var output: String
    public var scope: String?
    public var split_size: Int?

    public init(
        output: String,
        scope: String? = nil,
        split_size: Int? = nil
    ) {
        self.output = output
        self.scope = scope
        self.split_size = split_size
    }
}

public struct PublicationEditions: Codable, Sendable, Equatable {
    public var ir: PublicationEdition?
    public var rag: PublicationRagEdition?
    public var context: PublicationContextEdition?

    public init(
        ir: PublicationEdition? = nil,
        rag: PublicationRagEdition? = nil,
        context: PublicationContextEdition? = nil
    ) {
        self.ir = ir
        self.rag = rag
        self.context = context
    }
}

// MARK: - Publication plan (`boris-publication-plan`, schema v1)

/// Normalized declaration emitted on stdout by `boris plan --profile PATH`.
public struct PublicationPlan: Codable, Sendable {
    public var format: String
    public var schema_version: Int?
    public var input: String?
    public var input_format: String?
    public var site: PublicationSite?
    public var publication: PublicationDeclaration?
    public var targets: [PublicationPlanTarget]?
    public var editions: PublicationEditions?
}

public struct PublicationPlanTarget: Codable, Sendable {
    public var name: String
    public var output: String
    public var `public`: Bool?
    public var theme: String?
    public var layout: String?
    public var layout_rules: [PublicationLayoutRule]?
    public var projections: PublicationProjections?
}

public struct PublicationProjections: Codable, Sendable {
    public var html: Bool?
    public var sitemap: PublicationPathOutput?
    public var rss: PublicationPathOutput?
    public var llms: PublicationPathOutput?
}

// MARK: - Timings (`boris-timings`)

/// Optional observational report printed on stdout when `--timings` is set.
public struct TimingsReport: Codable, Sendable {
    public var format: String
    public var schemaVersion: String?
    public var mode: String?
    public var phases: [String: Int]?
    public var counters: TimingsCounters?
    public var totalNs: Int?
}

public struct TimingsCounters: Codable, Sendable {
    public var page_reads: Int?
    public var include_reads: Int?
    public var hash_bytes: Int?
    public var link_resolutions: Int?
    public var fast_path_hits: Int?
}

// MARK: - Schema version policy (D8)

/// D8: unknown/newer `schemaVersion` degrades visibly, never crashes.
/// Consumers must classify an IR document before trusting its shape; the
/// mirrors knowingly decode these versions:
///   0.2.0 — typed dependency edges (v0.2 IR)
///   0.3.0 — semantic-relations facet (what the happy fixtures carry)
///   0.4.0 — Cooklang recipe facet
public enum ContractSchema {
    public static let supportedIR: Set<String> = ["0.2.0", "0.3.0", "0.4.0"]

    public enum Status: Equatable, Sendable {
        case supported
        case unknown(String)
    }

    public static func status(ofIR version: String?) -> Status {
        guard let version, supportedIR.contains(version) else {
            return .unknown(version ?? "missing")
        }
        return .supported
    }
}
