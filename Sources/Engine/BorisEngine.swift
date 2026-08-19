import Foundation

/// Result of a Boris IR build: exit code, decoded `build-report.json`, and —
/// when the build succeeded — the decoded `manifest.json` / `graph.json` /
/// `completion.json`. `--timings` (when requested) is optional stdout JSON.
public struct BorisBuild: Sendable {
    public let exitCode: Int32
    public let report: BuildReport
    public let manifest: Manifest?
    public let graph: Graph?
    public let completion: Completion?
    public let timings: TimingsReport?
    public let stderr: String
}

/// Result of a Boris HTML build. Optional `--report` decodes
/// `html-build-report-0.1.0` when the file is written.
public struct BorisHTMLBuild: Sendable {
    public let exitCode: Int32
    public let report: HTMLBuildReport?
    public let stderr: String
}

/// Result of `boris check` / `boris impact`.
public struct BorisAnalysis: Sendable {
    public let exitCode: Int32
    public let report: AnalysisReport
}

/// Result of `boris --version`.
public struct BorisVersion: Sendable {
    public let exitCode: Int32
    public let line: String
}

/// Result of `boris plan --profile`. Exit 2/3 when the profile is missing or
/// invalid; `plan` is then nil and stdout/stderr carry the engine's output.
public struct BorisPlan: Sendable {
    public let exitCode: Int32
    public let plan: PublicationPlan?
    public let stdout: String
    public let stderr: String
}

/// Result of `boris validate --report`. The report is written on success and
/// content/I/O failure; usage errors may produce no file.
public struct BorisValidate: Sendable {
    public let exitCode: Int32
    public let report: HTMLBuildReport?
    public let stderr: String
}

/// Result of `boris init`.
public struct BorisInit: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

/// Result of building a single target or edition.
public struct BorisEntryBuildResult: Sendable {
    public let name: String
    public let kind: String // "target", "ir", "rag", "context"
    public let exitCode: Int32
    public let report: HTMLBuildReport?
    public let timings: TimingsReport?
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }
}

/// Result of `buildAll` fan-out over profile targets and editions.
public struct BorisFanoutResult: Sendable {
    public let isSuccess: Bool
    public let results: [BorisEntryBuildResult]
    public let totalDurationNs: Int?
}

/// Result of publication commands.
public struct BorisPublishResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

/// Result of recipe-scale evaluation.
public struct BorisRecipeScale: Sendable {
    public let exitCode: Int32
    public let recipe: CookRecipe?
    public let scale: Double
    public let stdout: String
    public let stderr: String
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
    private let runHandle = RunHandle()

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
    /// `graph.json` / `completion.json` only on success — Boris deletes them
    /// on content failure).
    ///
    /// Afterparty constrains **output trees** to the process workspace and
    /// rejects absolute output paths in IR mode (verified: `--out /abs/…`
    /// fails with `WorkspaceEscape` even inside cwd; relative paths pass).
    /// The input root may live anywhere. So we run from the output's parent
    /// and pass a **relative** output path. For the app this means
    /// `cwd = project folder`, `--out .boris` — the D1 defaults.
    ///
    /// Pass `timings: true` to add `--timings` and optionally decode the
    /// `boris-timings` JSON on stdout.
    public func buildIR(
        contentRoot: URL,
        outDir: URL,
        timings: Bool = false,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> BorisBuild {
        try FileManager.default.createDirectory(
            at: outDir, withIntermediateDirectories: true
        )
        var arguments = [
            "--out", outDir.lastPathComponent,
            "--input", contentRoot.path,
        ]
        if let knobs {
            knobs.apply(to: &arguments, defaultQuiet: true)
        } else {
            arguments.append("--quiet")
        }
        if timings {
            arguments.append("--timings")
        }
        let out = try await run(
            arguments: arguments,
            workingDirectory: outDir.deletingLastPathComponent()
        )
        let report = try decode(
            BuildReport.self,
            from: outDir.appendingPathComponent("build-report.json"),
            artifact: "build-report.json"
        )
        var manifest: Manifest?
        var graph: Graph?
        var completion: Completion?
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
            completion = try? decode(
                Completion.self,
                from: outDir.appendingPathComponent("completion.json"),
                artifact: "completion.json"
            )
        }
        let timingsReport: TimingsReport?
        if timings {
            timingsReport = decodeJSON(TimingsReport.self, from: out.stdout)
        } else {
            timingsReport = nil
        }
        return BorisBuild(
            exitCode: out.exitCode,
            report: report,
            manifest: manifest,
            graph: graph,
            completion: completion,
            timings: timingsReport,
            stderr: out.stderrText
        )
    }

