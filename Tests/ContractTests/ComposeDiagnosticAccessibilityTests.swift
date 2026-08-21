import XCTest

/// A11Y-1 #239: the diagnostics-row VoiceOver label. Pinned here because
/// `ComposeDiagnostic` is compiled into ContractTests (Foundation-only);
/// the view wiring (`.accessibilityElement(children: .combine)` + this
/// label) is manual-verified.
final class ComposeDiagnosticAccessibilityTests: XCTestCase {
    func testErrorWithLine() {
        let diagnostic = ComposeDiagnostic(severity: .error, message: "unexpected token", line: 12)
        XCTAssertEqual(diagnostic.accessibilityLabel, "Error on line 12: unexpected token")
    }

    func testWarningWithLine() {
        let diagnostic = ComposeDiagnostic(severity: .warning, message: "missing closing fence", line: 3)
        XCTAssertEqual(diagnostic.accessibilityLabel, "Warning on line 3: missing closing fence")
    }

    func testErrorWithoutLineOmitsLineClause() {
        let diagnostic = ComposeDiagnostic(severity: .error, message: "render failed")
        XCTAssertEqual(diagnostic.accessibilityLabel, "Error: render failed")
    }

    func testWarningWithoutLineOmitsLineClause() {
        let diagnostic = ComposeDiagnostic(severity: .warning, message: "unknown syntax")
        XCTAssertEqual(diagnostic.accessibilityLabel, "Warning: unknown syntax")
    }

    func testLabelKeepsMessageWhitespace() {
        let diagnostic = ComposeDiagnostic(severity: .error, message: "unclosed `{` (no `}` on the line)", line: 1)
        XCTAssertEqual(diagnostic.accessibilityLabel, "Error on line 1: unclosed `{` (no `}` on the line)")
    }
}
