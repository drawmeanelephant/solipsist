import XCTest

/// #265 Status bar triage — the save signal is derived from the typed
/// `ComposeSaveFlow` outcome, never from string-matching rendered text.
final class ComposeStatusBarTriageTests: XCTestCase {
    func testSavedOutcomeDrivesIndicator() {
        let signal = ComposeSaveFlow.Signal(outcome: .saved, savedMessage: "Saved")
        XCTAssertEqual(signal, .saved(message: "Saved"))
        XCTAssertEqual(signal?.message, "Saved")
        XCTAssertFalse(signal?.isError ?? true)
        XCTAssertEqual(signal?.symbolName, "checkmark")
    }

    func testFailedOutcomeShowsMessageInRed() {
        let signal = ComposeSaveFlow.Signal(
            outcome: .failed("disk on strike"),
            savedMessage: "Saved"
        )
        XCTAssertEqual(signal, .failed(message: "disk on strike"))
        XCTAssertEqual(signal?.message, "disk on strike", "the raw failure message round-trips")
        XCTAssertTrue(signal?.isError ?? false)
        XCTAssertEqual(signal?.symbolName, "xmark.octagon.fill")
    }

    func testCleanIdleOutcomeShowsNothing() {
        // Clean-and-idle: no signal at all — the bar renders nothing.
        XCTAssertNil(ComposeSaveFlow.Signal(outcome: .notDirty, savedMessage: "Saved"))
    }
}
