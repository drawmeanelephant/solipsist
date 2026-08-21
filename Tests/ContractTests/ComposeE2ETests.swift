import Foundation
import XCTest

/// #211 polish(compose): E2E jump + Oliver flags parity.
/// Oliver is bundled (`scripts/embed-boris.sh:164`) — do not bundle a new one.
/// This file pins the contract: every previewOptions bool maps to a CLI flag,
/// and a diagnostic's span.start survives ComposeDocument → Oliver → NSRange.
final class ComposeE2ETests: XCTestCase {
    // MARK: - E2E jump: document → Oliver span → ComposeDiagnostic → NSRange

    func testE2EJumpCharacterIndexBecomesNSRange() throws {
        let text = """
        ---
        title: x
        ---

        Hello **world** with [[wikilink]] and -- stray {.

        More content here.
        """
        // Simulate an Oliver frontmatter diagnostic at span 0..4 (probe shape)
        let oliverJSON = #"[{"severity":"warning","code":"unclosed-frontmatter","line":1,"column":1,"span":{"start":0,"end":4},"message":"front matter fence `---` never closed"}]"#
        let oliverDiagnostics = OliverRenderer.decodeDiagnostics(from: oliverJSON)
        XCTAssertEqual(oliverDiagnostics.count, 1)
        let mapped = OliverRenderService.composeDiagnostics(from: oliverDiagnostics)
        XCTAssertEqual(mapped.count, 1)
        let diag = try XCTUnwrap(mapped.first)
        XCTAssertEqual(diag.characterIndex, 0)
        XCTAssertEqual(diag.line, 1)
        // The editor jumps via ComposeEditorView.characterIndex(for:in:)
        // Replicate its clamping: min(max(index,0), utf16.count)
        let clamped = clampedCharacterIndex(diag.characterIndex, in: text)
        XCTAssertEqual(clamped, 0)
        let nsRange = NSRange(location: clamped ?? 0, length: 0)
        XCTAssertEqual(nsRange.location, 0)
        // The range is valid for the buffer
        let nsText = text as NSString
        XCTAssertLessThanOrEqual(nsRange.upperBound, nsText.length)
    }

    func testE2EJumpCooklangSpan() throws {
        let text = "Add @salt{1%tsp and ~dough{10%minutes}."
        let json = #"[{"severity":"warning","code":"unclosed-braces","line":1,"column":12,"span":{"start":11,"end":12},"message":"unclosed `{`"}]"#
        let oliver = OliverRenderer.decodeDiagnostics(from: json)
        let mapped = OliverRenderService.composeDiagnostics(from: oliver)
        XCTAssertEqual(mapped.first?.characterIndex, 11)
        let clamped = clampedCharacterIndex(mapped.first?.characterIndex, in: text)
        XCTAssertEqual(clamped, 11)
        let nsRange = NSRange(location: try XCTUnwrap(clamped), length: 0)
        XCTAssertTrue(nsRange.location < (text as NSString).length)
    }

    func testCharacterIndexClampingBeyondBuffer() {
        let text = "short"
        // Index beyond buffer clamps to utf16.count (5)
        XCTAssertEqual(clampedCharacterIndex(999, in: text), 5)
        XCTAssertEqual(clampedCharacterIndex(-10, in: text), 0)
        XCTAssertNil(clampedCharacterIndex(nil, in: text))
        // Line fallback when characterIndex is nil
        XCTAssertEqual(characterIndexViaLine(line: 1, in: text), 0)
        XCTAssertEqual(characterIndexViaLine(line: 2, in: "a\nb\nc"), 2)
        XCTAssertNil(characterIndexViaLine(line: 99, in: text))
    }

