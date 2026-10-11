import Foundation

/// Auto-reconnect policy for spontaneous `boris-editor` crashes (#232): up
/// to three restarts inside a 30s sliding window, backing off 2s × attempt.
/// Pure so the cap/window arithmetic is unit-testable without a clock.
enum EditorAutoReconnect {
    static let maxAttempts = 3
    static let window: Duration = .seconds(30)
    static let baseDelay: Duration = .seconds(2)

    enum Decision: Equatable {
        /// Schedule the next automatic restart; payload is the 1-based
        /// attempt number (delay = baseDelay × attempt).
        case retry(attempt: Int)
        /// Cap reached within the window — manual restart required.
        case giveUp
    }

    /// Drops crash instants that aged out of the sliding window.
    static func prune(_ crashes: [ContinuousClock.Instant], now: ContinuousClock.Instant) -> [ContinuousClock.Instant] {
        let cutoff = now - window
        return crashes.filter { $0 >= cutoff }
    }

    /// Decides what to do given the number of crashes recorded in the
    /// window, including the one that just happened.
    static func decision(crashesInWindow count: Int) -> Decision {
        count > maxAttempts ? .giveUp : .retry(attempt: count)
    }

    static let windowDescription = "\(window.components.seconds)s"
}
