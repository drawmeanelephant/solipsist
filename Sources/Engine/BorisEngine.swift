import Foundation

/// Result of a Boris IR build: exit code, decoded `build-report.json`, and —
/// when the build succeeded — the decoded `manifest.json` / `graph.json`.
public struct BorisBuild: Sendable {
    public let exitCode: Int32
    public let report: BuildReport
    public let manifest: Manifest?
    public let graph: Graph?
    public let stderr: String
}

/// Result of a Boris HTML build (exit code + stderr; HTML mode publishes no
/// JSON artifacts).
public struct BorisHTMLBuild: Sendable {
    public let exitCode: Int32
    public let stderr: String
}

/// Result of `boris check` / `boris impact`.
public struct BorisAnalysis: Sendable {
    public let exitCode: Int32
    public let report: AnalysisReport
}

public enum BorisEngineError: Error, Sendable, CustomStringConvertible {
    case binaryNotFound
    case missingArtifact(String)
    case decodeFailed(artifact: String, reason: String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "boris binary not found (set SOLIPSIST_BORIS_BIN or build via scripts/embed-boris.sh)"
        case .missingArtifact(let name):
            return "missing expected output artifact: \(name)"
        case .decodeFailed(let artifact, let reason):
            return "failed to decode \(artifact): \(reason)"
        }
    }
}

/// The engine: a single actor owning all Boris subprocess launches so that
/// builds never overlap (Boris watch mode explicitly forbids concurrent
/// builds in one process; we serialize across processes too).
public actor BorisEngine {
    public let binaryURL: URL

    public init(binaryURL: URL? = nil) throws {
        if let binaryURL {
            self.binaryURL = binaryURL
        } else if let located = BorisBinary.locate() {
            self.binaryURL = located
        } else {
            throw BorisEngineError.binaryNotFound
        }
    }

    // MARK: Builds

    /// Runs `boris --out <dir> --input <root> --quiet` (IR mode) and decodes
    /// the published artifacts (`build-report.json` always; `manifest.json` /
    /// `graph.json` only on success — Boris deletes them on content failure;
    /// `completion.json` exists on afterparty but is not yet modeled).
    ///
    /// Afterparty constrains **output trees** to the process workspace and
    /// rejects absolute output paths in IR mode (verified: `--out /abs/…`
    /// fails with `WorkspaceEscape` even inside cwd; relative paths pass).
    /// The input root may live anywhere. So we run from the output's parent
    /// and pass a **relative** output path. For the app this means
    /// `cwd = project folder`, `--out .boris` — the D1 defaults.
    public func buildIR(contentRoot: URL, outDir: URL) throws -> BorisBuild {
        try FileManager.default.createDirectory(
            at: outDir, withIntermediateDirectories: true
        )
        let out = try BorisRunner.run(
            binary: binaryURL,
            arguments: [
                "--out", outDir.lastPathComponent,
                "--input", contentRoot.path,
                "--quiet",
            ],
            workingDirectory: outDir.deletingLastPathComponent()
        )
        let report = try decode(
            BuildReport.self,
            from: outDir.appendingPathComponent("build-report.json"),
            artifact: "build-report.json"
        )
        var manifest: Manifest?
        var graph: Graph?
        if report.ok {
            manifest = try? decode(
                Manifest.self,
                from: outDir.appendingPathComponent("manifest.json"),
                artifact: "manifest.json"
            )
            graph = try? decode(
                Graph.self,
                from: outDir.appendingPathComponent("graph.json"),
                artifact: "graph.json"
            )
        }
        return BorisBuild(
            exitCode: out.exitCode,
            report: report,
            manifest: manifest,
            graph: graph,
            stderr: out.stderrText
        )
    }

    /// Runs an HTML site build: `boris --input <root> --html-dir <dir> --quiet`.
    ///
    /// Same afterparty containment rule as `buildIR`: run from the output's
    /// parent and pass a relative path.
    public func buildHTML(contentRoot: URL, htmlDir: URL) throws -> BorisHTMLBuild {
        try FileManager.default.createDirectory(
            at: htmlDir, withIntermediateDirectories: true
        )
        let out = try BorisRunner.run(
            binary: binaryURL,
            arguments: [
                "--input", contentRoot.path,
                "--html-dir", htmlDir.lastPathComponent,
                "--quiet",
            ],
            workingDirectory: htmlDir.deletingLastPathComponent()
        )
        return BorisHTMLBuild(exitCode: out.exitCode, stderr: out.stderrText)
    }

    // MARK: Analysis

    /// Runs `boris check --format json --report <file>` and decodes the report.
    ///
    /// Note: Boris prints analysis reports to *stderr* by default, so we use
    /// `--report PATH` to write the rendered JSON to a file instead. On
    /// afterparty, `check` exits 0 with findings by default and only exits 1
    /// with `--fail-on-unreferenced` — either way the report decodes fine.
    public func check(contentRoot: URL) throws -> BorisAnalysis {
        let fm = FileManager.default
        let reportURL = fm.temporaryDirectory
            .appendingPathComponent("boris-check-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: reportURL) }
        let out = try BorisRunner.run(binary: binaryURL, arguments: [
            "check",
            "--input", contentRoot.path,
            "--format", "json",
            "--report", reportURL.path,
            "--quiet",
        ])
        let report = try decode(AnalysisReport.self, from: reportURL, artifact: "check report")
        return BorisAnalysis(exitCode: out.exitCode, report: report)
    }

    /// Runs `boris impact <pageID> --format json --report <file>` and decodes
    /// the report.
    public func impact(contentRoot: URL, pageID: String) throws -> BorisAnalysis {
        let fm = FileManager.default
        let reportURL = fm.temporaryDirectory
            .appendingPathComponent("boris-impact-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: reportURL) }
        let out = try BorisRunner.run(binary: binaryURL, arguments: [
            "impact", pageID,
            "--input", contentRoot.path,
            "--format", "json",
            "--report", reportURL.path,
            "--quiet",
        ])
        let report = try decode(AnalysisReport.self, from: reportURL, artifact: "impact report")
        return BorisAnalysis(exitCode: out.exitCode, report: report)
    }

    // MARK: Probe

    /// Sanity probe: runs `boris --help` and returns the first lines.
    public func probe() throws -> String {
        let out = try BorisRunner.run(binary: binaryURL, arguments: ["--help"])
        let head = out.stdoutText
            .split(separator: "\n")
            .prefix(3)
            .joined(separator: "\n")
        return "exit \(out.exitCode)\n\(head)"
    }

    // MARK: Helpers

    private func decode<T: Decodable>(_ type: T.Type, from url: URL, artifact: String) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BorisEngineError.missingArtifact(artifact)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BorisEngineError.decodeFailed(artifact: artifact, reason: String(describing: error))
        }
    }
}
