import Foundation

/// #231: the one save path for Compose. Toolbar Save, ⌘S, and any host
/// verb funnel through this sequence so the buffer is written **inside**
/// the preview-watch suspension — never mid-write while boris watches:
///
///     beginTreeWrite()   // suspend the watch
///     document.save()    // write
///     endTreeWrite()     // resume (deferred: runs on failure too)
///     noteSave()         // queue validate — only after a real write
enum ComposeSaveFlow {
    /// What one save attempt did.
    enum Outcome: Equatable {
        /// Wrote and queued validation.
        case saved
        /// Buffer was clean or had no URL — nothing written, nothing queued.
        case notDirty
        /// The write threw; the watch is resumed and validation is not queued.
        case failed(String)
    }

    /// Runs one save inside the tree-write window. `endTreeWrite` is
    /// deferred, so a throwing write can never leave the watch suspended.
    static func run(
        beginTreeWrite: () -> Void,
        endTreeWrite: () -> Void,
        noteSave: () -> Void = {},
        save: () throws -> Bool
    ) -> Outcome {
        beginTreeWrite()
        defer { endTreeWrite() }
        do {
            guard try save() else { return .notDirty }
        } catch {
            return .failed(error.localizedDescription)
        }
        noteSave()
        return .saved
    }

    /// #265: the status-bar save signal, derived from the typed outcome
    /// instead of string-matching rendered text ("contains(\"Saved\")").
    enum Signal: Equatable {
        case saved(message: String)
        case failed(message: String)

        /// `.notDirty` (clean-and-idle) produces no signal at all.
        init?(outcome: Outcome, savedMessage: String) {
            switch outcome {
            case .saved:
                self = .saved(message: savedMessage)
            case .notDirty:
                return nil
            case .failed(let message):
                self = .failed(message: message)
            }
        }

        var message: String {
            switch self {
            case .saved(let message), .failed(let message): return message
            }
        }

        var isError: Bool {
            if case .failed = self { return true }
            return false
        }

        var symbolName: String {
            isError ? "xmark.octagon.fill" : "checkmark"
        }
    }
}
