import Foundation
import Observation

enum CoordinatorVerb: String, Sendable {
    case plan
    case validate
    case buildIR
    case buildHTML
    case buildAll
    case check
    case impact
    case publishStandardSite = "publish Standard.site"
    case publishNostr = "publish Nostr"
}

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

/// Menu verbs against `BorisEngine`. One job at a time. Play and the
/// status bar read this; they do not spawn `boris`.
@MainActor
@Observable
final class Coordinator {
    private(set) var isRunning = false
    private(set) var verb: CoordinatorVerb?
    private(set) var summary = "idle"
    private(set) var exitCode: Int32?
    private(set) var problems: [ProblemItem] = []
    private var task: Task<Void, Never>?

    func run(_ verb: CoordinatorVerb, store: WorkspaceStore, runtime: AppRuntime) {
        guard !isRunning else { return }
        guard let engine = runtime.engine else {
            finish(
                verb: verb,
                exit: nil,
                summary: runtime.engineError ?? "engine not found",
                problems: []
            )
            return
        }
        guard case .local(let source) = store.selectedSource, source.isAvailable else {
            finish(verb: verb, exit: nil, summary: "no local source", problems: [])
            return
        }

        isRunning = true
        self.verb = verb
        summary = "\(verb.rawValue)…"
        exitCode = nil
        problems = []

        let pageID = store.selection.noun?.kind == "page" ? store.selection.noun?.id : nil
        task = Task {
            let result = await Self.perform(verb, source: source, pageID: pageID, engine: engine)
            guard !Task.isCancelled else {
                self.finish(verb: verb, exit: result.exit, summary: "cancelled", problems: result.problems)
                return
            }
            self.finish(
                verb: verb,
                exit: result.exit,
                summary: result.summary,
                problems: result.problems
            )
        }
    }

    func stop(runtime: AppRuntime) {
        task?.cancel()
        task = nil
        if let engine = runtime.engine {
            Task { await engine.interrupt() }
        }
        if isRunning {
            summary = "stopping…"
        }
    }

    private func finish(
        verb: CoordinatorVerb,
        exit: Int32?,
        summary: String,
        problems: [ProblemItem]
    ) {
        self.verb = nil
        isRunning = false
        exitCode = exit
        self.summary = summary
        self.problems = problems
        task = nil
    }

    private struct JobResult: Sendable {
        var exit: Int32?
        var summary: String
        var problems: [ProblemItem]
    }

