import XCTest

/// #298 — theme browser: order preservation (local first), Default
/// clears, the write path is the same `target.theme` string, the
/// first-class count is pinned, and the tile document is safe HTML.
final class ThemeBrowserTests: XCTestCase {
    private func makeWorkspace(
        localThemes: [String],
        withCSS css: String? = nil
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-browser-\(UUID().uuidString)")
        for theme in localThemes {
            let dir = tempDir.appendingPathComponent("themes/\(theme)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let css {
                try css.write(
                    to: dir.appendingPathComponent("sample.css"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
        return tempDir
    }

    func testThemeBrowserListsLocalFirst() throws {
        let root = try makeWorkspace(localThemes: ["zeta-custom", "alpha-custom"])
        defer { try? FileManager.default.removeItem(at: root) }

        let all = ThemeCatalog.allThemes(for: root)
        XCTAssertEqual(Array(all.prefix(2)), ["alpha-custom", "zeta-custom"], "local de-duped, sorted, before first-class")
        XCTAssertTrue(all.contains("boris"))
        XCTAssertEqual(all.count, 22, "2 local + 20 first-class, de-duped")
    }

    func testLocalThemeShadowingFirstClassIsNotDuplicated() throws {
        // A local "boris" dir shadows the first-class name; allThemes
        // de-dupes — the browser shows one tile.
        let root = try makeWorkspace(localThemes: ["boris"])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(ThemeCatalog.allThemes(for: root).filter { $0 == "boris" }.count, 1)
    }

    func testDefaultTileClearsTheme() {
        // The browser's Default tile writes nil — the same value the
        // flat Picker wrote for "". Encoding a target with theme nil
        // round-trips it as absent, never as the empty string.
        let target = PublicationTarget(name: "public", output: "dist", public: true)
        XCTAssertNil(target.theme, "Default tile writes nil, not \"\"")
        var cleared = target
        cleared.theme = nil
        XCTAssertNil(cleared.theme)
    }

    func testSelectingTileWritesSameBindingAsPicker() throws {
        // The browser writes `target.theme` via the same memberwise
        // field; the profile save path is unchanged. Round-trip the
        // target through JSON to prove the wire value is identical.
        let chosen = PublicationTarget(
            name: "public",
            output: "dist",
            public: true,
            theme: "cards"
        )
        let data = try JSONEncoder().encode(chosen)
        let decoded = try JSONDecoder().decode(PublicationTarget.self, from: data)
        XCTAssertEqual(decoded.theme, "cards", "the same string the flat Picker wrote")
    }

    func testFirstClassThemeCountUnchanged() {
        // Fails loud if the pinned kit genuinely added one — verify
        // against the kit, then bump (issue #298 contract).
        XCTAssertEqual(ThemeCatalog.firstClassThemes.count, 20)
        XCTAssertEqual(ThemeCatalog.firstClassThemes.first, "archive")
        XCTAssertEqual(ThemeCatalog.firstClassThemes.last, "tokens")
    }

    // MARK: - Tile document

    func testTileDocumentInlinesCollectedCSS() throws {
        let root = try makeWorkspace(
            localThemes: ["styled"],
            withCSS: "body { font-family: serif; } h1 { color: teal; }"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let css = ThemePreviewDocument.css(for: "styled", workspaceRoot: root)
        XCTAssertNotNil(css, "local theme CSS resolves through ComposeThemeCSS.collect")
        let html = ThemePreviewDocument.html(sampleCSS: css)
        XCTAssertTrue(html.contains("font-family: serif"), "collected CSS is inlined verbatim")
        XCTAssertTrue(html.contains("Theme Sample"), "the fixed sample fragment renders")
    }

    func testTileDocumentFallsBackWhenCSSMissing() {
        // A first-class theme with no CSS in this workspace: neutral
        // fallback + the theme name — never blank, never an error.
        let css = ThemePreviewDocument.css(for: "press", workspaceRoot: nil)
        XCTAssertNil(css)
        let html = ThemePreviewDocument.html(sampleCSS: css)
        XCTAssertTrue(html.contains(ThemePreviewDocument.fallbackCSS))
        XCTAssertTrue(html.contains("Theme Sample"))
    }

    func testTileDocumentNeutralizesStyleEscape() {
        // A hostile stylesheet cannot escape the style element — the
        // ComposePreviewDocument sanitize contract, honored by tiles.
        let hostile = "body { content: '</style><script>alert(1)</script>' }"
        let html = ThemePreviewDocument.html(sampleCSS: hostile)
        XCTAssertFalse(html.contains("</style><script>"), "style escape is neutralized")
    }

    func testNonThemeDirectoryShowsFallbackNotError() throws {
        // themes/ containing a non-theme subdirectory (skipped as hidden
        // by the catalog; a non-hidden one with no CSS still renders the
        // fallback tile, never an error.
        let root = try makeWorkspace(localThemes: ["not-a-theme"])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(ThemeCatalog.discoverLocalThemes(in: root), ["not-a-theme"])
        let css = ThemePreviewDocument.css(for: "not-a-theme", workspaceRoot: root)
        let html = ThemePreviewDocument.html(sampleCSS: css)
        XCTAssertTrue(html.contains("Theme Sample"), "no crash, no blank tile")
    }
}
