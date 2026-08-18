import XCTest

final class SaveValidateGateTests: XCTestCase {
    func testSaveStormArmsDebounceEachTimeThenStartsOnce() {
        var gate = SaveValidateGate()
        let start = ContinuousClock.now

        XCTAssertEqual(gate.noteSave(now: start, state: .idle), .armDebounce)
        XCTAssertEqual(
            gate.noteSave(now: start.advanced(by: .milliseconds(80)), state: .idle),
            .armDebounce
        )
        XCTAssertEqual(
            gate.noteSave(now: start.advanced(by: .milliseconds(160)), state: .idle),
            .armDebounce
        )
        XCTAssertEqual(
            gate.debounceFired(now: start.advanced(by: .milliseconds(460)), state: .idle),
            .startValidate
        )
        XCTAssertFalse(gate.queued)
    }

    func testSaveDuringBuildQueuesAndStartsIfFresh() {
        var gate = SaveValidateGate()
        let start = ContinuousClock.now

        XCTAssertEqual(gate.noteSave(now: start, state: .building), .none)
        XCTAssertTrue(gate.queued)
        XCTAssertEqual(
            gate.jobFinished(now: start.advanced(by: .milliseconds(400)), freshness: .seconds(2)),
            .startValidate
        )
    }

    func testQueuedSaveDropsWhenStale() {
        var gate = SaveValidateGate()
        let start = ContinuousClock.now

        XCTAssertEqual(gate.noteSave(now: start, state: .validating), .none)
        XCTAssertEqual(
            gate.jobFinished(now: start.advanced(by: .seconds(3)), freshness: .seconds(2)),
            .dropPending
        )
        XCTAssertFalse(gate.queued)
    }

    func testManualVerbCancelsPendingQueue() {
        var gate = SaveValidateGate()
        let start = ContinuousClock.now
        _ = gate.noteSave(now: start, state: .building)
        XCTAssertTrue(gate.queued)
        gate.manualVerbStarted()
        XCTAssertFalse(gate.queued)
        XCTAssertEqual(
            gate.jobFinished(now: start.advanced(by: .milliseconds(10)), freshness: .seconds(2)),
            .none
        )
    }

    func testManualValidateSkipWindowSuppressesSaves() {
        var gate = SaveValidateGate()
        let start = ContinuousClock.now
        gate.manualValidateFinished(now: start, skip: .seconds(2))
        XCTAssertEqual(
            gate.noteSave(now: start.advanced(by: .milliseconds(200)), state: .idle),
            .none
        )
        XCTAssertEqual(
            gate.noteSave(now: start.advanced(by: .seconds(3)), state: .watching),
            .armDebounce
        )
    }

    func testTerminatingDropsSaves() {
        var gate = SaveValidateGate()
        let start = ContinuousClock.now
        XCTAssertEqual(gate.noteSave(now: start, state: .terminating), .none)
        XCTAssertFalse(gate.queued)
        XCTAssertEqual(gate.debounceFired(now: start, state: .terminating), .dropPending)
    }

    func testDebounceDuringJobQueues() {
        var gate = SaveValidateGate()
        let start = ContinuousClock.now
        XCTAssertEqual(gate.debounceFired(now: start, state: .building), .none)
        XCTAssertTrue(gate.queued)
    }

    func testPolicyDefaults() {
        XCTAssertEqual(CoordinatorPolicy.saveDebounceDefault, .milliseconds(300))
        XCTAssertEqual(CoordinatorPolicy.oneShotTimeoutDefault, .seconds(60))
        XCTAssertEqual(CoordinatorPolicy.buildTimeoutDefault, .seconds(300))
        XCTAssertEqual(CoordinatorPolicy.queuedFreshnessDefault, .seconds(2))
        XCTAssertEqual(CoordinatorPolicy.manualSkipDefault, .seconds(2))
    }

    func testStateTransitionsStayCanonical() {
        let states: [CoordinatorState] = [
            .idle, .watching, .validating, .building, .terminating,
        ]
        XCTAssertEqual(states.map(\.rawValue), [
            "idle", "watching", "validating", "building", "terminating",
        ])
    }
}
