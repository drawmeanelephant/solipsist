import Foundation
import Observation

/// The buffer behind the compose element: the source text, the frontend it
/// targets, and the save seam. Standalone by design — the window that hosts
/// it is a later card; this type only knows about a URL it may write to.
///
/// Boundary 4 of `AGENTS.md` applies: the buffer is never written to disk
/// except through an explicit `save()`. Nothing in the view layer calls
/// `save()` implicitly.
@MainActor
@Observable
final class ComposeDocument {
    /// The authored source text. Single source of truth.
    var text: String = "" {
        didSet {
            if text != oldValue {
                isDirty = true
                // Auto-detect only until the language is pinned (by the
                // initial load or an explicit picker choice); never override
                // the user's selection mid-session.
                if !languageExplicit {
                    language = ComposeLanguage.detect(fileURL: fileURL, contents: text)
                }
            }
        }
    }

    /// The frontend this buffer targets. Auto-detected until pinned; the
    /// picker's binding writes through this setter, which pins it.
    var language: ComposeLanguage {
        didSet {
            languageExplicit = true
        }
    }

    /// Whether `language` has been pinned (initial load or explicit choice).
    private var languageExplicit: Bool

    /// The URL `save()` writes to. Nil until the host supplies one.
    var fileURL: URL?

    /// Whether the buffer differs from the last save/load.
    private(set) var isDirty = false

    /// Human-readable state for the compose window's status line.
    var statusText: String {
        var parts: [String] = []
        if let fileURL {
            parts.append(fileURL.lastPathComponent)
        } else {
            parts.append("Untitled")
        }
        parts.append(language.displayName)
        if let frontmatter {
            parts.append("front matter: \(frontmatter.kind.rawValue)")
        }
        if isDirty {
            parts.append("edited")
        }
        return parts.joined(separator: " · ")
    }

    init(text: String = "", fileURL: URL? = nil, language: ComposeLanguage? = nil) {
        self.text = text
        self.fileURL = fileURL
        self.language = language ?? ComposeLanguage.detect(fileURL: fileURL, contents: text)
        self.languageExplicit = language != nil
        self.isDirty = false
    }

    /// The frontmatter dialect, mirroring Oliver's shared pre-pass
    /// (`src/frontmatter.zig`): YAML (`---`) / TOML (`+++`) sniffed at
    /// index 0, stripped before dispatch.
    enum FrontmatterKind: String {
        case yaml
        case toml
    }

    /// The raw frontmatter boundary. We expose it for highlighting and
    /// editing; we never fake a parsed view.
    struct Frontmatter: Equatable {
        let kind: FrontmatterKind
        /// Range of the whole `--- … ---` block, including both fences.
        let range: Range<String.Index>
        /// Raw payload between the fences (exclusive of the fence lines).
        let payload: Substring

        var payloadString: String { String(payload) }
    }

    /// Detects a `---`/`+++` frontmatter block anchored at index 0, matching
    /// Oliver's sniff-then-strip rule. An unclosed opener is *not* front
    /// matter (Oliver passes it through with an `unclosed-frontmatter`
    /// diagnostic).
    var frontmatter: Frontmatter? {
        Frontmatter.parse(in: text)
    }

    /// Explicit save. Returns false when there is nothing to save.
    @discardableResult
    func save() throws -> Bool {
        guard let fileURL, isDirty else { return false }
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        isDirty = false
        return true
    }

    /// Loads a file into the buffer (used by the future host; keeps the
    /// element testable in isolation).
    func load(from url: URL) throws {
        let loaded = try String(contentsOf: url, encoding: .utf8)
        fileURL = url
        text = loaded
        language = ComposeLanguage.detect(fileURL: url, contents: loaded)
        isDirty = false
    }
}

extension ComposeDocument.Frontmatter {
    static func parse(in text: String) -> ComposeDocument.Frontmatter? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        guard let first = lines.next() else { return nil }
        let fence = first.trimmingCharacters(in: .whitespaces)
        guard fence == "---" || fence == "+++" else { return nil }
        let kind: ComposeDocument.FrontmatterKind = fence == "---" ? .yaml : .toml

        // Reconstruct line offsets to find the closing fence.
        var index = text.startIndex
        var fenceLineStart: String.Index?
        var payloadStart: String.Index = text.startIndex
        var payloadEnd: String.Index = text.startIndex
        for (lineIndex, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if lineIndex == 0 {
                index = text.index(index, offsetBy: line.count)
                if index < text.endIndex, text[index] == "\n" {
                    index = text.index(after: index)
                }
                payloadStart = index
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == fence {
                fenceLineStart = index
                payloadEnd = index
                break
            }
            index = text.index(index, offsetBy: line.count)
            if index < text.endIndex, text[index] == "\n" {
                index = text.index(after: index)
            }
        }
        guard let fenceLineStart else { return nil }

        // `payloadEnd` is the fence line's start; back off the newline that
        // terminated the last content line so the payload excludes it.
        if payloadEnd > payloadStart, text[text.index(before: payloadEnd)] == "\n" {
            payloadEnd = text.index(before: payloadEnd)
        }

        let payload = text[payloadStart..<payloadEnd]
        // Range covers both fences: from the start of the document through
        // the closing fence line.
        let closeLineEnd = text.index(fenceLineStart, offsetBy: fence.count)
        let range = text.startIndex..<closeLineEnd
        return ComposeDocument.Frontmatter(kind: kind, range: range, payload: payload)
    }
}
