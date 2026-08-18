import Foundation

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
    case publishNostr = "publish Nostr"

    /// Jobs that write trees watch also owns (`dist/`, `.boris`, proof).
    var writesTree: Bool {
        switch self {
        case .buildIR, .buildHTML, .buildThis, .buildAll, .publishStandardSite, .publishNostr:
            true
        case .plan, .validate, .check, .impact:
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

/// An execution record in the Coordinator activity history.
struct CoordinatorActivity: Identifiable, Sendable {
    let id: UUID
    let verb: CoordinatorVerb
    let exitCode: Int32?
    let summary: String
    let timestamp: Date
    let durationNs: Int?
    let timings: TimingsReport?
    let problemsCount: Int

    init(
        id: UUID = UUID(),
        verb: CoordinatorVerb,
        exitCode: Int32?,
        summary: String,
        timestamp: Date = Date(),
        durationNs: Int? = nil,
        timings: TimingsReport? = nil,
        problemsCount: Int = 0
    ) {
        self.id = id
        self.verb = verb
        self.exitCode = exitCode
        self.summary = summary
        self.timestamp = timestamp
        self.durationNs = durationNs
        self.timings = timings
        self.problemsCount = problemsCount
    }

    var isSuccess: Bool {
        exitCode == 0
    }
}
