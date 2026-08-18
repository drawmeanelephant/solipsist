import Foundation

/// Coordinator states from the #58 state machine. `validating` is any
/// non-tree-writing one-shot; `building` is any tree-writing one-shot.
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
