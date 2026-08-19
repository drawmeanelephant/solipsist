import XCTest

/// LATER-3.1: Oliver's `--diagnostics json` side channel, decoded defensively.
/// Shapes pinned from a live probe of the built CLI (2026-08-19) — stderr is
/// a JSON array with exact source spans; stdout stays pure HTML.
final class OliverDiagnosticTests: XCTestCase {
    private let probeFrontmatter = #"[{"severity":"warning","code":"unclosed-frontmatter","offset":1,"line":1,"column":1,""#
        + #"span":{"start":0,"end":4},"message":"front matter fence `---` never closed"}]"#

    private let probeCooklang = #"[{"severity":"warning","code":"unclosed-braces","offset":12,"line":1,"column":12,""#
        + #"span":{"start":11,"end":12},"message":"unclosed `{` (no `}` on the line)"}]"#

    func testDecodesProbedFrontmatterDiagnostic() {
        let decoded = OliverRenderer.decodeDiagnostics(from: probeFrontmatter)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].severity, "warning")
        XCTAssertEqual(decoded[0].code, "unclosed-frontmatter")
        XCTAssertEqual(decoded[0].line, 1)
        XCTAssertEqual(decoded[0].column, 1)
        XCTAssertEqual(decoded[0].span?.start, 0)
        XCTAssertEqual(decoded[0].span?.end, 4)
    }

    func testDecodesProbedCooklangDiagnostic() {
        let decoded = OliverRenderer.decodeDiagnostics(from: probeCooklang)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].code, "unclosed-braces")
        XCTAssertEqual(decoded[0].offset, 12)
        XCTAssertEqual(decoded[0].span?.start, 11)
        XCTAssertEqual(decoded[0].message, "unclosed `{` (no `}` on the line)")
    }

    func testEmptyArrayDecodes() {
        XCTAssertTrue(OliverRenderer.decodeDiagnostics(from: "[]").isEmpty)
    }

    func testProseStderrDegradesToEmpty() {
        // The side channel is absent (flag off) or the CLI printed prose —
        // never a throw (D8).
        XCTAssertTrue(OliverRenderer.decodeDiagnostics(from: "").isEmpty)
        XCTAssertTrue(OliverRenderer.decodeDiagnostics(from: "oliver: RawHtmlRejected\n").isEmpty)
        XCTAssertTrue(OliverRenderer.decodeDiagnostics(from: "not json at all").isEmpty)
    }

    func testUnknownFieldsDecodeDefensively() {
        // Newer shapes may add fields; the known ones must still decode.
        let newer = #"[{"severity":"error","code":"future-thing","line":7,"span":{"start":10,"end":20},"message":"hi","extra":{"nested":true}}]"#
        let decoded = OliverRenderer.decodeDiagnostics(from: newer)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].severity, "error")
        XCTAssertEqual(decoded[0].line, 7)
        XCTAssertEqual(decoded[0].span?.start, 10)
    }
}
