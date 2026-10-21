import Foundation

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
    /// The source the job ran against — nil for jobs that never got a
    /// source (guard-failed starts). Callers scope per-source reads on it.
    let sourceID: SourceID?

    init(
        id: UUID = UUID(),
        verb: CoordinatorVerb,
        exitCode: Int32?,
        summary: String,
        timestamp: Date = Date(),
        durationNs: Int? = nil,
        timings: TimingsReport? = nil,
        problemsCount: Int = 0,
        sourceID: SourceID? = nil
    ) {
        self.id = id
        self.verb = verb
        self.exitCode = exitCode
        self.summary = summary
        self.timestamp = timestamp
        self.durationNs = durationNs
        self.timings = timings
        self.problemsCount = problemsCount
        self.sourceID = sourceID
    }

    var isSuccess: Bool {
        exitCode == 0
    }
}
