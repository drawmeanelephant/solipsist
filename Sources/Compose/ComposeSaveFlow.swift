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
}
