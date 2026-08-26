import Foundation

/// A finished AI draft, staged for review in the compose buffer. Plain
/// data on purpose: it crosses the App Intent → app handoff and the
/// engine seam, and it never touches disk by itself.
///
/// Boundary 4 (`AGENTS.md`): staging is memory-only. The buffer becomes
/// a file only through compose's explicit Save, which routes through the
/// same `ComposeSaveFlow` tree-write window as every other save.
struct StagedPostDraft: Equatable, Sendable {
    var title: String
    var summary: String
    var tags: [String]
    /// Markdown body. No frontmatter — assembly adds that canonically.
    var body: String
    var origin: Origin

    enum Origin: String, Equatable, Sendable {
        case siri
        case menu
    }

    init(title: String, summary: String = "", tags: [String] = [], body: String, origin: Origin) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.body = body
        self.origin = origin
    }
}

enum PostDraftAssembly {
    /// File-name stem for an untitled draft: `title` → `my-post-title`.
    /// Punctuation runs become separators; falls back to `"untitled"`
    /// when nothing survives slugification.
    static func slug(_ title: String) -> String {
        var mapped = String.UnicodeScalarView()
        for scalar in title.lowercased().unicodeScalars {
            mapped.append(CharacterSet.alphanumerics.contains(scalar) ? scalar : " ")
        }
        let cleaned = String(mapped)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let capped = String(cleaned.prefix(80))
        return capped.isEmpty ? "untitled" : String(capped.drop(while: { $0 == "-" }))
    }

    /// The staged draft as compose-buffer text: canonical frontmatter
    /// (closed keys only, emitted by `ComposeFrontmatter.apply`) followed
    /// by the body. We never invent keys — absence == null per schema —
    /// so `parent`/`status`/`id` are left to the author's front-matter pane.
    static func markdown(for draft: StagedPostDraft) -> String {
        var fields = ComposeFrontmatter.Fields.empty
        fields.title = draft.title
        fields.summary = draft.summary
        fields.tags = draft.tags
        let payload = ComposeFrontmatter.apply(fields, to: "")
        guard !payload.isEmpty else {
            return draft.body
        }
        return "---\n\(payload)\n---\n\n\(draft.body)\n"
    }
}
