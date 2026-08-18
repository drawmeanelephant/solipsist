import Foundation

/// The three authoring languages the compose element understands.
///
/// Oliver — the clean-room markup library that is the rendering engine
/// behind Boris — is the language reference for this surface
/// (`github.com/drawmeanelephant/oliver`). We mirror Oliver's frontends and
/// their feature surface here; we never reimplement parse semantics. The
/// feature notes in each case mirror Oliver's own capability docs
/// (`docs/CAPABILITIES.md`, `docs/FEATURE-MATRIX.md`, `docs/COOKLANG.md`).
enum ComposeLanguage: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case textile
    case cooklang

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .textile: return "Textile"
        case .cooklang: return "Cooklang"
        }
    }

    /// Oliver frontend entry point, for documentation and later wiring.
    var oliverFrontend: String {
        switch self {
        case .markdown: return "oliver.parse(..., .markdown, ...)"
        case .textile: return "oliver.parse(..., .textile, ...)"
        case .cooklang: return "oliver.cooklang.parse(...)"
        }
    }

    /// File extensions that conventionally select this frontend.
    var fileExtensions: Set<String> {
        switch self {
        case .markdown: return ["md", "markdown", "mdown"]
        case .textile: return ["textile"]
        case .cooklang: return ["cook", "menu"]
        }
    }

    /// Oliver's conformance wall for this frontend (docs/CAPABILITIES.md).
    var conformanceNote: String {
        switch self {
        case .markdown:
            return "CommonMark 0.31.2 — 652/652 examples byte-for-byte"
        case .textile:
            return "Textile fixture wall — fully green (TEXTILE-PARITY.md)"
        case .cooklang:
            return "Canonical Cooklang corpus — 60/60 (docs/COOKLANG.md)"
        }
    }

    /// Whether the frontmatter pre-pass (shared Oliver `src/frontmatter.zig`)
    /// applies to this frontend. Cooklang treats YAML front matter as a raw
    /// boundary; Markdown/Textile can parse the bounded YAML/TOML subset.
    var supportsFrontmatter: Bool {
        true
    }

    // MARK: - Detection

    /// Picks a language from a file URL's extension first, then falls back
    /// to content sniffing. Content sniffing is advisory — the user can
    /// always override.
    static func detect(fileURL: URL?, contents: String) -> ComposeLanguage {
        if let fileURL {
            let ext = fileURL.pathExtension.lowercased()
            if let byExtension = allCases.first(where: { $0.fileExtensions.contains(ext) }) {
                return byExtension
            }
        }
        return sniff(contents) ?? .markdown
    }

    /// Advisory content sniffing, ordered by how unambiguous the signal is:
    /// Cooklang ingredient/cookware/timer tokens, then Textile signatures,
    /// then Markdown defaults. Returns nil when the buffer is ambiguous.
    static func sniff(_ contents: String) -> ComposeLanguage? {
        let head = contents.prefix(2000)

        if CooklangSignals.isCooklang(head) {
            return .cooklang
        }
        if TextileSignals.isTextile(head) {
            return .textile
        }
        if MarkdownSignals.isMarkdown(head) {
            return .markdown
        }
        return nil
    }
}

/// Signal patterns mirroring Oliver's frontends. These are *heuristics for
/// choosing a frontend*, deliberately a coarse subset of the real grammar —
/// the grammar itself lives in Oliver.
private enum MarkdownSignals {
    static func isMarkdown(_ text: Substring) -> Bool {
        lines(text).contains { line in
            line.hasPrefix("#")
                || line.hasPrefix("> ")
                || line.hasPrefix("```")
                || line.hasPrefix("~~~")
                || line.hasPrefix("- ")
                || line.hasPrefix("* ")
                || line.hasPrefix("1. ")
                || line.hasPrefix("|")
        }
    }
}

private enum TextileSignals {
    static func isTextile(_ text: Substring) -> Bool {
        lines(text).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("h1.")
                || trimmed.hasPrefix("h2.")
                || trimmed.hasPrefix("h3.")
                || trimmed.hasPrefix("h4.")
                || trimmed.hasPrefix("h5.")
                || trimmed.hasPrefix("h6.")
                || trimmed.hasPrefix("p.")
                || trimmed.hasPrefix("bq.")
                || trimmed.hasPrefix("bc.")
                || trimmed.hasPrefix("pre.")
                || trimmed.hasPrefix("fn")
                || trimmed.hasPrefix("* ")
                // NB: `# ` is deliberately absent — it collides with a
                // Markdown ATX heading (`# Title`); Textile ordered lists
                // are the weaker reading and lose the sniff.
                || trimmed.hasPrefix("|")
        }
    }
}

private enum CooklangSignals {
    static func isCooklang(_ text: Substring) -> Bool {
        lines(text).contains { line in
            (line.contains("@") && !line.hasPrefix("```"))
                || (line.hasPrefix("#") && !line.hasPrefix("# ") && !line.hasPrefix("##"))
                || line.hasPrefix("= ")
                || line.hasPrefix("--")
                || line.hasPrefix("> ")
                || line.hasPrefix("[-")
        }
    }
}

private func lines(_ text: Substring) -> [Substring] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
}
