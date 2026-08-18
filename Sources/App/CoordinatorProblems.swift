import Foundation

struct ProblemItem: Identifiable, Hashable, Sendable {
    let id: String
    let severity: String
    let code: String
    let message: String
    let path: String?
    let line: Int?
    let column: Int?

    init(
        severity: String,
        code: String,
        message: String,
        path: String? = nil,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.id = "\(code)|\(path ?? "")|\(line ?? -1)|\(column ?? -1)|\(message)"
        self.severity = severity
        self.code = code
        self.message = message
        self.path = path
        self.line = line
        self.column = column
    }
}

/// Maps engine results onto the problems list. A non-zero exit with no
/// report still becomes a row — never swallow stderr or an exit code.
enum CoordinatorProblems {
    static func from(report: HTMLBuildReport?) -> [ProblemItem] {
        (report?.diagnostics ?? []).map(from(diagnostic:))
    }

    static func from(diagnostic: Diagnostic) -> ProblemItem {
        ProblemItem(
            severity: diagnostic.severity,
            code: diagnostic.code,
            message: diagnostic.message,
            path: diagnostic.sourcePath,
            line: diagnostic.line,
            column: diagnostic.column
        )
    }

    static func fromIR(report: BuildReport) -> [ProblemItem] {
        report.diagnostics.map(from(diagnostic:))
    }

    /// Target / edition / fan-out entry. Prefer the report; if the report is
    /// missing or empty and the process failed, surface stderr (or the exit).
    static func fromEntry(
        name: String,
        kind: String,
        exitCode: Int32,
        stderr: String,
        report: HTMLBuildReport?
    ) -> [ProblemItem] {
        let fromReport = from(report: report)
        if !fromReport.isEmpty { return fromReport }
        guard exitCode != 0 else { return [] }
        return [failed(code: kind, name: name, exitCode: exitCode, stderr: stderr)]
    }

    static func fromEntries(_ results: [EntryProblemSource]) -> [ProblemItem] {
        results.flatMap {
            fromEntry(
                name: $0.name,
                kind: $0.kind,
                exitCode: $0.exitCode,
                stderr: $0.stderr,
                report: $0.report
            )
        }
    }

    static func fromCommand(code: String, exitCode: Int32, stderr: String) -> [ProblemItem] {
        guard exitCode != 0 else { return [] }
        return [failed(code: code, name: nil, exitCode: exitCode, stderr: stderr)]
    }

    static func fromFailure(code: String, message: String) -> [ProblemItem] {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            ProblemItem(
                severity: "error",
                code: code,
                message: trimmed.isEmpty ? code : trimmed
            )
        ]
    }

    struct EntryProblemSource: Sendable {
        var name: String
        var kind: String
        var exitCode: Int32
        var stderr: String
        var report: HTMLBuildReport?
    }

    private static func failed(
        code: String,
        name: String?,
        exitCode: Int32,
        stderr: String
    ) -> ProblemItem {
        let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if !tail.isEmpty {
            message = tail
        } else if let name {
            message = "\(name): exit \(exitCode)"
        } else {
            message = "exit \(exitCode)"
        }
        return ProblemItem(severity: "error", code: code, message: message)
    }
}
