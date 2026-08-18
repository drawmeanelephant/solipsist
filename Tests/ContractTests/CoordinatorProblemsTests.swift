import XCTest

final class CoordinatorProblemsTests: XCTestCase {
    func testReportDiagnosticsBecomeRows() {
        let report = HTMLBuildReport(
            schemaVersion: "html-build-report-0.1.0",
            compilerId: "boris",
            ok: false,
            contentRoot: nil,
            outDir: nil,
            errorCount: 1,
            diagnostics: [
                Diagnostic(
                    severity: "error",
                    code: "EFRONTMATTER",
                    message: "bad yaml",
                    remediation: "fix it",
                    sourcePath: "index.md",
                    line: 3,
                    column: 1,
                    id: nil
                )
            ]
        )
        let items = CoordinatorProblems.from(report: report)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].code, "EFRONTMATTER")
        XCTAssertEqual(items[0].path, "index.md")
        XCTAssertEqual(items[0].line, 3)
    }

    func testFailedEntryWithoutReportSurfacesStderr() {
        let items = CoordinatorProblems.fromEntry(
            name: "rag",
            kind: "rag",
            exitCode: 1,
            stderr: "rag: split-size too small\n",
            report: nil
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].severity, "error")
        XCTAssertEqual(items[0].code, "rag")
        XCTAssertEqual(items[0].message, "rag: split-size too small")
    }

    func testFailedEntryWithoutStderrSurfacesExit() {
        let items = CoordinatorProblems.fromEntry(
            name: "public",
            kind: "target",
            exitCode: 2,
            stderr: "   ",
            report: nil
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].message, "public: exit 2")
    }

    func testSuccessfulEntryWithoutReportIsSilent() {
        let items = CoordinatorProblems.fromEntry(
            name: "ir",
            kind: "ir",
            exitCode: 0,
            stderr: "",
            report: nil
        )
        XCTAssertTrue(items.isEmpty)
    }

    func testCommandFailureNeverDropsEmptyStderr() {
        let items = CoordinatorProblems.fromCommand(code: "standard-site", exitCode: 7, stderr: "")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].code, "standard-site")
        XCTAssertEqual(items[0].message, "exit 7")
    }

    func testFanoutKeepsEveryFailedEntry() {
        let items = CoordinatorProblems.fromEntries([
            .init(name: "public", kind: "target", exitCode: 0, stderr: "", report: nil),
            .init(name: "rag", kind: "rag", exitCode: 1, stderr: "rag failed", report: nil),
            .init(name: "context", kind: "context", exitCode: 1, stderr: "context failed", report: nil),
        ])
        XCTAssertEqual(items.map(\.message), ["rag failed", "context failed"])
    }
}
