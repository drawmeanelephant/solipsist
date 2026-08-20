import XCTest

final class CompanionURLTests: XCTestCase {
    // MARK: - EditorURL Tests

    func testEditorURLValidWithPrefix() throws {
        let input = "BORIS_EDITOR_URL=http://127.0.0.1:49152/#token=0123456789abcdef"
        let url = try EditorURL.parse(input)
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 49152)
        XCTAssertEqual(url.fragment, "token=0123456789abcdef")
    }

    func testEditorURLValidRawAndWhitespace() throws {
        let input = "  \n  http://localhost:8080/#token=feedface  \t  "
        let url = try EditorURL.parse(input)
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, 8080)
        XCTAssertEqual(url.fragment, "token=feedface")
    }

    func testEditorURLIPv6Loopback() throws {
        let input = "http://[::1]:9000/#token=abcd1234"
        let url = try EditorURL.parse(input)
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "::1")
        XCTAssertEqual(url.port, 9000)
    }

    func testEditorURLEmptyInputs() {
        XCTAssertThrowsError(try EditorURL.parse("")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .empty)
        }
        XCTAssertThrowsError(try EditorURL.parse("   \n\t  ")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .empty)
        }
        XCTAssertThrowsError(try EditorURL.parse("BORIS_EDITOR_URL=")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .empty)
        }
    }

    func testEditorURLInvalidURLs() {
        XCTAssertThrowsError(try EditorURL.parse("not a valid url :// @")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .invalidURL)
        }
        XCTAssertThrowsError(try EditorURL.parse("https://127.0.0.1:8080/#token=abcd")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .invalidURL)
        }
        XCTAssertThrowsError(try EditorURL.parse("ws://127.0.0.1:8080/#token=abcd")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .invalidURL)
        }
    }

    func testEditorURLNonLoopbackHosts() {
        XCTAssertThrowsError(try EditorURL.parse("http://example.com:8080/#token=abcd")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .notLoopback)
        }
        XCTAssertThrowsError(try EditorURL.parse("http://192.168.1.100:8080/#token=abcd")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .notLoopback)
        }
        XCTAssertThrowsError(try EditorURL.parse("http://10.0.0.1:8080/#token=abcd")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .notLoopback)
        }
    }

    func testEditorURLTokenValidation() {
        // Missing fragment
        XCTAssertThrowsError(try EditorURL.parse("http://127.0.0.1:8080/")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .missingTokenFragment)
        }
        // Wrong fragment prefix
        XCTAssertThrowsError(try EditorURL.parse("http://127.0.0.1:8080/#key=abcd")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .missingTokenFragment)
        }
        // Empty token
        XCTAssertThrowsError(try EditorURL.parse("http://127.0.0.1:8080/#token=")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .invalidTokenHex)
        }
        // Non-hex token
        XCTAssertThrowsError(try EditorURL.parse("http://127.0.0.1:8080/#token=ghijklm")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .invalidTokenHex)
        }
        XCTAssertThrowsError(try EditorURL.parse("http://127.0.0.1:8080/#token=123-abc")) { error in
            XCTAssertEqual(error as? EditorURL.ParseError, .invalidTokenHex)
        }
    }

    func testEditorURLAcceptsExtraFragmentKeys() throws {
        let input = "http://127.0.0.1:49152/#token=0123456789abcdef&open=content/index.md"
        let url = try EditorURL.parse(input)
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.fragment, "token=0123456789abcdef&open=content/index.md")
    }

    func testEditorURLTokenNeedNotBeFirstFragmentKey() throws {
        let input = "http://127.0.0.1:8080/#open=content/index.md&token=feedface"
        let url = try EditorURL.parse(input)
        XCTAssertEqual(url.host, "127.0.0.1")
    }

    func testEditorURLOpeningAppendsAuthorOwnedPath() throws {
        let base = try EditorURL.parse("http://127.0.0.1:8080/#token=abcd")
        let opened = EditorURL.opening(base, sourcePath: "guides/getting-started.md")
        XCTAssertEqual(opened.fragment, "token=abcd&open=content/guides/getting-started.md")
        let parsed = try EditorURL.parse(opened.absoluteString)
        XCTAssertEqual(parsed.fragment, opened.fragment)
    }

    func testEditorURLOpeningReplacesExistingOpen() throws {
        let base = try EditorURL.parse("http://127.0.0.1:8080/#token=abcd&open=content/old.md")
        let opened = EditorURL.opening(base, sourcePath: "index.md")
        XCTAssertEqual(opened.fragment, "token=abcd&open=content/index.md")
    }

    func testEditorURLOpeningLeavesInvalidSourcePathAlone() throws {
        let base = try EditorURL.parse("http://127.0.0.1:8080/#token=abcd")
        XCTAssertEqual(EditorURL.opening(base, sourcePath: nil).fragment, "token=abcd")
        XCTAssertEqual(EditorURL.opening(base, sourcePath: "").fragment, "token=abcd")
        XCTAssertEqual(EditorURL.opening(base, sourcePath: "../secret").fragment, "token=abcd")
        XCTAssertEqual(EditorURL.opening(base, sourcePath: "/etc/passwd").fragment, "token=abcd")
        XCTAssertEqual(EditorURL.opening(base, sourcePath: "content/../secret").fragment, "token=abcd")
    }

    func testEditorURLProjectPathFromGraphSourcePath() {
        XCTAssertEqual(EditorURL.projectPath(fromSourcePath: "index.md"), "content/index.md")
        XCTAssertEqual(EditorURL.projectPath(fromSourcePath: "guides/getting-started.md"), "content/guides/getting-started.md")
        XCTAssertEqual(EditorURL.projectPath(fromSourcePath: "content/index.md"), "content/index.md")
        XCTAssertEqual(EditorURL.projectPath(fromSourcePath: "themes/boris/layouts/main.html"), "themes/boris/layouts/main.html")
        XCTAssertEqual(EditorURL.projectPath(fromSourcePath: "boris.json"), "boris.json")
        XCTAssertEqual(EditorURL.projectPath(fromSourcePath: "dist/index.html"), "content/dist/index.html")
        XCTAssertNil(EditorURL.projectPath(fromSourcePath: nil))
        XCTAssertNil(EditorURL.projectPath(fromSourcePath: "  "))
        XCTAssertNil(EditorURL.projectPath(fromSourcePath: "../secret"))
        XCTAssertNil(EditorURL.projectPath(fromSourcePath: "content/../secret"))
        XCTAssertNil(EditorURL.projectPath(fromSourcePath: "/content/index.md"))
        XCTAssertNil(EditorURL.projectPath(fromSourcePath: "/etc/passwd"))
    }

    func testEditorURLMaskedDisplayString() throws {
        let url = try EditorURL.parse("http://127.0.0.1:8080/#token=12345678abcdef&open=content/index.md")
        let masked = EditorURL.maskedDisplayString(for: url)
        XCTAssertFalse(masked.contains("12345678abcdef"))
        XCTAssertTrue(masked.contains("token=••••••••"))
        XCTAssertTrue(masked.contains("open=content/index.md"))
    }

    // MARK: - PreviewURL Tests

    func testPreviewURLLoopbackRules() throws {
        let ipv4 = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/__boris/"))
        let localhost = try XCTUnwrap(URL(string: "http://localhost:3000/"))
        let ipv6 = try XCTUnwrap(URL(string: "http://[::1]:9000/preview"))

        XCTAssertTrue(PreviewURL.isLoopback(ipv4))
        XCTAssertTrue(PreviewURL.isLoopback(localhost))
        XCTAssertTrue(PreviewURL.isLoopback(ipv6))
        XCTAssertTrue(PreviewURL.isAllowed(ipv4))
        XCTAssertTrue(PreviewURL.isAllowed(localhost))
        XCTAssertTrue(PreviewURL.isAllowed(ipv6))
    }

    func testPreviewURLBlankAllowed() throws {
        let blank = try XCTUnwrap(URL(string: "about:blank"))
        XCTAssertTrue(PreviewURL.isAllowed(blank))
        XCTAssertFalse(PreviewURL.isLoopback(blank))
    }

    func testPreviewURLNonLoopbackRejected() throws {
        let remote = try XCTUnwrap(URL(string: "http://example.com:8080/"))
        let lan = try XCTUnwrap(URL(string: "http://192.168.1.1:8080/"))
        let secure = try XCTUnwrap(URL(string: "https://127.0.0.1:8080/"))
        let file = try XCTUnwrap(URL(string: "file:///tmp/test.html"))

        XCTAssertFalse(PreviewURL.isLoopback(remote))
        XCTAssertFalse(PreviewURL.isAllowed(remote))
        XCTAssertFalse(PreviewURL.isLoopback(lan))
        XCTAssertFalse(PreviewURL.isAllowed(lan))
        XCTAssertFalse(PreviewURL.isLoopback(secure))
        XCTAssertFalse(PreviewURL.isAllowed(secure))
        XCTAssertFalse(PreviewURL.isLoopback(file))
        XCTAssertFalse(PreviewURL.isAllowed(file))
    }

    func testPreviewURLSiteOriginFromHelper() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/__boris/"))
        let origin = try XCTUnwrap(PreviewURL.siteOrigin(fromHelper: helper))
        XCTAssertEqual(origin.scheme, "http")
        XCTAssertEqual(origin.host, "127.0.0.1")
        XCTAssertEqual(origin.port, 8080)
        XCTAssertEqual(origin.path, "/")
        XCTAssertNil(origin.query)
        XCTAssertNil(origin.fragment)
    }

    func testPreviewURLSiteOriginWithoutTrailingSlash() throws {
        let helper = try XCTUnwrap(URL(string: "http://localhost:3000/__boris"))
        let origin = try XCTUnwrap(PreviewURL.siteOrigin(fromHelper: helper))
        XCTAssertEqual(origin.host, "localhost")
        XCTAssertEqual(origin.port, 3000)
        XCTAssertEqual(origin.path, "/")
    }

    func testPreviewURLSiteOriginStripsQueryAndFragment() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/__boris/?x=1#frag"))
        let origin = try XCTUnwrap(PreviewURL.siteOrigin(fromHelper: helper))
        XCTAssertEqual(origin.path, "/")
        XCTAssertNil(origin.query)
        XCTAssertNil(origin.fragment)
    }

    func testPreviewURLPageURLFromGraphIDs() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:49152/__boris/"))
        let index = try XCTUnwrap(PreviewURL.pageURL(helper: helper, pageID: "index"))
        XCTAssertEqual(index.absoluteString, "http://127.0.0.1:49152/index.html")
        let nested = try XCTUnwrap(PreviewURL.pageURL(helper: helper, pageID: "guides/getting-started"))
        XCTAssertEqual(nested.absoluteString, "http://127.0.0.1:49152/guides/getting-started.html")
        let cook = try XCTUnwrap(PreviewURL.pageURL(helper: helper, pageID: "recipe/soup"))
        XCTAssertEqual(cook.absoluteString, "http://127.0.0.1:49152/recipe/soup.html")
    }

    func testPreviewURLPageURLUsesGraphIDVerbatimNotSourcePathStemSwap() throws {
        // The letter URL is `/{GraphNode.id}.html` — the id is used
        // verbatim. A slashed or extension-bearing id must never be
        // derived from (or stem-swapped against) the page's sourcePath.
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:49152/__boris/"))
        let slashed = try XCTUnwrap(PreviewURL.pageURL(helper: helper, pageID: "recipe/soup"))
        XCTAssertEqual(slashed.absoluteString, "http://127.0.0.1:49152/recipe/soup.html")
        // A sourcePath-shaped id keeps its own prefix: no `content/` injection.
        let pathShaped = try XCTUnwrap(PreviewURL.pageURL(helper: helper, pageID: "content/recipe/soup"))
        XCTAssertEqual(pathShaped.absoluteString, "http://127.0.0.1:49152/content/recipe/soup.html")
        // An extension is appended, never swapped for `.html`.
        let withExtension = try XCTUnwrap(PreviewURL.pageURL(helper: helper, pageID: "recipe/soup.md"))
        XCTAssertEqual(withExtension.absoluteString, "http://127.0.0.1:49152/recipe/soup.md.html")
    }

    func testPreviewURLPageURLTrimsSlashes() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/__boris/"))
        let url = try XCTUnwrap(PreviewURL.pageURL(helper: helper, pageID: "/guides/getting-started/"))
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:8080/guides/getting-started.html")
    }

    func testPreviewURLPageURLRejectsEmptyID() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/__boris/"))
        XCTAssertNil(PreviewURL.pageURL(helper: helper, pageID: ""))
        XCTAssertNil(PreviewURL.pageURL(helper: helper, pageID: "///"))
    }

    func testPreviewURLSiteOriginRejectsNonLoopback() throws {
        let remote = try XCTUnwrap(URL(string: "http://example.com/__boris/"))
        XCTAssertNil(PreviewURL.siteOrigin(fromHelper: remote))
        XCTAssertNil(PreviewURL.pageURL(helper: remote, pageID: "index"))
    }

    func testPreviewURLPageURLRejectsFile() throws {
        let file = try XCTUnwrap(URL(string: "file:///tmp/index.html"))
        XCTAssertNil(PreviewURL.siteOrigin(fromHelper: file))
        XCTAssertNil(PreviewURL.pageURL(helper: file, pageID: "index"))
    }
}
