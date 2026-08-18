import AppKit
import Foundation

/// Modal prompt for a publish secret. The field is secure; the value is
/// copied into a `SecureBuffer` and the string is not kept.
enum PublishSecretPrompt {
    struct Answer {
        var secret: SecureBuffer
        var rememberInKeychain: Bool
    }

    @MainActor
    static func present(for verb: CoordinatorVerb) -> Answer? {
        switch verb {
        case .publishNostr:
            return present(
                title: "Nostr Signing Key",
                message: "Paste an nsec or 64-character hex key. It is piped to boris on stdin and never placed in argv, env, or the profile.",
                rememberTitle: "Remember in Keychain"
            )
        case .publishStandardSite:
            return present(
                title: "Standard.site App Password",
                message: "Piped to `boris standard-site login --app-password` on stdin. App passwords grant broad account write — use a dedicated identity.",
                rememberTitle: "Remember in Keychain"
            )
        default:
            return nil
        }
    }

    @MainActor
    static func present(title: String, message: String, rememberTitle: String) -> Answer? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Secret"
        let remember = NSButton(checkboxWithTitle: rememberTitle, target: nil, action: nil)
        remember.state = .off

        let stack = NSStackView(views: [field, remember])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        alert.accessoryView = stack

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.stringValue = ""
        guard !text.isEmpty else { return nil }
        return Answer(
            secret: SecureBuffer(utf8String: text),
            rememberInKeychain: remember.state == .on
        )
    }
}
