import Foundation

/// Machine-local execution knobs. Stored in UserDefaults only — never
/// `boris.json` (D2).
public struct BorisExecutionKnobs: Equatable, Sendable {
    public var jobs: Int
    public var incremental: Bool
    public var quiet: Bool

    public static let jobsKey = "solipsist.execution.jobs"
    public static let incrementalKey = "solipsist.execution.incremental"
    public static let quietKey = "solipsist.execution.quiet"
    public static let jobsRange = 1...64

    public init(jobs: Int = 1, incremental: Bool = false, quiet: Bool = false) {
        self.jobs = min(max(jobs, Self.jobsRange.lowerBound), Self.jobsRange.upperBound)
        self.incremental = incremental
        self.quiet = quiet
    }

    public static func load(from defaults: UserDefaults = .standard) -> BorisExecutionKnobs {
        let rawJobs = defaults.object(forKey: jobsKey) as? Int ?? 1
        let incremental = defaults.bool(forKey: incrementalKey)
        let quiet = defaults.bool(forKey: quietKey)
        return BorisExecutionKnobs(jobs: rawJobs, incremental: incremental, quiet: quiet)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(jobs, forKey: Self.jobsKey)
        defaults.set(incremental, forKey: Self.incrementalKey)
        defaults.set(quiet, forKey: Self.quietKey)
    }

    /// Appends `--jobs <N>`, `--incrementalX, `--quiet` flags where requested / supported.
    public func apply(to args: inout [String], defaultQuiet: Bool = true) {
        if jobs > 1 {
            args.append(contentsOf: ["--jobs", "\(jobs)"])
        }
        if incremental {
            args.append("--incremental")
        }
        if quiet {
            if !args.contains("--quiet") {
                args.append("--quiet")
            }
        } else if !defaultQuiet {
            // default was not quiet and quiet is false
        }
    }
}