    private static func perform(
        _ verb: CoordinatorVerb,
        source: LocalSource,
        pageID: String?,
        engine: BorisEngine
    ) async -> JobResult {
        do {
            switch verb {
            case .plan:
                guard let profile = source.profileURL() else {
                    return JobResult(exit: 3, summary: "plan: no boris.json", problems: [])
                }
                let result = try await engine.plan(profileURL: profile)
                let summary = result.plan == nil
                    ? "plan exit \(result.exitCode)"
                    : "plan ok (\(result.plan?.format ?? "declaration"))"
                let problems: [ProblemItem]
                if result.plan == nil, !result.stderr.isEmpty {
                    problems = [
                        ProblemItem(
                            severity: "error",
                            code: "plan",
                            message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    ]
                } else {
                    problems = []
                }
                return JobResult(exit: result.exitCode, summary: summary, problems: problems)

            case .validate:
                let reportURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("solipsist-validate-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: reportURL) }
                let result = try await engine.validate(
                    contentRoot: source.contentRoot(),
                    reportURL: reportURL,
                    workingDirectory: try source.workspaceRoot()
                )
                let items = Self.problems(from: result.report)
                let count = result.report?.errorCount ?? items.filter { $0.severity == "error" }.count
                return JobResult(
                    exit: result.exitCode,
                    summary: "validate exit \(result.exitCode) · \(count) error(s)",
                    problems: items
                )

            case .buildIR:
                let outDir = try source.artifactDirectory(named: ".boris")
                let result = try await engine.buildIR(
                    contentRoot: source.contentRoot(),
                    outDir: outDir,
                    timings: true
                )
                let items = result.report.diagnostics.map(Self.problem(from:))
                let pages = result.report.pageCount.map { "\($0) pages" } ?? "IR"
                return JobResult(
                    exit: result.exitCode,
                    summary: "IR exit \(result.exitCode) · \(pages) · \(result.report.errorCount ?? items.count) error(s)",
                    problems: items
                )

            case .buildHTML:
                let htmlDir = try source.artifactDirectory(named: "dist")
                let reportURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("solipsist-html-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: reportURL) }
                let result = try await engine.buildHTML(
                    contentRoot: source.contentRoot(),
                    htmlDir: htmlDir,
                    reportURL: reportURL
                )
                let items = Self.problems(from: result.report)
                return JobResult(
                    exit: result.exitCode,
                    summary: "HTML exit \(result.exitCode) · \(result.report?.errorCount ?? items.count) error(s)",
                    problems: items
                )

            case .buildAll:
                let workspaceRoot = try source.workspaceRoot()
                var profile = PublicationProfile(format: "boris-publication-profile")
                if let pair = try InspectorProfile.load(from: workspaceRoot),
                   let prof = try? JSONDecoder().decode(PublicationProfile.self, from: pair.data)
                {
                    profile = prof
                }
                let result = try await engine.buildAll(
                    contentRoot: source.contentRoot(),
                    profile: profile,
                    workingDirectory: workspaceRoot,
                    timings: true
                )
                var items: [ProblemItem] = []
                for res in result.results {
                    if let report = res.report {
                        items.append(contentsOf: Self.problems(from: report))
                    }
                }
                let exit = result.isSuccess ? 0 : (result.results.last?.exitCode ?? 1)
                let dur = result.totalDurationNs.map { "(\($0 / 1_000_000)ms)" } ?? ""
                let summary = "Build all \(result.isSuccess ? "succeeded" : "failed") · \(result.results.count) entry(s) \(dur)"
                return JobResult(exit: exit, summary: summary, problems: items)

            case .check:
                let result = try await engine.check(
                    contentRoot: source.contentRoot(),
                    workingDirectory: try source.workspaceRoot()
                )
                let items = result.report.findings.map {
                    ProblemItem(
                        severity: "info",
                        code: $0.code,
                        message: "\($0.type) \($0.value) (count \($0.count))"
                    )
                }
                let s = result.report.summary
                return JobResult(
                    exit: result.exitCode,
                    summary: "check exit \(result.exitCode) · \(s.pages) pages · \(s.unreferencedPages) unreferenced",
                    problems: items
                )

            case .impact:
                guard let pageID else {
                    return JobResult(exit: 2, summary: "impact: select a page", problems: [])
                }
                let result = try await engine.impact(
                    contentRoot: source.contentRoot(),
                    pageID: pageID,
                    workingDirectory: try source.workspaceRoot()
                )
                let items = (result.report.impact ?? []).map {
                    ProblemItem(severity: "info", code: $0.type, message: $0.value)
                }
                return JobResult(
                    exit: result.exitCode,
                    summary: "impact \(pageID) · \(items.count) item(s)",
                    problems: items
                )

            case .publishStandardSite:
                guard let profile = source.profileURL() else {
                    return JobResult(exit: 3, summary: "publish: no boris.json", problems: [])
                }
                let result = try await engine.standardSitePublish(profileURL: profile)
                let problems = result.exitCode == 0 ? [] : [
                    ProblemItem(severity: "error", code: "standard-site", message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                ]
                return JobResult(
                    exit: result.exitCode,
                    summary: "Standard.site exit \(result.exitCode)",
                    problems: problems
                )

            case .publishNostr:
                guard let profile = source.profileURL() else {
                    return JobResult(exit: 3, summary: "publish: no boris.json", problems: [])
                }
                let result = try await engine.nostrPlan(profileURL: profile)
                let problems = result.exitCode == 0 ? [] : [
                    ProblemItem(severity: "error", code: "nostr", message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                ]
                return JobResult(
                    exit: result.exitCode,
                    summary: "Nostr plan exit \(result.exitCode)",
                    problems: problems
                )
            }
        } catch {
            return JobResult(exit: nil, summary: String(describing: error), problems: [])
        }
    }

    private static func problems(from report: HTMLBuildReport?) -> [ProblemItem] {
        (report?.diagnostics ?? []).map(problem(from:))
    }

    private static func problem(from diagnostic: Diagnostic) -> ProblemItem {
        ProblemItem(
            severity: diagnostic.severity,
            code: diagnostic.code,
            message: diagnostic.message,
            path: diagnostic.sourcePath,
            line: diagnostic.line,
            column: diagnostic.column
        )
    }
}
