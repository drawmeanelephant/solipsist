import Foundation

/// One diagnostic for the compose element's problems seam (LATER-3.1).
/// Oliver's span-based diagnostics map into this shape; the element only
/// renders what it is given. Foundation-only so the ContractTests target
/// can pin the mapping without a SwiftUI import.
struct ComposeDiagnostic: Identifiable, Equatable {
    enum Severity: Equatable {
        case warning
        case error
    }

    let id = UUID()
    let severity: Severity
    let message: String
    let line: Int?
    /// Absolute character offset (Oliver's `span.start`) for click-to-line.
    let characterIndex: Int?

    init(severity: Severity, message: String, line: Int? = nil, characterIndex: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
        self.characterIndex = characterIndex
    }
}
