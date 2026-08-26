import AppKit
import Foundation
import UniformTypeIdentifiers

/// M18 staged-draft seams, kept out of `ComposeWindow` so the window
/// stays under the file-length ceiling and the naming logic stays
/// testable headless.
///
/// Boundary 4 (`AGENTS.md`): the panel is the *only* place an untitled
/// draft acquires a destination, and it does so on an explicit Save.
enum ComposeStagedDraft {
    /// `page-title.md` from the draft's assembled frontmatter; falls back
    /// to `untitled.md` when the model produced no usable title.
    static func suggestedFileName(frontmatterPayload: String) -> String {
        let fields = ComposeFrontmatter.parse(payload: frontmatterPayload)
        return PostDraftAssembly.slug(fields.title) + ".md"
    }

    /// The sandbox-safe destination ask for an untitled buffer. Defaults
    /// to the selected source's content root when one is selected.
    /// Returns nil when the author cancels — nothing is written then.
    @MainActor
    static func runSavePanel(directoryURL: URL?, frontmatterPayload: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.text]
        panel.directoryURL = directoryURL
        panel.nameFieldStringValue = suggestedFileName(frontmatterPayload: frontmatterPayload)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