    /// Runs an HTML site build: `boris --input <root> --html-dir <dir> --quiet`.
    ///
    /// Same afterparty containment rule as `buildIR`: run from the output's
    /// parent and pass a relative path. Optional `--report` is a single file
    /// (absolute allowed).
    public func buildHTML(
        contentRoot: URL,
        htmlDir: URL,
        reportURL: URL? = nil,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> BorisHTMLBuild {
        try FileManager.default.createDirectory(
            at: htmlDir, withIntermediateDirectories: true
        )
        var arguments = [
            "--input", contentRoot.path,
            "--html-dir", htmlDir.lastPathComponent,
        ]
        if let knobs {
            knobs.apply(to: &arguments, defaultQuiet: true)
        } else {
            arguments.append("--quiet")
        }
        if let reportURL {
            arguments += ["--report", reportURL.path]
        }
        let out = try await run(
            arguments: arguments,
            workingDirectory: htmlDir.deletingLastPathComponent()
        )
        var report: HTMLBuildReport?
        if let reportURL, FileManager.default.fileExists(atPath: reportURL.path) {
            report = try? decode(
                HTMLBuildReport.self,
                from: reportURL,
                artifact: "html-build-report"
            )
        }
        return BorisHTMLBuild(exitCode: out.exitCode, report: report, stderr: out.stderrText)
    }

    /// Runs `boris` for a single named `PublicationTarget` from a profile.
    public func buildTarget(
        contentRoot: URL,
        target: PublicationTarget,
        siteURL: String? = nil,
        workingDirectory: URL? = nil,
        timings: Bool = false,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> BorisEntryBuildResult {
        let cwd = workingDirectory ?? contentRoot.deletingLastPathComponent()
        let fm = FileManager.default
        let reportURL = fm.temporaryDirectory
            .appendingPathComponent("boris-report-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: reportURL) }

        var args = [
            "--input", contentRoot.path,
            "--target", "\(target.name)=\(target.output)",
            "--report", reportURL.path,
        ]
        if let knobs {
            knobs.apply(to: &args, defaultQuiet: true)
        } else {
            args.append("--quiet")
        }
        if let theme = target.theme, !theme.isEmpty {
            args.append(contentsOf: ["--theme", theme])
        }
        if let layout = target.layout, !layout.isEmpty {
            args.append(contentsOf: ["--target-layout", "\(target.name)=\(layout)"])
        }
        if let rules = target.layout_rules {
            for rule in rules {
                args.append(contentsOf: ["--layout-rule", target.name, rule.selector, rule.layout])
            }
        }
        if let siteURL, !siteURL.isEmpty {
            args.append(contentsOf: ["--site-url", siteURL])
        }
        if let sitemap = target.sitemap {
            args.append(contentsOf: ["--sitemap-path", sitemap.path])
        }
        if let rss = target.rss {
            args.append(contentsOf: ["--rss-path", rss.path])
        }
        if let llms = target.llms {
            args.append(contentsOf: ["--llms-path", llms.path])
        }
        if timings {
            args.append("--timings")
        }

        let out = try await run(arguments: args, workingDirectory: cwd)
        var report: HTMLBuildReport?
        if FileManager.default.fileExists(atPath: reportURL.path),
           let reportData = try? Data(contentsOf: reportURL)
        {
            report = decodeJSON(HTMLBuildReport.self, from: reportData)
        }
        let timingsReport = timings ? decodeJSON(TimingsReport.self, from: out.stdout) : nil

        return BorisEntryBuildResult(
            name: target.name,
            kind: "target",
            exitCode: out.exitCode,
            report: report,
            timings: timingsReport,
            stdout: out.stdoutText,
            stderr: out.stderrText
        )
    }

    /// Runs `boris` for an edition (`ir`, `rag`, `context`).
    public func buildEdition(
        contentRoot: URL,
        kind: String,
        outputDir: String,
        scope: String? = nil,
        splitSize: Int? = nil,
        isComplete: Bool = false,
        workingDirectory: URL? = nil,
        timings: Bool = false,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> BorisEntryBuildResult {
        let cwd = workingDirectory ?? contentRoot.deletingLastPathComponent()
        var args = ["--input", contentRoot.path]
        if let knobs {
            knobs.apply(to: &args, defaultQuiet: true)
        } else {
            args.append("--quiet")
        }
        switch kind {
        case "ir":
            args.append(contentsOf: ["--out", outputDir])
        case "rag":
            args.append(contentsOf: ["--rag-dir", outputDir])
            if isComplete {
                args.append("--complete")
            } else {
                if let scope, !scope.isEmpty {
                    args.append(contentsOf: ["--scope", scope])
                }
                if let splitSize, splitSize > 0 {
                    args.append(contentsOf: ["--split-size", "\(splitSize)"])
                }
            }
        case "context":
            args.append(contentsOf: ["--context-dir", outputDir])
            if let scope, !scope.isEmpty {
                args.append(contentsOf: ["--scope", scope])
            }
            if let splitSize, splitSize > 0 {
                args.append(contentsOf: ["--split-size", "\(splitSize)"])
            }
        default:
            args.append(contentsOf: ["--out", outputDir])
        }

        if timings {
            args.append("--timings")
        }

        let out = try await run(arguments: args, workingDirectory: cwd)
        let timingsReport = timings ? decodeJSON(TimingsReport.self, from: out.stdout) : nil

        return BorisEntryBuildResult(
            name: kind,
            kind: kind,
            exitCode: out.exitCode,
            report: nil,
            timings: timingsReport,
            stdout: out.stdoutText,
            stderr: out.stderrText
        )
    }

    /// Fans out builds for all targets and editions in a `PublicationProfile`.
    /// Follows profile order, executes isolated invocations, and fails fast
    /// on any target or edition error (as Boris does).
    public func buildAll(
        contentRoot: URL,
        profile: PublicationProfile,
        workingDirectory: URL? = nil,
        timings: Bool = true,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> BorisFanoutResult {
        let cwd = workingDirectory ?? contentRoot.deletingLastPathComponent()
        var results: [BorisEntryBuildResult] = []

        // 1. Targets in profile order
        if let targets = profile.targets, !targets.isEmpty {
            for target in targets {
                let res = try await buildTarget(
                    contentRoot: contentRoot,
                    target: target,
                    siteURL: profile.site?.url,
                    workingDirectory: cwd,
                    timings: timings,
                    knobs: knobs
                )
                results.append(res)
                if !res.isSuccess {
                    return BorisFanoutResult(
                        isSuccess: false,
                        results: results,
                        totalDurationNs: results.compactMap { $0.timings?.totalNs }.reduce(0, +)
                    )
                }
            }
        } else {
            let res = try await buildTarget(
                contentRoot: contentRoot,
                target: PublicationTarget(name: "default", output: "dist"),
                siteURL: profile.site?.url,
                workingDirectory: cwd,
                timings: timings,
                knobs: knobs
            )
            results.append(res)
            if !res.isSuccess {
                return BorisFanoutResult(
                    isSuccess: false,
                    results: results,
                    totalDurationNs: res.timings?.totalNs
                )
            }
        }

        // 2. Editions in profile order
        if let editions = profile.editions {
            if let ir = editions.ir {
                let res = try await buildEdition(
                    contentRoot: contentRoot,
                    kind: "ir",
                    outputDir: ir.output,
                    workingDirectory: cwd,
                    timings: timings,
                    knobs: knobs
                )
                results.append(res)
                if !res.isSuccess {
                    return BorisFanoutResult(
                        isSuccess: false,
                        results: results,
                        totalDurationNs: results.compactMap { $0.timings?.totalNs }.reduce(0, +)
                    )
                }
            }
            if let rag = editions.rag {
                let res = try await buildEdition(
                    contentRoot: contentRoot,
                    kind: "rag",
                    outputDir: rag.output,
                    scope: rag.scope,
                    splitSize: rag.split_size,
                    workingDirectory: cwd,
                    timings: timings,
                    knobs: knobs
                )
                results.append(res)
                if !res.isSuccess {
                    return BorisFanoutResult(
                        isSuccess: false,
                        results: results,
                        totalDurationNs: results.compactMap { $0.timings?.totalNs }.reduce(0, +)
                    )
                }
            }
            if let context = editions.context {
                let res = try await buildEdition(
                    contentRoot: contentRoot,
                    kind: "context",
                    outputDir: context.output,
                    scope: context.scope,
                    splitSize: context.split_size,
                    workingDirectory: cwd,
                    timings: timings,
                    knobs: knobs
                )
                results.append(res)
                if !res.isSuccess {
                    return BorisFanoutResult(
                        isSuccess: false,
                        results: results,
                        totalDurationNs: results.compactMap { $0.timings?.totalNs }.reduce(0, +)
                    )
                }
            }
        }

        let totalDuration = results.compactMap { $0.timings?.totalNs }.reduce(0, +)
        return BorisFanoutResult(
            isSuccess: true,
            results: results,
            totalDurationNs: totalDuration > 0 ? totalDuration : nil
        )
    }

    /// SIGTERM the in-flight process, if any. One-shot builds die; watch
    /// exits 0. The app treats `terminationReason == .uncaughtSignal` as
    /// cancel when we inspect it; here we surface the resulting exit.
    public nonisolated func interrupt() {
        runHandle.terminate()
    }

    /// SIGKILL the in-flight one-shot if SIGTERM was ignored.
    public nonisolated func forceKill() {
        runHandle.forceKill()
    }

    /// SIGTERM, wait, SIGKILL. Yields so Stop stays responsive.
    public nonisolated func escalate(grace: Duration = ChildProcessControl.reapGrace) async {
        await runHandle.escalate(grace: grace)
    }

    // MARK: Preview (M4)

    /// Starts `boris watch --serve --port 0` for `contentRoot` (D5) and
    /// returns the live server. `workingDirectory` is the project folder
    /// (D1: layouts/themes resolve and outputs stay contained there). The
    /// server parses the startup stderr line for the ephemeral port;
    /// `WatchServer.onServe` delivers the helper URL (`…/__boris/`) the
    /// preview web view loads. The caller owns the server lifetime — call
    /// `stop()` (SIGTERM → graceful exit 0, A12) when done. `nonisolated`:
    /// reads only the immutable `binaryURL`.
    public nonisolated func previewStart(
        contentRoot: URL,
        workingDirectory: URL,
        port: Int = 0
    ) throws -> WatchServer {
        let server = WatchServer(
            binary: binaryURL,
            contentRoot: contentRoot,
            workingDirectory: workingDirectory,
            port: port
        )
        try server.start()
        return server
    }

    // MARK: Validate watch (A5 / #161)

    /// Starts `boris validate --watch --watch-json` for `contentRoot` and
    /// returns the live problems daemon. `workingDirectory` is the project
    /// folder (D1). Validate writes nothing, so the daemon is a sibling of
    /// the preview watch — never a third watch — and needs no tree-write
    /// suspend. The caller owns the lifetime — call `stop()` (SIGTERM →
    /// graceful exit 0, A12) when done. `nonisolated`: reads only the
    /// immutable `binaryURL`.
    public nonisolated func validateStart(
        contentRoot: URL,
        workingDirectory: URL
    ) throws -> ValidateWatch {
        let watch = ValidateWatch(
            binary: binaryURL,
            contentRoot: contentRoot,
            workingDirectory: workingDirectory
        )
        try watch.start()
        return watch
    }

    // MARK: Editor (M6)

    /// Starts `boris-editor` for the project at `workingDirectory` (A14).
    /// DIR is the project folder (must contain `content/`), not the content tree.
    public nonisolated func editorStart(
        editorBinary: URL,
        workingDirectory: URL,
        uiDir: URL? = nil,
        port: Int = 0
    ) throws -> EditorServer {
        let server = EditorServer(
            editorBinary: editorBinary,
            engineBinary: binaryURL,
            projectRoot: workingDirectory,
            uiDir: uiDir,
            port: port
        )
        try server.start()
        return server
    }

    // MARK: Analysis

    /// Runs `boris check --format json --report <file>` and decodes the report.
    ///
    /// Note: Boris prints analysis reports to *stderr* by default, so we use
    /// `--report PATH` to write the rendered JSON to a file instead. On
    /// afterparty, `check` exits 0 with findings by default and only exits 1
    /// with `--fail-on-unreferenced` — either way the report decodes fine.
    public func check(contentRoot: URL, workingDirectory: URL? = nil, knobs: BorisExecutionKnobs? = nil) async throws -> BorisAnalysis {
        let fm = FileManager.default
        let reportURL = fm.temporaryDirectory
            .appendingPathComponent("boris-check-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: reportURL) }
        var args = [
            "check",
            "--input", contentRoot.path,
            "--format", "json",
            "--report", reportURL.path,
        ]
        if let knobs {
            knobs.apply(to: &args, defaultQuiet: true)
        } else {
            args.append("--quiet")
        }
        let out = try await run(
            arguments: args,
            workingDirectory: workingDirectory ?? contentRoot.deletingLastPathComponent()
        )
        let report = try decode(AnalysisReport.self, from: reportURL, artifact: "check report")
        return BorisAnalysis(exitCode: out.exitCode, report: report)
    }

    /// Runs `boris impact <pageID> --format json --report <file>` and decodes
    /// the report.
    public func impact(contentRoot: URL, pageID: String, workingDirectory: URL? = nil, knobs: BorisExecutionKnobs? = nil) async throws -> BorisAnalysis {
        let fm = FileManager.default
        let reportURL = fm.temporaryDirectory
            .appendingPathComponent("boris-impact-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: reportURL) }
        var args = [
            "impact", pageID,
            "--input", contentRoot.path,
            "--format", "json",
            "--report", reportURL.path,
        ]
        if let knobs {
            knobs.apply(to: &args, defaultQuiet: true)
        } else {
            args.append("--quiet")
        }
        let out = try await run(
            arguments: args,
            workingDirectory: workingDirectory ?? contentRoot.deletingLastPathComponent()
        )
        let report = try decode(AnalysisReport.self, from: reportURL, artifact: "impact report")
        return BorisAnalysis(exitCode: out.exitCode, report: report)
    }

    // MARK: Version / plan / validate / init

    /// Runs `boris --version` and returns the stdout line (e.g. `boris/0.8.1`).
    public func version() async throws -> BorisVersion {
        let out = try await run(arguments: ["--version"])
        let line = out.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return BorisVersion(exitCode: out.exitCode, line: line)
    }

    /// Runs `boris plan --profile PATH` with cwd = the profile's parent
    /// (the publication workspace). Does not invent a profile.
    public func plan(profileURL: URL) async throws -> BorisPlan {
        let out = try await run(
            arguments: ["plan", "--profile", profileURL.lastPathComponent],
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        return BorisPlan(
            exitCode: out.exitCode,
            plan: decodeJSON(PublicationPlan.self, from: out.stdout),
            stdout: out.stdoutText,
            stderr: out.stderrText
        )
    }

    /// Runs `boris validate --input … --report PATH` and decodes the
    /// `html-build-report-0.1.0` file when written. `--report` may be absolute.
    public func validate(
        contentRoot: URL,
        reportURL: URL,
        workingDirectory: URL? = nil,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> BorisValidate {
        var args = [
            "validate",
            "--input", contentRoot.path,
            "--report", reportURL.path,
        ]
        knobs?.apply(to: &args, defaultQuiet: false)
        let out = try await run(
            arguments: args,
            workingDirectory: workingDirectory ?? contentRoot.deletingLastPathComponent()
        )
        var report: HTMLBuildReport?
        if FileManager.default.fileExists(atPath: reportURL.path) {
            report = try decode(
                HTMLBuildReport.self,
                from: reportURL,
                artifact: "validate report"
            )
        }
        return BorisValidate(
            exitCode: out.exitCode,
            report: report,
            stderr: out.stderrText
        )
    }

    /// Runs `boris init` in `directory`.
    public func initProject(in directory: URL) async throws -> BorisInit {
        let out = try await run(arguments: ["init"], workingDirectory: directory)
        return BorisInit(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    // MARK: Publication (M8)

    /// Runs `boris standard-site plan --profile PATH`.
    public func standardSitePlan(profileURL: URL) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: ["standard-site", "plan", "--profile", profileURL.lastPathComponent],
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris standard-site records --profile PATH`.
    public func standardSiteRecords(profileURL: URL) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: ["standard-site", "records", "--profile", profileURL.lastPathComponent],
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris standard-site login --app-password` with the password on stdin.
    /// Identity is `--did` or `--handle` (never a secret).
    public func standardSiteLogin(
        did: String? = nil,
        handle: String? = nil,
        password: SecureBuffer,
        workingDirectory: URL? = nil
    ) async throws -> BorisPublishResult {
        var args = ["standard-site", "login", "--app-password"]
        if let did, !did.isEmpty {
            args += ["--did", did]
        } else if let handle, !handle.isEmpty {
            args += ["--handle", handle]
        }
        let out = try await run(
            arguments: args,
            workingDirectory: workingDirectory,
            stdin: password
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris standard-site publish --profile PATH`.
    /// Preserves exit classes 4–9 (denial, timeout, compatibility, partial-publication, verification, session).
    public func standardSitePublish(profileURL: URL) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: ["standard-site", "publish", "--profile", profileURL.lastPathComponent],
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris standard-site verify --profile PATH`.
    public func standardSiteVerify(profileURL: URL) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: ["standard-site", "verify", "--profile", profileURL.lastPathComponent],
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris standard-site sessions`.
    public func standardSiteSessions(workingDirectory: URL? = nil) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: ["standard-site", "sessions"],
            workingDirectory: workingDirectory
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris standard-site logout`.
    public func standardSiteLogout(workingDirectory: URL? = nil) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: ["standard-site", "logout"],
            workingDirectory: workingDirectory
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris standard-site smoke` (live opt-in interop test).
    public func standardSiteSmoke(
        profileURL: URL? = nil,
        workingDirectory: URL? = nil
    ) async throws -> BorisPublishResult {
        var args = ["standard-site", "smoke"]
        if let profileURL {
            args.append(contentsOf: ["--profile", profileURL.lastPathComponent])
        }
        let out = try await run(
            arguments: args,
            workingDirectory: workingDirectory ?? profileURL?.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris package`: produces `packages/<archive>` containing `MACHINE-READABLE-VERSION.json`, `SHA256SUMS`, etc.
    public func package(
        contentRoot: URL,
        packagesDir: URL? = nil,
        archive: String? = nil,
        withRag: Bool = true,
        workingDirectory: URL? = nil
    ) async throws -> BorisPublishResult {
        var args = ["package", "--input", contentRoot.path]
        if let packagesDir {
            args.append(contentsOf: ["--packages-dir", packagesDir.path])
        }
        if let archive, !archive.isEmpty {
            args.append(contentsOf: ["--archive", archive])
        }
        args.append(withRag ? "--with-rag" : "--no-rag")
        args.append("--quiet")

        let out = try await run(
            arguments: args,
            workingDirectory: workingDirectory ?? contentRoot.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris nostr plan --profile PATH`.
    public func nostrPlan(profileURL: URL) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: ["nostr", "plan", "--profile", profileURL.lastPathComponent],
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris nostr sign --plan PATH --key-stdin --out PATH`.
    /// The key is written to stdin and wiped; it is never in argv or env.
    public func nostrSign(
        planURL: URL,
        outURL: URL,
        secret: SecureBuffer,
        workingDirectory: URL? = nil
    ) async throws -> BorisPublishResult {
        let out = try await run(
            arguments: [
                "nostr", "sign",
                "--plan", planURL.path,
                "--key-stdin",
                "--out", outURL.path,
            ],
            workingDirectory: workingDirectory ?? planURL.deletingLastPathComponent(),
            stdin: secret
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    /// Runs `boris nostr publish --bundle PATH --out PATH`.
    public func nostrPublish(bundleURL: URL, reportURL: URL? = nil) async throws -> BorisPublishResult {
        var args = ["nostr", "publish", "--bundle", bundleURL.path]
        if let reportURL {
            args.append(contentsOf: ["--out", reportURL.path])
        }
        let out = try await run(
            arguments: args,
            workingDirectory: bundleURL.deletingLastPathComponent()
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    // MARK: Kit tools

    /// Runs a standalone kit-tool binary (e.g. `boris-source-rag`) through
    /// the engine's single process slot, so Stop / cancel reaches the tool
    /// too. Output is captured exactly like engine runs; no decoding.
    public func runTool(
        binary: URL,
        arguments: [String],
        workingDirectory: URL? = nil
    ) async throws -> BorisPublishResult {
        let out = try await BorisRunner.run(
            binary: binary,
            arguments: arguments,
            workingDirectory: workingDirectory,
            handle: runHandle
        )
        return BorisPublishResult(exitCode: out.exitCode, stdout: out.stdoutText, stderr: out.stderrText)
    }

    // MARK: Recipe Scale

    /// Runs `boris recipe-scale` (or evaluates scaled Cooklang recipe).
    public func recipeScale(
        contentRoot: URL,
        pageID: String,
        factor: Double = 1.0,
        workingDirectory: URL? = nil,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> BorisRecipeScale {
        var args = [
            "recipe-scale",
            pageID,
            "--scale", "\(factor)",
            "--input", contentRoot.path,
        ]
        if let knobs {
            knobs.apply(to: &args, defaultQuiet: true)
        } else {
            args.append("--quiet")
        }

        let cwd = workingDirectory ?? contentRoot.deletingLastPathComponent()
        let out = try? await run(arguments: args, workingDirectory: cwd)

        if let out, out.exitCode == 0, let recipe = decodeJSON(CookRecipe.self, from: out.stdout) {
            return BorisRecipeScale(
                exitCode: out.exitCode,
                recipe: recipe,
                scale: factor,
                stdout: out.stdoutText,
                stderr: out.stderrText
            )
        }

        // Fallback: evaluate scaling directly from local graph artifact if available
        let graphURL = contentRoot.appendingPathComponent(".boris/graph.json")
        let altGraphURL = cwd.appendingPathComponent(".boris/graph.json")
        let targetGraphURL = FileManager.default.fileExists(atPath: graphURL.path) ? graphURL : altGraphURL
        if FileManager.default.fileExists(atPath: targetGraphURL.path),
           let data = try? Data(contentsOf: targetGraphURL),
           let graph = try? JSONDecoder().decode(Graph.self, from: data),
           let node = graph.nodes.first(where: { $0.id == pageID }),
           let originalRecipe = node.recipe
        {
            let scaled = RecipeScaleHelper.scale(recipe: originalRecipe, factor: factor)
            return BorisRecipeScale(
                exitCode: 0,
                recipe: scaled,
                scale: factor,
                stdout: out?.stdoutText ?? "",
                stderr: out?.stderrText ?? ""
            )
        }

        return BorisRecipeScale(
            exitCode: out?.exitCode ?? 1,
            recipe: nil,
            scale: factor,
            stdout: out?.stdoutText ?? "",
            stderr: out?.stderrText ?? ""
        )
    }

    // MARK: Probe

    /// Sanity probe: runs `boris --help` and returns the first lines.
    public func probe() async throws -> String {
        let out = try await run(arguments: ["--help"])
        let head = out.stdoutText
            .split(separator: "\n")
            .prefix(3)
            .joined(separator: "\n")
        return "exit \(out.exitCode)\n\(head)"
    }

    // MARK: Helpers

    private func run(
        arguments: [String],
        workingDirectory: URL? = nil,
        stdin: SecureBuffer? = nil
    ) async throws -> RunOutput {
        try await BorisRunner.run(
            binary: binaryURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            handle: runHandle,
            stdin: stdin
        )
    }

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

    /// Optional stdout decode (plan / timings). Empty or unknown shape → nil
    /// rather than a crash (D8).
    private func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
