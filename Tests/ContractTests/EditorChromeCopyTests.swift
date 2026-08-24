import XCTest

/// #267 — Editor companion humanized chrome, round 2. Pins the display-only
/// copy mappings; the session's `Phase` enum and reconnect policy (#232)
/// are untouched.
final class EditorChromeCopyTests: XCTestCase {
    private let url = URL(string: "http://127.0.0.1:49152/#token=x")!

    func testPhaseLabelHumanWording() {
        XCTAssertEqual(EditorPhaseCopy.label(for: .idle), "Not connected")
        XCTAssertEqual(EditorPhaseCopy.label(for: .starting), "Connecting…")
        XCTAssertEqual(EditorPhaseCopy.label(for: .connected(url)), "Ready")
        XCTAssertEqual(
            EditorPhaseCopy.label(for: .reconnecting(attempt: 2)),
            "Connection lost — retrying (2 of \(EditorAutoReconnect.maxAttempts))"
        )
        XCTAssertEqual(EditorPhaseCopy.label(for: .failed("host exited")), "host exited")
    }

    func testPhaseAccessibilityLabelsEnumerateAllCases() {
        // The A11Y-4 pattern: every case carries a non-empty VoiceOver label.
        let phases: [EditorSession.Phase] = [
            .idle,
            .starting,
            .connected(url),
            .reconnecting(attempt: 1),
            .failed("boom"),
        ]
        for phase in phases {
            XCTAssertFalse(EditorPhaseCopy.accessibilityLabel(for: phase).isEmpty)
        }
        // No more engine-speak in the accessible chrome.
        XCTAssertFalse(EditorPhaseCopy.accessibilityLabel(for: .starting).contains("Engine"))
    }

    func testIdleCopyLeadsWithAction() {
        let description = EditorIdleCopy.description
        XCTAssertTrue(description.contains("File → Edit Page"), "the action leads the copy")
        guard
            let leadRange = description.range(of: EditorIdleCopy.lead),
            let lastResortRange = description.range(of: "last resort")
        else {
            return XCTFail("idle copy must contain both the lead action and the last-resort sentence")
        }
        XCTAssertLessThan(
            leadRange.lowerBound, lastResortRange.lowerBound,
            "manual-connect mention must come after the action"
        )
    }
}
