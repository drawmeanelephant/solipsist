import Foundation

/// Pure save-triggered validate policy. Timers live on the coordinator;
/// this type only decides what happens next.
struct SaveValidateGate: Sendable {
    var lastSave: ContinuousClock.Instant?
    var skipUntil: ContinuousClock.Instant?
    var queued = false

    enum Action: Equatable, Sendable {
        case armDebounce
        case startValidate
        case dropPending
        case none
    }

    mutating func noteSave(now: ContinuousClock.Instant, state: CoordinatorState) -> Action {
        lastSave = now
        switch state {
        case .terminating:
            queued = false
            return .none
        case .building, .validating:
            queued = true
            return .none
        case .idle, .watching:
            if let skipUntil, now < skipUntil {
                return .none
            }
            queued = false
            return .armDebounce
        }
    }

    mutating func debounceFired(now: ContinuousClock.Instant, state: CoordinatorState) -> Action {
        switch state {
        case .terminating:
            queued = false
            return .dropPending
        case .building, .validating:
            queued = true
            return .none
        case .idle, .watching:
            if let skipUntil, now < skipUntil {
                return .none
            }
            queued = false
            return .startValidate
        }
    }

    mutating func manualVerbStarted() {
        queued = false
    }

    mutating func manualValidateFinished(now: ContinuousClock.Instant, skip: Duration) {
        skipUntil = now.advanced(by: skip)
    }

    mutating func jobFinished(
        now: ContinuousClock.Instant,
        freshness: Duration
    ) -> Action {
        guard queued else { return .none }
        guard let lastSave, now - lastSave <= freshness else {
            queued = false
            return .dropPending
        }
        if let skipUntil, now < skipUntil {
            queued = false
            return .none
        }
        queued = false
        return .startValidate
    }

    mutating func dropAll() {
        queued = false
        lastSave = nil
        skipUntil = nil
    }
}
