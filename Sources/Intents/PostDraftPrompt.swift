import AppKit

/// The File-menu face of M18: ask for a topic, draft with the on-device
/// model, stage the result in compose. Same pipeline as the Siri intent,
/// different front door (menus first).
@MainActor
enum PostDraftPrompt {
    static func runAndStage() {
        guard let topic = requestTopic() else { return }
        Task {
            do {
                let draft = try await PostDraftEngine.draft(topic: topic, origin: .menu)
                DraftRouter.shared.deliver(draft)
                // Same action as the Siri intent, performed by hand:
                // donate so suggestions reflect real usage.
                DraftPostIntent().donateQuietly()
            } catch {
                // Unavailability and model failures are surfaced, never
                // swallowed (boundary 3).
                presentFailure(error)
            }
        }
    }

    /// Modal topic prompt. Cancel/Escape returns nil and nothing runs.
    private static func requestTopic() -> String? {
        let alert = NSAlert()
        alert.messageText = "New Draft with Apple Intelligence"
        alert.informativeText = "What should the post be about?"
        alert.addButton(withTitle: "Draft")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Topic"
        alert.accessoryView = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func presentFailure(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
