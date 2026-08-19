import Foundation

/// Coordinator states from the #58 state machine. `validating` is any
/// non-tree-writing one-shot; `building` is any tree-writing one-shot.
enum CoordinatorVerb: String, Sendable {
    case plan
    case validate
    case buildIR
    case buildHTML
    case buildThis = "build this"
    case buildAll
    case check
    case impact
    case publishStandardSite = "publish Standard.site"
    case standardSiteVerify = "Standard.site verify"
    case standardSiteRecords = "Standard.site records"
    case standardSiteSessions = "Standard.site sessions"
    case standardSiteLogout = "Standard.site logout"
    case standardSiteSmoke = "Standard.site smoke"
    case publishNostr = "publish Nostr"
    case package
    case recipeScale = "recipe-scale"
    case sourceRag = "source RAG"
    case contentAudit = "content audit"

    /// Jobs that write trees watch also owns (`dist/`, `.boris`, proof, packages)
    /// or generate artifacts in the workspace (source RAG pack, content audit).
    var writesTree: Bool {
        switch self {
        case .buildIR, .buildHTML, .buildThis, .buildAll, .publishStandardSite, .publishNostr, .package, .sourceRag, .contentAudit:
            true
        case .plan, .validate, .check, .impact, .standardSiteVerify, .standardSiteRecords, .standardSiteSessions, .standardSiteLogout, .standardSiteSmoke, .recipeScale:
            false
        }
    }

    var timeout: Duration {
        writesTree ? CoordinatorPolicy.buildTimeout : CoordinatorPolicy.oneShotTimeout
    }

    var secretTarget: String? {
        switch self {
        case .publishNostr: PublishTargets.nostr
        case .publishStandardSite: PublishTargets.standardSite
        default: nil
        }
    }
}

enum CoordinatorState: String, Sendable {
    case idle
    case watching
    case validating
    case building
    case terminating
}

/// Machine-local timings (D2: app plist / UserDefaults, never `boris.json`).
enum CoordinatorPolicy {
    static let saveDebounceDefault: Duration = .milliseconds(300)
    static let queuedFreshnessDefault: Duration = .seconds(2)
    static let manualSkipDefault: Duration = .seconds(2)
    static let oneShotTimeoutDefault: Duration = .seconds(60)
    static let buildTimeoutDefault: Duration = .seconds(300)

    private static let debounceKey = "solipsist.coordinator.saveDebounceMs"
    private static let freshnessKey = "solipsist.coordinator.queuedFreshnessMs"
    private static let skipKey = "solipsist.coordinator.manualSkipMs"
    private static let oneShotKey = "solipsist.coordinator.oneShotTimeoutMs"
    private static let buildKey = "solipsist.coordinator.buildTimeoutMs"

    static var saveDebounce: Duration { milliseconds(debounceKey, default: 300) }
    static var queuedFreshness: Duration { milliseconds(freshnessKey, default: 2_000) }
    static var manualSkip: Duration { milliseconds(skipKey, default: 2_000) }
    static var oneShotTimeout: Duration { milliseconds(oneShotKey, default: 60_000) }
    static var buildTimeout: Duration { milliseconds(buildKey, default: 300_000) }

    private static func milliseconds(_ key: String, default value: Int) -> Duration {
        let stored = UserDefaults.standard.object(forKey: key) as? Int
        return .milliseconds(stored ?? value)
    }
}

/// Where content-audit reports land: the app container (caches), keyed per
/// source — never the user's content tree (ENGINE-CONTRACTS §8: read-only
/// over the source, and `--out` must be a real path, which `~/Library/Caches`
/// is and `/tmp` is not on macOS).
enum ContentAuditOutput {
    static func directory(for source: any PlayFolderSource) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appendingPathComponent("content-audit", isDirectory: true)
            .appendingPathComponent(source.id.raw.uuidString, isDirectory: true)
    }
}
