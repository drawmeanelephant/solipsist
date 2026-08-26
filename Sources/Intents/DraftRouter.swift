import Foundation

/// The App Intent → app handoff. Siri (or the File menu) produces a
/// `StagedPostDraft` before the compose window exists, so delivery is
/// queued here and flushed when `MainWindow` registers the opener.
///
/// Same shape as `AppDelegate.openFolder`'s deferred-delivery pattern:
/// a MainActor singleton, a pending queue for cold launches, one
/// consumer closure. Nothing here knows about SwiftUI or windows.
@MainActor
final class DraftRouter {
    static let shared = DraftRouter()

    var consume: ((StagedPostDraft) -> Void)?
    private var pending: [StagedPostDraft] = []

    /// Producers call this: Siri's `perform()`, the menu prompt.
    func deliver(_ draft: StagedPostDraft) {
        if let consume {
            consume(draft)
        } else {
            pending.append(draft)
        }
    }

    /// The app side registers its opener once the window group is alive.
    func register(consumer: @escaping (StagedPostDraft) -> Void) {
        consume = consumer
        let queued = pending
        pending.removeAll()
        queued.forEach(consumer)
    }

    /// Test seam: drop everything.
    func reset() {
        consume = nil
        pending.removeAll()
    }
}
