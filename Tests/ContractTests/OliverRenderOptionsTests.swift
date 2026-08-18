import XCTest

final class OliverRenderOptionsTests: XCTestCase {
    func testDefaultsProduceBareRenderCommand() {
        let args = OliverRenderOptions().arguments(frontend: .markdown)
        XCTAssertEqual(args, ["render", "--from", "markdown"])
    }

    func testFrontendsMapToCLINames() {
        XCTAssertEqual(OliverRenderOptions().arguments(frontend: .textile).dropFirst(2).first, "textile")
        XCTAssertEqual(OliverRenderOptions().arguments(frontend: .cooklang).dropFirst(2).first, "cooklang")
    }

    func testExtensionFlagsEmitOnlyWhenSet() {
        var options = OliverRenderOptions()
        options.wikilinks = true
        options.callouts = true
        options.smartypants = true
        options.footnotes = true
        options.definitionLists = true
        options.headingAttributes = true
        options.strikethrough = true
        options.headingIDs = true
        options.taskLists = true
        let args = options.arguments(frontend: .markdown)
        for flag in [
            "--wikilinks", "--callouts", "--smartypants", "--footnotes",
            "--definition-lists", "--heading-attributes", "--strikethrough",
            "--heading-ids", "--task-lists",
        ] {
            XCTAssertTrue(args.contains(flag), "expected \(flag) in \(args)")
        }
    }

    func testDefaultRawHTMLAndFrontmatterAreOmitted() {
        let args = OliverRenderOptions().arguments(frontend: .markdown)
        XCTAssertFalse(args.contains("--raw-html"))
        XCTAssertFalse(args.contains("--frontmatter"))
    }

    func testRawHTMLPolicyEmitsValue() {
        var options = OliverRenderOptions()
        options.rawHTML = .escaped
        let args = options.arguments(frontend: .markdown)
        XCTAssertEqual(args.suffix(2), ["--raw-html", "escaped"])
    }

    func testFrontmatterPolicyEmitsValue() {
        var options = OliverRenderOptions()
        options.frontmatter = .toml
        let args = options.arguments(frontend: .markdown)
        XCTAssertEqual(args.suffix(2), ["--frontmatter", "toml"])
    }

    func testXHTMLProfileEmitsTo() {
        var options = OliverRenderOptions()
        options.profile = .xhtml
        let args = options.arguments(frontend: .markdown)
        XCTAssertEqual(args.suffix(2), ["--to", "xhtml"])
    }
}
