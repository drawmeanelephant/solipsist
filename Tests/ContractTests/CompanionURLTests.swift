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

    // MARK: - PreviewURL Tests

    func testPreviewURLLoopbackRules() throws {
        let v4 = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/__boris/"))
        let localhost = try XCTUnwrap(URL(string: "http://localhost:3000/"))
        let v6 = try XCTUnwrap(URL(string: "http://[::1]:9000/preview"))

        XCTAssertTrue(PreviewURL.isLoopback(v4))
        XCTAssertTrue(PreviewURL.isLoopback(localhost))
        XCTAssertTrue(PreviewURL.isLoopback(v6))
        XCTAssertTrue(PreviewURL.isAllowed(v4))
        XCTAssertTrue(PreviewURL.isAllowed(localhost))
        XCTAssertTrue(PreviewURL.isAllowed(v6))
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
}
