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

/// #267: human phase copy for the editor chrome — display-only mapping;
/// the session's `Phase` enum is untouched. Enumerates all five cases (the
/// A11Y-4 pattern) so a new case cannot compile without a label.
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
        case .failed(let message):
            return message
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