    func testComposeDiagnosticFromOliverPreservesSeverity() {
        let errors = OliverRenderer.decodeDiagnostics(from: #"[{"severity":"error","code":"future","span":{"start":5,"end":10},"message":"boom","line":2}]"#)
        let mapped = OliverRenderService.composeDiagnostics(from: errors)
        XCTAssertEqual(mapped.first?.severity, .error)
        XCTAssertEqual(mapped.first?.characterIndex, 5)
        let warnings = OliverRenderer.decodeDiagnostics(from: #"[{"severity":"warning","code":"w","span":{"start":1,"end":2},"message":"hi"}]"#)
        let mappedW = OliverRenderService.composeDiagnostics(from: warnings)
        XCTAssertEqual(mappedW.first?.severity, .warning)
    }

    // MARK: - Oliver flags parity: every previewOptions bool maps to a CLI flag

    // swiftlint:disable:next function_body_length
    func testEveryPreviewOptionBoolMapsToCLI() {
        // Start from defaults -> bare command
        let bare = OliverRenderOptions().arguments(frontend: .markdown)
        XCTAssertEqual(bare, ["render", "--from", "markdown"])

        // Each MarkupRenderOptions bool flips exactly one Oliver flag.
        // We test via OliverRenderService.engineOptions -> OliverRenderOptions.arguments
        var options = MarkupRenderOptions()

        options.wikilinks = true
        XCTAssertTrue(engineArgs(options).contains("--wikilinks"))
        options.wikilinks = false

        options.callouts = true
        XCTAssertTrue(engineArgs(options).contains("--callouts"))
        options.callouts = false

        options.smartypants = true
        XCTAssertTrue(engineArgs(options).contains("--smartypants"))
        options.smartypants = false

        options.footnotes = true
        XCTAssertTrue(engineArgs(options).contains("--footnotes"))
        options.footnotes = false

        options.definitionLists = true
        XCTAssertTrue(engineArgs(options).contains("--definition-lists"))
        options.definitionLists = false

        options.headingAttributes = true
        XCTAssertTrue(engineArgs(options).contains("--heading-attributes"))
        options.headingAttributes = false

        options.strikethrough = true
        XCTAssertTrue(engineArgs(options).contains("--strikethrough"))
        options.strikethrough = false

        options.headingIDs = true
        XCTAssertTrue(engineArgs(options).contains("--heading-ids"))
        options.headingIDs = false

        options.taskLists = true
        XCTAssertTrue(engineArgs(options).contains("--task-lists"))
        options.taskLists = false

        // Non-bool enums
        options.rawHTML = .escaped
        XCTAssertTrue(engineArgs(options).contains("--raw-html"))
        XCTAssertTrue(engineArgs(options).contains("escaped"))
        options.rawHTML = .rejected
        XCTAssertTrue(engineArgs(options).contains("rejected"))
        options.rawHTML = .allowed
        XCTAssertFalse(engineArgs(options).contains("--raw-html"))

        options.frontmatter = .yaml
        XCTAssertTrue(engineArgs(options).contains("--frontmatter"))
        XCTAssertTrue(engineArgs(options).contains("yaml"))
        options.frontmatter = .toml
        XCTAssertTrue(engineArgs(options).contains("toml"))
        options.frontmatter = .none
        XCTAssertFalse(engineArgs(options).contains("--frontmatter"))

        options.profile = .xhtml
        XCTAssertTrue(engineArgs(options).contains("--to"))
        XCTAssertTrue(engineArgs(options).contains("xhtml"))
        options.profile = .html
        XCTAssertFalse(engineArgs(options).contains("--to"))

        // Diagnostics flag (OliverRenderOptions, always true via service, but map is explicit)
        var engineDirect = OliverRenderOptions()
        engineDirect.diagnostics = true
        XCTAssertTrue(engineDirect.arguments(frontend: .markdown).contains("--diagnostics"))
        XCTAssertTrue(engineDirect.arguments(frontend: .markdown).contains("json"))
    }

    func testEngineFlagsAreAdditive() {
        var options = MarkupRenderOptions()
        options.wikilinks = true
        options.callouts = true
        options.footnotes = true
        let args = engineArgs(options)
        XCTAssertTrue(args.contains("--wikilinks"))
        XCTAssertTrue(args.contains("--callouts"))
        XCTAssertTrue(args.contains("--footnotes"))
        XCTAssertEqual(args.first, "render")
    }

    // MARK: - Highlighter incremental path perf bound (LATER-3.2)

    func testHighlighterIncrementalRepaintIsBounded() {
        // 20k char buffer with a frontmatter fence and many headings.
        let big = String(repeating: "# Heading\n\nSome **bold** and `code` with [[wiki]]\n\n", count: 400)
        let storage = NSMutableAttributedString(
            string: big,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor]
        )
        let range = NSRange(location: 100, length: 80)
        let start = CFAbsoluteTimeGetCurrent()
        ComposeHighlighter.repaint(big, language: .markdown, in: range, storage: storage)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        // Should be well under 1s even for a large buffer; the incremental path
        // only paints the intersection, not the whole buffer layout.
        XCTAssertLessThan(elapsed, 0.5, "repaint over small range took \(elapsed)s, should be bounded")
        // The painted range should not equal the whole-buffer paint for outside offsets.
        let outside = NSRange(location: 0, length: 2)
        XCTAssertNotEqual(
            storage.attribute(.foregroundColor, at: outside.location, effectiveRange: nil) as? NSColor,
            NSColor.systemRed
        )
    }

    func testHighlighterChangedRangeIsDeterministic() {
        let old = "hello world"
        let new = "hello big world"
        let firstRange = ComposeHighlighter.changedRange(old: old, new: new)
        let secondRange = ComposeHighlighter.changedRange(old: old, new: new)
        XCTAssertEqual(firstRange, secondRange)
        XCTAssertEqual(firstRange.location, 6)
        XCTAssertEqual(firstRange.length, 4)
        XCTAssertTrue(firstRange.upperBound <= (new as NSString).length)
    }

    // MARK: - Helpers (mirror ComposeEditorView's private logic for test)

    private func clampedCharacterIndex(_ index: Int?, in text: String) -> Int? {
        guard let index else { return nil }
        return min(max(index, 0), (text as NSString).length)
    }

    private func characterIndexViaLine(line: Int?, in text: String) -> Int? {
        guard let line, line >= 1 else { return nil }
        let textNSString = text as NSString
        var found: Int?
        var current = 1
        textNSString.enumerateSubstrings(in: NSRange(location: 0, length: textNSString.length), options: [.byLines, .substringNotRequired]) { _, range, _, stop in
            if current == line {
                found = range.location
                stop.pointee = true
            }
            current += 1
        }
        return found
    }

    private func engineArgs(_ options: MarkupRenderOptions) -> [String] {
        OliverRenderService.engineOptions(options).arguments(frontend: .markdown)
    }
}
