import XCTest

@MainActor
final class ComposeDocumentTests: XCTestCase {
    // MARK: - Frontmatter boundary (Oliver's sniff-then-strip rule)

    func testYamlFrontmatterDetected() {
        let doc = ComposeDocument(text: "---\ntitle: Hello\n---\n\nBody")
        guard let frontmatter = doc.frontmatter else {
            return XCTFail("expected YAML frontmatter")
        }
        XCTAssertEqual(frontmatter.kind, .yaml)
        XCTAssertEqual(frontmatter.payloadString, "title: Hello")
    }

    func testTomlFrontmatterDetected() {
        let doc = ComposeDocument(text: "+++\ntitle = \"Hello\"\n+++\n\nBody")
        guard let frontmatter = doc.frontmatter else {
            return XCTFail("expected TOML frontmatter")
        }
        XCTAssertEqual(frontmatter.kind, .toml)
        XCTAssertEqual(frontmatter.payloadString, "title = \"Hello\"")
    }

    func testEmptyFrontmatterPayload() {
        let doc = ComposeDocument(text: "---\n---\n\nBody")
        guard let frontmatter = doc.frontmatter else {
            return XCTFail("expected frontmatter")
        }
        XCTAssertEqual(frontmatter.payloadString, "")
    }

    func testUnclosedOpenerIsNotFrontmatter() {
        // Oliver: an unclosed opener passes through unchanged with an
        // `unclosed-frontmatter` diagnostic — never treated as frontmatter.
        let doc = ComposeDocument(text: "---\ntitle: Never closes\n\nBody")
        XCTAssertNil(doc.frontmatter)
    }

    func testFenceNotAtIndexZeroIsNotFrontmatter() {
        let doc = ComposeDocument(text: "Body first\n---\ntitle: No\n---\n")
        XCTAssertNil(doc.frontmatter)
    }

    func testFrontmatterRangeCoversBothFences() {
        let doc = ComposeDocument(text: "---\na: 1\n---\nBody")
        guard let frontmatter = doc.frontmatter else {
            return XCTFail("expected frontmatter")
        }
        XCTAssertEqual(String(doc.text[frontmatter.range]), "---\na: 1\n---")
    }

    // MARK: - Language pinning

    func testLanguageAutoDetectsUntilPinned() {
        let doc = ComposeDocument(text: "")
        XCTAssertEqual(doc.language, .markdown)

        doc.text = "@salt{1%tsp} into the bowl."
        XCTAssertEqual(doc.language, .cooklang)

        // Pinning (picker choice) survives later edits.
        doc.language = .textile
        doc.text = "# A heading that would sniff markdown"
        XCTAssertEqual(doc.language, .textile, "explicit choice must not be overridden")
    }

    func testExplicitLanguageInInitIsPinned() {
        let doc = ComposeDocument(text: "@salt", language: .textile)
        doc.text = "# heading"
        XCTAssertEqual(doc.language, .textile)
    }

    // MARK: - Dirty flag and explicit save

    func testDirtyFlagTracksEdits() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-doc-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = ComposeDocument(text: "Hello", fileURL: url)
        XCTAssertFalse(doc.isDirty)

        doc.text = "Hello, world."
        XCTAssertTrue(doc.isDirty)

        XCTAssertTrue(try doc.save())
        XCTAssertFalse(doc.isDirty)

        // Nothing to save when clean.
        XCTAssertFalse(try doc.save())

        let reloaded = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(reloaded, "Hello, world.")
    }

    func testSaveRequiresExplicitURL() throws {
        let doc = ComposeDocument(text: "Never written")
        XCTAssertFalse(try doc.save(), "save without a URL must be a no-op")
    }

    func testUntitledDraftStartsDirtyAndSavesWithoutAnotherEdit() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-draft-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }

        let draft = StagedPostDraft(title: "Field Notes", body: "Review this draft.", origin: .menu)
        let text = PostDraftAssembly.markdown(for: draft)
        let doc = ComposeDocument(text: text, language: .markdown)
        XCTAssertTrue(doc.isDirty, "staging is not a save")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        doc.fileURL = url
        XCTAssertTrue(try doc.save(), "an untouched draft must be saveable")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
        XCTAssertFalse(doc.isDirty)
    }

    func testSaveDoesNotOverwriteAnExternalEdit() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-conflict-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Original".write(to: url, atomically: true, encoding: .utf8)

        let doc = ComposeDocument()
        try doc.load(from: url)
        doc.text = "Native compose edit"
        try "Boris editor edit".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try doc.save())
        XCTAssertTrue(doc.isDirty)
        XCTAssertEqual(doc.text, "Native compose edit")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Boris editor edit")
    }

    func testRevertingToLoadedTextClearsDirtyState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-revert-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "Original".write(to: url, atomically: true, encoding: .utf8)
        let doc = ComposeDocument()
        try doc.load(from: url)
        doc.text = "Changed"
        XCTAssertTrue(doc.isDirty)
        doc.text = "Original"
        XCTAssertFalse(doc.isDirty, "undoing the last edit must restore the clean state")
        XCTAssertFalse(try doc.save())
    }

    func testSuccessfulSaveUpdatesTheConflictBaseline() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-save-baseline-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = ComposeDocument(text: "First save")
        doc.fileURL = url
        XCTAssertTrue(try doc.save())
        doc.text = "Second save"
        XCTAssertTrue(try doc.save())
        try "External save".write(to: url, atomically: true, encoding: .utf8)
        doc.text = "Third save"
        XCTAssertThrowsError(try doc.save())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "External save")
    }

    func testDeletedFileIsNotSilentlyRecreated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-deleted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("note.md")
        try "Original".write(to: url, atomically: true, encoding: .utf8)
        let doc = ComposeDocument()
        try doc.load(from: url)
        doc.text = "Changed"
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try doc.save())
        XCTAssertTrue(doc.isDirty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFailedLoadPreservesTheCurrentBufferAndFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-missing-\(UUID().uuidString).md")
        let originalURL = url.appendingPathExtension("original")
        let doc = ComposeDocument(text: "Original", fileURL: originalURL)
        doc.text = "Unsaved changes"
        XCTAssertThrowsError(try doc.load(from: url))
        XCTAssertEqual(doc.fileURL, originalURL)
        XCTAssertEqual(doc.text, "Unsaved changes")
        XCTAssertTrue(doc.isDirty)
    }

    func testLoadSyncsBufferAndClearsDirty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-load-\(UUID().uuidString).cook")
        defer { try? FileManager.default.removeItem(at: url) }
        try "@salt{1}".write(to: url, atomically: true, encoding: .utf8)

        let doc = ComposeDocument()
        try doc.load(from: url)
        XCTAssertEqual(doc.text, "@salt{1}")
        XCTAssertEqual(doc.language, .cooklang)
        XCTAssertFalse(doc.isDirty)
    }

    func testStatusTextSummarizes() {
        let doc = ComposeDocument(text: "---\na: 1\n---\nBody", fileURL: URL(fileURLWithPath: "/tmp/note.md"))
        let status = doc.statusText
        XCTAssertTrue(status.contains("note.md"))
        XCTAssertTrue(status.contains("Markdown"))
        XCTAssertTrue(status.contains("front matter: yaml"))
    }
}
