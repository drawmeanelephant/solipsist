import XCTest

/// #280 — typed editor failures. Pins the status-line copy per case and the
/// `EditorFailureGuidance` switch that replaced substring matching on raw
/// messages; wording drift now fails here instead of silently breaking the
/// editor chrome's guidance.
final class EditorSessionErrorTests: XCTestCase {
    // MARK: Status lines

    func testMessagesAreNonEmptyForEveryCase() {
        let errors: [EditorSessionError] = [
            .engineUnavailable,
            .binaryNotFound,
            .timeout,
            .crashLoop(stderrTail: ""),
            .crashLoop(stderrTail: "panic: token rejected"),
            .launchFailed("port in use"),
            .folderUnresolved("happy"),
        ]
        for error in errors {
            XCTAssertFalse(error.message.isEmpty, "\(error)")
        }
    }

    func testEngineUnavailableMessage() {
        XCTAssertEqual(EditorSessionError.engineUnavailable.message, "Boris engine not available.")
    }

    func testBinaryNotFoundSurfacesLaunchErrorVerbatim() {
        XCTAssertEqual(
            EditorSessionError.binaryNotFound.message,
            EditorHostLaunchError.editorBinaryNotFound.errorDescription
        )
    }

    func testTimeoutMessagePinsBudget() {
        XCTAssertEqual(
            EditorSessionError.timeout.message,
            "Editor host did not report a token URL within \(EditorSession.connectTimeoutDescription)."
        )
    }

    func testCrashLoopMessagePinsCapWindowAndTail() {
        let plain = EditorSessionError.crashLoop(stderrTail: "").message
        XCTAssertTrue(plain.contains("\(EditorAutoReconnect.maxAttempts) times"), plain)
        XCTAssertTrue(plain.contains(EditorAutoReconnect.windowDescription), plain)
        XCTAssertTrue(plain.contains("Manual restart required"), plain)
        XCTAssertFalse(plain.contains("—"), plain)

        let tailed = EditorSessionError.crashLoop(stderrTail: "boom").message
        XCTAssertTrue(tailed.hasSuffix(" — boom"), tailed)
    }

    func testLaunchFailedKeepsPrefix() {
        XCTAssertEqual(
            EditorSessionError.launchFailed("port in use").message,
            "Could not start editor host: port in use"
        )
    }

    func testFolderUnresolvedMessage() {
        XCTAssertEqual(
            EditorSessionError.folderUnresolved("stunts").message,
            "Could not resolve project folder for 'stunts'"
        )
    }

    func testLaunchErrorInitMapsEveryFactoryCase() {
        XCTAssertEqual(EditorSessionError(EditorHostLaunchError.editorBinaryNotFound), .binaryNotFound)
    }

    // MARK: Guidance mapping

    func testGuidanceCoversActionableCases() {
        XCTAssertNotNil(EditorFailureGuidance.guidance(for: .binaryNotFound))
        XCTAssertNotNil(EditorFailureGuidance.guidance(for: .timeout))
        XCTAssertNotNil(EditorFailureGuidance.guidance(for: .crashLoop(stderrTail: "")))
        XCTAssertNotNil(EditorFailureGuidance.guidance(for: .engineUnavailable))
    }

    func testGuidanceNilForPassThroughCases() {
        XCTAssertNil(EditorFailureGuidance.guidance(for: .launchFailed("x")))
        XCTAssertNil(EditorFailureGuidance.guidance(for: .folderUnresolved("y")))
    }

    func testGuidanceDetailsPinActionableAdvice() {
        XCTAssertEqual(
            EditorFailureGuidance.guidance(for: .binaryNotFound)?.detail,
            "Install boris-editor or set SOLIPSIST_BORIS_EDITOR_BIN in your environment."
        )
        XCTAssertEqual(
            EditorFailureGuidance.guidance(for: .timeout)?.detail,
            "The editor host may be slow to start. Try again or check the boris-editor logs."
        )
        XCTAssertEqual(
            EditorFailureGuidance.guidance(for: .crashLoop(stderrTail: ""))?.detail,
            "The editor host crashed. Check the boris-editor logs for details."
        )
        XCTAssertEqual(
            EditorFailureGuidance.guidance(for: .engineUnavailable)?.detail,
            "Ensure Boris is built and the engine binary is accessible."
        )
    }

    func testCrashAndEngineGuidanceHeadlineCarriesFullStatusLine() {
        XCTAssertEqual(
            EditorFailureGuidance.guidance(for: .engineUnavailable)?.headline,
            EditorSessionError.engineUnavailable.message
        )
        XCTAssertEqual(
            EditorFailureGuidance.guidance(for: .crashLoop(stderrTail: "boom"))?.headline,
            EditorSessionError.crashLoop(stderrTail: "boom").message
        )
    }
}
