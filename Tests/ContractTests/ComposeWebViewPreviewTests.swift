import WebKit
import XCTest

/// #230 — the compose preview renders through a sandboxed WKWebView with
/// the theme CSS inlined. The document assembly, theme resolution, and
/// navigation policy are pure and pinned here; one integration test drives
/// a real web view to prove the sandbox cancels link navigation.
final class ComposeWebViewPreviewTests: XCTestCase {
    // MARK: - Document assembly (testPreviewFragmentWrapsHTML)

    func testPreviewFragmentWrapsHTML() {
        let html = ComposePreviewDocument.html(
            fragment: "<p>hello <strong>world</strong></p>",
            themeCSS: "body { color: red; }"
        )
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("body { color: red; }"))
        XCTAssertTrue(html.contains("<body>\n<p>hello <strong>world</strong></p>\n</body>"))
    }

    func testPreviewThemeCSSFallback() {
        let withoutTheme = ComposePreviewDocument.html(fragment: "<p>x</p>", themeCSS: nil)
        let emptyTheme = ComposePreviewDocument.html(fragment: "<p>x</p>", themeCSS: "")
        for html in [withoutTheme, emptyTheme] {
            XCTAssertTrue(html.contains(ComposePreviewDocument.fallbackCSS))
            XCTAssertFalse(html.contains("<style>\n\n</style>"))
        }
        // A real theme replaces the fallback entirely.
        let themed = ComposePreviewDocument.html(fragment: "<p>x</p>", themeCSS: "p { margin: 0; }")
        XCTAssertFalse(themed.contains(ComposePreviewDocument.fallbackCSS))
        XCTAssertTrue(themed.contains("p { margin: 0; }"))
    }

    /// Dark mode (nice-to-have): the document declares its color scheme so
    /// WebKit follows the system appearance, and the fallback stylesheet
    /// uses appearance-adaptive colors. Theme CSS is never rewritten.
    func testFallbackStyleSheetHonorsDarkMode() {
        let html = ComposePreviewDocument.html(fragment: "<p>x</p>", themeCSS: nil)
        XCTAssertTrue(html.contains(#"<meta name="color-scheme" content="light dark">"#))
        XCTAssertTrue(ComposePreviewDocument.fallbackCSS.contains("color-scheme: light dark"))
        XCTAssertTrue(ComposePreviewDocument.fallbackCSS.contains("canvastext"))
        XCTAssertTrue(ComposePreviewDocument.fallbackCSS.contains("canvas;"))
    }

    func testStyleCloseGuardCannotEscape() {
        let hostile = "a::after { content: \"</style><script>alert(1)</script>\"; }"
        let html = ComposePreviewDocument.html(fragment: "<p>x</p>", themeCSS: hostile)
        XCTAssertFalse(html.contains("</style><script>alert(1)</script>"))
        XCTAssertTrue(html.contains("<script>alert(1)</script>".replacingOccurrences(of: "</", with: "<\\/")))
    }

    // MARK: - Theme resolution

    func testPreferredThemeTargetSelection() {
        func target(_ name: String, theme: String?, isPublic: Bool? = nil) -> PublicationTarget {
            PublicationTarget(name: name, output: "dist/\(name)", public: isPublic, theme: theme)
        }

        // No targets / no themes → nothing.
        XCTAssertNil(ComposeThemeCSS.preferredThemePath(in: nil))
        XCTAssertNil(ComposeThemeCSS.preferredThemePath(in: []))
        XCTAssertNil(ComposeThemeCSS.preferredThemePath(in: [target("a", theme: nil)]))

        // First public target with a theme wins over earlier private ones.
        let publicWins = ComposeThemeCSS.preferredThemePath(in: [
            target("private", theme: "themes/one"),
            target("public", theme: "themes/two", isPublic: true),
        ])
        XCTAssertEqual(publicWins, "themes/two")

        // Without a public flag, the first themed target wins.
        XCTAssertEqual(
            ComposeThemeCSS.preferredThemePath(in: [
                target("first", theme: "themes/first"),
                target("second", theme: "themes/second"),
            ]),
            "themes/first"
        )
    }

    func testThemeCSSCollectedFromWorkspaceThemes() throws {
        let root = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let css = try XCTUnwrap(
            ComposeThemeCSS.collect(workspaceRoot: root, targets: [
                PublicationTarget(name: "public", output: "dist", public: true, theme: "themes/boris"),
            ])
        )
        XCTAssertTrue(css.contains("/* base */"))
        XCTAssertTrue(css.contains("/* print */"))
        // Deterministic order: path-sorted (assets before print.css).
        let baseRange = try XCTUnwrap(css.range(of: "/* base */"))
        let printRange = try XCTUnwrap(css.range(of: "/* print */"))
        XCTAssertLessThan(baseRange.lowerBound, printRange.lowerBound)
    }

    func testThemeCSSMissingDirectoryFallsBackToNil() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("compose-theme-missing-\(UUID().uuidString)")
        XCTAssertNil(
            ComposeThemeCSS.collect(workspaceRoot: root, targets: [
                PublicationTarget(name: "t", output: "dist", theme: "themes/nope"),
            ])
        )
        // And no theme at all.
        XCTAssertNil(ComposeThemeCSS.collect(workspaceRoot: root, targets: nil))
    }

    // MARK: - Sandbox policy

    func testSandboxAllowsOnlyInitialMainFrameLoad() {
        XCTAssertTrue(ComposePreviewSandbox.allows(initialLoadPending: true, isMainFrame: true))
        // Everything after the initial load is cancelled…
        XCTAssertFalse(ComposePreviewSandbox.allows(initialLoadPending: false, isMainFrame: true))
        // …and sub-frames are never allowed, even on the first pass.
        XCTAssertFalse(ComposePreviewSandbox.allows(initialLoadPending: true, isMainFrame: false))
        XCTAssertFalse(ComposePreviewSandbox.allows(initialLoadPending: false, isMainFrame: false))
    }

    // MARK: - Integration: a real web view honors the policy

    @MainActor
    func testWebViewRendersFragmentAndBlocksLinkNavigation() async throws {
        let document = ComposePreviewDocument.html(
            fragment: "<p id=\"p\">Hello preview <a id=\"l\" href=\"https://example.invalid/escape\">link</a></p>",
            themeCSS: "#p { color: navy; }"
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        let coordinator = ComposePreviewCoordinator()
        webView.navigationDelegate = coordinator
        coordinator.load(document, in: webView)

        // Rendered: the fragment's text made it into the live DOM.
        try await waitUntil("fragment to render") {
            let text = try await webView.evaluateJavaScript("document.body.innerText") as? String
            return text?.contains("Hello preview") == true
        }

        // Click the link: the sandbox must cancel the main-frame navigation,
        // so the location never leaves the about: origin of loadHTMLString.
        _ = try await webView.evaluateJavaScript("document.getElementById('l').click()")
        try await Task.sleep(for: .milliseconds(400))
        let rawLocation = try await webView.evaluateJavaScript("window.location.href")
        let location = try XCTUnwrap(rawLocation as? String)
        XCTAssertTrue(location.hasPrefix("about:"), "navigation escaped the pane: \(location)")
    }

    // MARK: - Helpers

    /// `<root>/themes/boris/assets/css/base.css` + `<root>/themes/boris/print.css`.
    private func temporaryWorkspace() throws -> URL {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("compose-theme-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let assets = root.appendingPathComponent("themes/boris/assets/css", isDirectory: true)
        try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
        try "/* base */".write(to: assets.appendingPathComponent("base.css"), atomically: true, encoding: .utf8)
        try "/* print */".write(to: root.appendingPathComponent("themes/boris/print.css"), atomically: true, encoding: .utf8)
        return root
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout seconds: TimeInterval = 5,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for \(description)")
    }
}
