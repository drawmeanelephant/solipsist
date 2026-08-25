import Foundation

/// #267: human idle-state copy for the editor companion chrome. Leads with
/// what to do; manual connect is mentioned only as the last-resort sentence
/// (#237 collapsed that field behind Manual Connect).
enum EditorIdleCopy {
    static let lead = "Choose File → Edit Page, or press Restart Host below."
    static let lastResort = "Manual Connect stays available below as a last resort."

    static var description: String {
        lead + " " + lastResort
    }
}

/// #280: maps typed session failures to actionable guidance for the idle
/// state. Switches on `EditorSessionError` cases — compiler-checked against
/// the enum instead of substring matching raw wording. Cases with no
/// dedicated guidance return nil so the view falls back to the idle copy.
enum EditorFailureGuidance {
    struct Guidance: Equatable {
        let headline: String
        let detail: String
    }

    static func guidance(for error: EditorSessionError) -> Guidance? {
        switch error {
        case .binaryNotFound:
            return Guidance(
                headline: "boris-editor binary not found",
                detail: "Install boris-editor or set SOLIPSIST_BORIS_EDITOR_BIN in your environment."
            )
        case .timeout:
            return Guidance(
                headline: "Editor host did not report a token URL within \(EditorSession.connectTimeoutDescription)",
                detail: "The editor host may be slow to start. Try again or check the boris-editor logs."
            )
        case .crashLoop:
            return Guidance(
                headline: error.message,
                detail: "The editor host crashed. Check the boris-editor logs for details."
            )
        case .engineUnavailable:
            return Guidance(
                headline: error.message,
                detail: "Ensure Boris is built and the engine binary is accessible."
            )
        case .launchFailed, .folderUnresolved:
            return nil
        }
    }
}

/// #267: human phase copy for the editor chrome — display-only mapping;
/// the session's `Phase` enum shape is untouched. Enumerates all five cases
/// (the A11Y-4 pattern) so a new case cannot compile without a label.
enum EditorPhaseCopy {
    static func label(for phase: EditorSession.Phase) -> String {
        switch phase {
        case .idle:
            return "Not connected"
        case .starting:
            return "Connecting…"
        case .connected:
            return "Ready"
        case .reconnecting(let attempt):
            return "Connection lost — retrying (\(attempt) of \(EditorAutoReconnect.maxAttempts))"
        case .failed(let error):
            return error.message
        }
    }

    /// VoiceOver label for every phase value the indicator can render.
    static func accessibilityLabel(for phase: EditorSession.Phase) -> String {
        switch phase {
        case .idle:
            return "Not connected"
        case .starting:
            return "Connecting"
        case .connected:
            return "Ready"
        case .reconnecting(let attempt):
            return "Connection lost — retrying, attempt \(attempt) of \(EditorAutoReconnect.maxAttempts)"
        case .failed:
            return "Connection failed"
        }
    }
}
