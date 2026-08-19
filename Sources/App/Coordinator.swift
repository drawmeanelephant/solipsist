import AppKit
import Foundation
import Observation

/// Menu verbs against `BorisEngine`. One job at a time. Play and the
/// status bar read this; they do not spawn `boris`.
@MainActor
@Observable
final class Coordinator {
    private(set) var isRunning = false
    private(set) var state: CoordinatorState = .idle
    private(set) var verb: CoordinatorVerb?
    private(set) var lastVerb: CoordinatorVerb?
    private(set) var summary = "idle"
    private(set) var exitCode: Int32?
    private(set) var problems: [ProblemItem] = []
    private(set) var activityHistory: [CoordinatorActivity] = []
    private(set) var latestPlan: PublicationPlan?
    private(set) var latestCheckReport: AnalysisReport?
    private(set) var checkFindings: [AnalysisFinding] = []
    private var jobStartTime: ContinuousClock.Instant?
    private var task: Task<Void, Never>?
    private var reapTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private weak var activeWatch: WatchServer?
    private var watchSuspends = 0
    private var saveGate = SaveValidateGate()
    @ObservationIgnored
    private var saveWatcher = ContentTreeWatcher()
    private var jobOrigin: JobOrigin = .manual
    private var timedOut = false
    private var watchingSourceID: SourceID?
    @ObservationIgnored
    private weak var boundStore: WorkspaceStore?
    @ObservationIgnored
    private weak var boundRuntime: AppRuntime?

    private enum JobOrigin {
        case manual
        case save
    }

    func clearActivity() {
        activityHistory.removeAll()
    }

    var canRunVerb: Bool { state == .idle || state == .watching }

    var canStop: Bool { state != .idle && state != .terminating }

    func registerWatch(_ server: WatchServer) {
        if let old = activeWatch, old !== server {
            old.resume()
            old.stop()
        }
        activeWatch = server
        if !isRunning {
            state = .watching
            if summary == "idle" { summary = "watching" }
        }
    }

    func unregisterWatch(_ server: WatchServer) {
        guard activeWatch === server else { return }
        activeWatch = nil
        watchSuspends = 0
        if !isRunning {
            state = .idle
            if summary == "watching" || summary == "stopping preview…" {
                summary = "idle"
            }
        }
    }

    /// Pause watch for any tree-writing invocation, including play's
    /// implicit IR build. Nested; resume when the last writer ends.
    func beginTreeWrite() {
        watchSuspends += 1
        if watchSuspends == 1 {
            activeWatch?.suspend()
        }
    }

    func endTreeWrite() {
        guard watchSuspends > 0 else { return }
        watchSuspends -= 1
        if watchSuspends == 0 {
            activeWatch?.resume()
        }
    }

    func syncSaveWatch(store: WorkspaceStore, runtime: AppRuntime) {
        boundStore = store
        boundRuntime = runtime
        let folder: (any PlayFolderSource)?
        switch store.selectedSource {
        case .local(let source): folder = source
        case .github(let source): folder = source
        case nil: folder = nil
        }
        guard let folder, folder.isAvailable,
              let root = try? folder.contentRoot(),
              FileManager.default.fileExists(atPath: root.path)
        else {
            saveWatcher.stop()
            watchingSourceID = nil
            return
        }
        guard watchingSourceID != folder.id else { return }
        watchingSourceID = folder.id
        saveWatcher.handler = { [weak self] in
            Task { @MainActor in
                self?.noteSave()
            }
        }
        saveWatcher.start(path: root.path)
    }

    func noteSave() {
        if saveGate.noteSave(now: .now, state: state) == .armDebounce {
            armDebounce()
        }
    }

    func terminateAll(runtime: AppRuntime) {
        saveGate.dropAll()
        debounceTask?.cancel()
        debounceTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        saveWatcher.stop()
        watchingSourceID = nil
        if state != .terminating {
            stop(runtime: runtime)
        }
        runtime.engine?.forceKill()
        activeWatch?.forceKill()
    }

    func run(_ verb: CoordinatorVerb, store: WorkspaceStore, runtime: AppRuntime) {
        start(verb, store: store, runtime: runtime, origin: .manual)
    }

    private func startSaveValidate() {
        guard let store = boundStore, let runtime = boundRuntime else { return }
        start(.validate, store: store, runtime: runtime, origin: .save)
    }

    private func start(
        _ verb: CoordinatorVerb,
        store: WorkspaceStore,
        runtime: AppRuntime,
        origin: JobOrigin
    ) {
        guard canRunVerb else { return }
        guard let engine = runtime.engine else {
            let message = runtime.engineError ?? "engine not found"
            finish(
                verb: verb,
                exit: nil,
                summary: message,
                problems: CoordinatorProblems.fromFailure(code: "engine", message: message)
            )
            return
        }
        guard case .local(let source) = store.selectedSource, source.isAvailable else {
            finish(
                verb: verb,
                exit: nil,
                summary: "no local source",
                problems: CoordinatorProblems.fromFailure(code: "source", message: "no local source")
            )
            return
        }

        let secret: SecureBuffer?
        if let target = verb.secretTarget {
            guard let taken = Self.takeOrPromptSecret(
                for: verb,
                target: target,
                credentials: runtime.credentials
            ) else {
                return
            }
            secret = taken
        } else {
            secret = nil
        }

        if origin == .manual {
            saveGate.manualVerbStarted()
            debounceTask?.cancel()
            debounceTask = nil
        }

        isRunning = true
        state = verb.writesTree ? .building : .validating
        self.verb = verb
        self.lastVerb = verb
        self.jobStartTime = .now
        jobOrigin = origin
        timedOut = false
        summary = "\(verb.rawValue)…"
        exitCode = nil
        problems = []
        if verb.writesTree {
            beginTreeWrite()
        }

        watchdogTask?.cancel()
        watchdogTask = Task { [timeout = verb.timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.handleTimeout(runtime: runtime)
        }

        let startTime = ContinuousClock.now
        let noun = store.selection.noun
        task = Task {
            let result = await Self.perform(
                verb,
                source: source,
                noun: noun,
                engine: engine,
                secret: secret
            )
            if verb == .sourceRag, result.exit == 0, let reveal = result.revealURL {
                NSWorkspace.shared.activateFileViewerSelecting([reveal])
            }
            let elapsed = startTime.duration(to: .now)
            let (secs, attos) = elapsed.components
            let elapsedNs = Int(secs * 1_000_000_000) + Int(attos / 1_000_000_000)
            let durationNs = result.timings?.totalNs ?? result.totalDurationNs ?? elapsedNs

            guard !Task.isCancelled else {
                self.finish(
                    verb: verb,
                    exit: result.exit,
                    summary: "cancelled",
                    problems: result.problems,
                    result: result,
                    durationNs: durationNs
                )
                return
            }
            self.finish(
                verb: verb,
                exit: result.exit,
                summary: result.summary,
                problems: result.problems,
                result: result,
                durationNs: durationNs
            )
        }
    }

    func stop(runtime: AppRuntime) {
        guard state != .terminating else { return }
        reapTask?.cancel()
        watchdogTask?.cancel()

        if isRunning {
            state = .terminating
            summary = timedOut ? "timing out…" : "stopping…"
            task?.cancel()
            let engine = runtime.engine
            reapTask = Task {
                await engine?.escalate()
            }
            return
        }

        guard let watch = activeWatch, watch.isRunning else { return }
        state = .terminating
        summary = "stopping preview…"
        watch.stop()
        reapTask = Task {
            try? await Task.sleep(for: ChildProcessControl.reapGrace)
            guard !Task.isCancelled else { return }
            watch.forceKill()
        }
    }

    private func finish(
        verb: CoordinatorVerb,
        exit: Int32?,
        summary: String,
        problems: [ProblemItem],
        result: JobResult? = nil,
        durationNs: Int? = nil
    ) {
        if verb.writesTree {
            endTreeWrite()
        }
        reapTask?.cancel()
        reapTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil

        let duration = jobStartTime.map { $0.duration(to: .now) } ?? .zero
        jobStartTime = nil
        JobNotificationDispatcher.notifyIfBackgrounded(verb: verb, exit: exit, duration: duration)

        let origin = jobOrigin
        let wasTimeout = timedOut
        timedOut = false
        jobOrigin = .manual

        self.verb = nil
        isRunning = false
        exitCode = exit
        if wasTimeout {
            self.summary = exit.map { "\(verb.rawValue) timed out · exit \($0)" }
                ?? "\(verb.rawValue) timed out"
            self.problems = CoordinatorProblems.fromFailure(
                code: "timeout",
                message: "\(verb.rawValue) exceeded its time limit"
            )
        } else {
            self.summary = summary
            self.problems = problems
        }
        if let plan = result?.plan {
            self.latestPlan = plan
        }
        if let checkReport = result?.checkReport {
            self.latestCheckReport = checkReport
            self.checkFindings = checkReport.findings
        }

        let activity = CoordinatorActivity(
            verb: verb,
            exitCode: exit,
            summary: self.summary,
            timestamp: Date(),
            durationNs: durationNs,
            timings: result?.timings,
            problemsCount: self.problems.count
        )
        activityHistory.insert(activity, at: 0)
        if activityHistory.count > 50 {
            activityHistory.removeLast(activityHistory.count - 50)
        }

        task = nil
        state = (activeWatch?.isRunning == true) ? .watching : .idle

        if origin == .manual, verb == .validate, !wasTimeout {
            saveGate.manualValidateFinished(now: .now, skip: CoordinatorPolicy.manualSkip)
        }
        if saveGate.jobFinished(now: .now, freshness: CoordinatorPolicy.queuedFreshness)
            == .startValidate
        {
            startSaveValidate()
        }
    }

    private func armDebounce() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: CoordinatorPolicy.saveDebounce)
            guard !Task.isCancelled else { return }
            if self.saveGate.debounceFired(now: .now, state: self.state) == .startValidate {
                self.startSaveValidate()
            }
        }
    }

    private func handleTimeout(runtime: AppRuntime) {
        guard isRunning, state != .terminating else { return }
        timedOut = true
        stop(runtime: runtime)
    }

    private struct JobResult: Sendable {
        var exit: Int32?
        var summary: String
        var problems: [ProblemItem]
        var plan: PublicationPlan? = nil
        var checkReport: AnalysisReport? = nil
        var timings: TimingsReport? = nil
        var totalDurationNs: Int? = nil
        /// Set when a job produced a tree the app should surface (Finder reveal).
        var revealURL: URL? = nil
    }

    private static func takeOrPromptSecret(
        for verb: CoordinatorVerb,
        target: String,
        credentials: PublishCredentialManager
    ) -> SecureBuffer? {
        if let existing = credentials.takeSecretForUse(for: target) {
            return existing
        }
        guard let answer = PublishSecretPrompt.present(for: verb) else { return nil }
        do {
            try credentials.setCredential(
                answer.secret,
                for: target,
                rememberInKeychain: answer.rememberInKeychain
            )
        } catch {
            return nil
        }
        return credentials.takeSecretForUse(for: target)
    }

    private static func perform(
        _ verb: CoordinatorVerb,
        source: LocalSource,
        noun: WorkspaceNoun?,
        engine: BorisEngine,
        secret: SecureBuffer?
    ) async -> JobResult {
        let knobs = BorisExecutionKnobs.load()
        do {
            switch verb {
            case .plan:
                guard let profile = source.profileURL() else {
                    return JobResult(
                        exit: 3,
                        summary: "plan: no boris.json",
                        problems: CoordinatorProblems.fromFailure(code: "plan", message: "no boris.json")
                    )
                }
                let result = try await engine.plan(profileURL: profile)
                let summary = result.plan == nil
                    ? "plan exit \(result.exitCode)"
                    : "plan ok (\(result.plan?.format ?? "declaration"))"
                let problems: [ProblemItem]
                if result.plan == nil {
                    problems = CoordinatorProblems.fromCommand(
                        code: "plan",
                        exitCode: result.exitCode == 0 ? 1 : result.exitCode,
                        stderr: result.stderr
                    )
                } else {
                    problems = []
                }
                return JobResult(exit: result.exitCode, summary: summary, problems: problems, plan: result.plan)

            case .validate:
                let reportURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("solipsist-validate-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: reportURL) }
                let result = try await engine.validate(
                    contentRoot: source.contentRoot(),
                    reportURL: reportURL,
                    workingDirectory: try source.workspaceRoot(),
                    knobs: knobs
                )
                var items = CoordinatorProblems.from(report: result.report)
                if items.isEmpty, result.exitCode != 0 {
                    items = CoordinatorProblems.fromCommand(
                        code: "validate",
                        exitCode: result.exitCode,
                        stderr: result.stderr
                    )
                }
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
                    timings: true,
                    knobs: knobs
                )
                var items = CoordinatorProblems.fromIR(report: result.report)
                if items.isEmpty, result.exitCode != 0 {
                    items = CoordinatorProblems.fromCommand(
                        code: "ir",
                        exitCode: result.exitCode,
                        stderr: result.stderr
                    )
                }
                let pages = result.report.pageCount.map { "\($0) pages" } ?? "IR"
                return JobResult(
                    exit: result.exitCode,
                    summary: "IR exit \(result.exitCode) · \(pages) · \(result.report.errorCount ?? items.count) error(s)",
                    problems: items,
                    timings: result.timings,
                    totalDurationNs: result.timings?.totalNs
                )

            case .buildHTML:
                let htmlDir = try source.artifactDirectory(named: "dist")
                let reportURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("solipsist-html-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: reportURL) }
                let result = try await engine.buildHTML(
                    contentRoot: source.contentRoot(),
                    htmlDir: htmlDir,
                    reportURL: reportURL,
                    knobs: knobs
                )
                var items = CoordinatorProblems.from(report: result.report)
                if items.isEmpty, result.exitCode != 0 {
                    items = CoordinatorProblems.fromCommand(
                        code: "html",
                        exitCode: result.exitCode,
                        stderr: result.stderr
                    )
                }
                return JobResult(
                    exit: result.exitCode,
                    summary: "HTML exit \(result.exitCode) · \(result.report?.errorCount ?? items.count) error(s)",
                    problems: items
                )

            case .buildThis:
                return try await buildThis(noun: noun, source: source, engine: engine, knobs: knobs)

            case .buildAll:
                let workspaceRoot = try source.workspaceRoot()
                let profile: PublicationProfile
                do {
                    profile = try loadProfile(from: source)
                        ?? PublicationProfile(format: "boris-publication-profile")
                } catch {
                    return JobResult(
                        exit: 3,
                        summary: "Build all: boris.json did not decode",
                        problems: CoordinatorProblems.fromFailure(
                            code: "profile",
                            message: String(describing: error)
                        )
                    )
                }
                let result = try await engine.buildAll(
                    contentRoot: source.contentRoot(),
                    profile: profile,
                    workingDirectory: workspaceRoot,
                    timings: true,
                    knobs: knobs
                )
                let items = CoordinatorProblems.fromEntries(result.results.map {
                    CoordinatorProblems.EntryProblemSource(
                        name: $0.name,
                        kind: $0.kind,
                        exitCode: $0.exitCode,
                        stderr: $0.stderr,
                        report: $0.report
                    )
                })
                let exit = result.isSuccess ? 0 : (result.results.last?.exitCode ?? 1)
                let dur = result.totalDurationNs.map { "(\($0 / 1_000_000)ms)" } ?? ""
                let summary = "Build all \(result.isSuccess ? "succeeded" : "failed") · \(result.results.count) entry(s) \(dur)"
                return JobResult(exit: exit, summary: summary, problems: items, totalDurationNs: result.totalDurationNs)

            case .check:
                let result = try await engine.check(
                    contentRoot: source.contentRoot(),
                    workingDirectory: try source.workspaceRoot(),
                    knobs: knobs
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
                    problems: items,
                    checkReport: result.report
                )

            case .impact:
                guard let pageID = noun?.kind == "page" ? noun?.id : nil else {
                    return JobResult(
                        exit: 2,
                        summary: "impact: select a page",
                        problems: CoordinatorProblems.fromFailure(
                            code: "impact",
                            message: "select a page"
                        )
                    )
                }
                let result = try await engine.impact(
                    contentRoot: source.contentRoot(),
                    pageID: pageID,
                    workingDirectory: try source.workspaceRoot(),
                    knobs: knobs
                )
                let items = (result.report.impact ?? []).map {
                    ProblemItem(severity: "info", code: $0.type, message: $0.value)
                }
                return JobResult(
                    exit: result.exitCode,
                    summary: "impact \(pageID) · \(items.count) item(s)",
                    problems: items
                )

            case .recipeScale:
                guard let pageID = noun?.kind == "page" ? noun?.id : nil else {
                    return JobResult(
                        exit: 2,
                        summary: "recipe-scale: select a page",
                        problems: CoordinatorProblems.fromFailure(
                            code: "recipe-scale",
                            message: "select a page"
                        )
                    )
                }
                let result = try await engine.recipeScale(
                    contentRoot: source.contentRoot(),
                    pageID: pageID,
                    factor: 1.0,
                    workingDirectory: try source.workspaceRoot(),
                    knobs: knobs
                )
                let count = result.recipe?.ingredients.count ?? 0
                return JobResult(
                    exit: result.exitCode,
                    summary: "recipe-scale \(pageID) · \(count) ingredient(s)",
                    problems: []
                )

            case .publishStandardSite:
                return try await publishStandardSite(source: source, engine: engine, secret: secret)

            case .standardSiteVerify:
                guard let profileURL = source.profileURL() else {
                    return JobResult(
                        exit: 3,
                        summary: "verify: no boris.json",
                        problems: CoordinatorProblems.fromFailure(code: "standard-site", message: "no boris.json")
                    )
                }
                let result = try await engine.standardSiteVerify(profileURL: profileURL)
                let items = CoordinatorProblems.fromCommand(
                    code: "standard-site",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Standard.site verify ok" : "Standard.site verify exit \(result.exitCode)",
                    problems: items
                )

            case .standardSiteRecords:
                guard let profileURL = source.profileURL() else {
                    return JobResult(
                        exit: 3,
                        summary: "records: no boris.json",
                        problems: CoordinatorProblems.fromFailure(code: "standard-site", message: "no boris.json")
                    )
                }
                let result = try await engine.standardSiteRecords(profileURL: profileURL)
                let items = CoordinatorProblems.fromCommand(
                    code: "standard-site",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Standard.site records ok" : "Standard.site records exit \(result.exitCode)",
                    problems: items
                )

            case .standardSiteSessions:
                let result = try await engine.standardSiteSessions(
                    workingDirectory: try source.workspaceRoot()
                )
                let items = CoordinatorProblems.fromCommand(
                    code: "standard-site",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Standard.site sessions ok" : "Standard.site sessions exit \(result.exitCode)",
                    problems: items
                )

            case .standardSiteLogout:
                let result = try await engine.standardSiteLogout(
                    workingDirectory: try source.workspaceRoot()
                )
                let items = CoordinatorProblems.fromCommand(
                    code: "standard-site",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Standard.site logout ok" : "Standard.site logout exit \(result.exitCode)",
                    problems: items
                )

            case .standardSiteSmoke:
                let result = try await engine.standardSiteSmoke(
                    profileURL: source.profileURL(),
                    workingDirectory: try source.workspaceRoot()
                )
                let items = CoordinatorProblems.fromCommand(
                    code: "standard-site",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Standard.site smoke ok" : "Standard.site smoke exit \(result.exitCode)",
                    problems: items
                )

            case .publishNostr:
                return try await publishNostr(source: source, engine: engine, secret: secret)

            case .package:
                let result = try await engine.package(
                    contentRoot: try source.contentRoot(),
                    workingDirectory: try source.workspaceRoot()
                )
                let items = CoordinatorProblems.fromCommand(
                    code: "package",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Package archive ok" : "Package exit \(result.exitCode)",
                    problems: items
                )

            case .sourceRag:
                guard let tool = SourceRagBinary.locate(borisBinary: engine.binaryURL) else {
                    return JobResult(
                        exit: 3,
                        summary: "source RAG: boris-source-rag not found",
                        problems: CoordinatorProblems.fromFailure(
                            code: "source-rag",
                            message: "boris-source-rag binary not found (set SOLIPSIST_SOURCE_RAG_BIN)"
                        )
                    )
                }
                let workspaceRoot = try source.workspaceRoot()
                let outDir = workspaceRoot.appendingPathComponent("source-rag")
                let result = try await engine.runTool(
                    binary: tool,
                    arguments: ["--root", workspaceRoot.path, "--out", outDir.path, "--quiet"],
                    workingDirectory: workspaceRoot
                )
                let items = CoordinatorProblems.fromCommand(
                    code: "source-rag",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Source RAG ok" : "Source RAG exit \(result.exitCode)",
                    problems: items,
                    revealURL: result.exitCode == 0 ? outDir : nil
                )

            case .contentAudit:
                guard let tool = ContentAuditBinary.locate(borisBinary: engine.binaryURL) else {
                    return JobResult(
                        exit: 3,
                        summary: "content audit: boris-content-audit not found",
                        problems: CoordinatorProblems.fromFailure(
                            code: "content-audit",
                            message: "boris-content-audit binary not found (set SOLIPSIST_CONTENT_AUDIT_BIN)"
                        )
                    )
                }
                let workspaceRoot = try source.workspaceRoot()
                let contentRoot = try source.contentRoot()
                let outDir = ContentAuditOutput.directory(for: source)
                try FileManager.default.createDirectory(
                    at: outDir, withIntermediateDirectories: true
                )
                let contentRel = contentRoot.path == workspaceRoot.path
                    ? "."
                    : String(contentRoot.path.dropFirst(workspaceRoot.path.count + 1))
                let result = try await engine.runTool(
                    binary: tool,
                    arguments: [
                        "--mode=poetry",
                        "--root=\(workspaceRoot.path)",
                        "--content-root=\(contentRel)",
                        "--out=\(outDir.path)",
                        "--format=json",
                        "--quiet",
                    ],
                    workingDirectory: workspaceRoot
                )
                let items = CoordinatorProblems.fromCommand(
                    code: "content-audit",
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
                return JobResult(
                    exit: result.exitCode,
                    summary: result.exitCode == 0 ? "Content audit ok" : "Content audit exit \(result.exitCode)",
                    problems: items
                )
            }
        } catch {
            let message = String(describing: error)
            return JobResult(
                exit: nil,
                summary: message,
                problems: CoordinatorProblems.fromFailure(code: "coordinator", message: message)
            )
        }
    }

    private static func buildThis(
        noun: WorkspaceNoun?,
        source: LocalSource,
        engine: BorisEngine,
        knobs: BorisExecutionKnobs? = nil
    ) async throws -> JobResult {
        guard let noun else {
            return JobResult(
                exit: 2,
                summary: "build this: select a target or edition",
                problems: CoordinatorProblems.fromFailure(
                    code: "build",
                    message: "select a target or edition"
                )
            )
        }

        let workspaceRoot = try source.workspaceRoot()
        let profile: PublicationProfile?
        do {
            profile = try loadProfile(from: source)
        } catch {
            return JobResult(
                exit: 3,
                summary: "build this: boris.json did not decode",
                problems: CoordinatorProblems.fromFailure(
                    code: "profile",
                    message: String(describing: error)
                )
            )
        }

        switch noun.kind {
        case "target":
            let target: PublicationTarget
            if let match = profile?.targets?.first(where: { $0.name == noun.id }) {
                target = match
            } else if noun.id == "default" {
                target = PublicationTarget(name: "default", output: "dist")
            } else {
                return JobResult(
                    exit: 2,
                    summary: "build this: no target \"\(noun.id)\"",
                    problems: CoordinatorProblems.fromFailure(
                        code: "target",
                        message: "no target \"\(noun.id)\" in boris.json"
                    )
                )
            }
            let result = try await engine.buildTarget(
                contentRoot: source.contentRoot(),
                target: target,
                siteURL: profile?.site?.url,
                workingDirectory: workspaceRoot,
                timings: true,
                knobs: knobs
            )
            let items = CoordinatorProblems.fromEntry(
                name: result.name,
                kind: result.kind,
                exitCode: result.exitCode,
                stderr: result.stderr,
                report: result.report
            )
            return JobResult(
                exit: result.exitCode,
                summary: "\(target.name) exit \(result.exitCode) · \(items.count) problem(s)",
                problems: items,
                timings: result.timings,
                totalDurationNs: result.timings?.totalNs
            )

        case "edition":
            guard let spec = editionSpec(id: noun.id, profile: profile) else {
                return JobResult(
                    exit: 2,
                    summary: "build this: no \(noun.id) edition in profile",
                    problems: CoordinatorProblems.fromFailure(
                        code: "edition",
                        message: "no \(noun.id) edition in boris.json"
                    )
                )
            }
            let result = try await engine.buildEdition(
                contentRoot: source.contentRoot(),
                kind: spec.kind,
                outputDir: spec.output,
                scope: spec.scope,
                splitSize: spec.splitSize,
                workingDirectory: workspaceRoot,
                timings: true,
                knobs: knobs
            )
            let items = CoordinatorProblems.fromEntry(
                name: result.name,
                kind: result.kind,
                exitCode: result.exitCode,
                stderr: result.stderr,
                report: result.report
            )
            return JobResult(
                exit: result.exitCode,
                summary: "\(spec.kind) exit \(result.exitCode) · \(items.count) problem(s)",
                problems: items,
                timings: result.timings,
                totalDurationNs: result.timings?.totalNs
            )

        default:
            return JobResult(
                exit: 2,
                summary: "build this: select a target or edition",
                problems: CoordinatorProblems.fromFailure(
                    code: "build",
                    message: "select a target or edition"
                )
            )
        }
    }

    private static func publishStandardSite(
        source: LocalSource,
        engine: BorisEngine,
        secret: SecureBuffer?
    ) async throws -> JobResult {
        defer { secret?.wipe() }
        guard let profileURL = source.profileURL() else {
            return JobResult(
                exit: 3,
                summary: "publish: no boris.json",
                problems: CoordinatorProblems.fromFailure(code: "standard-site", message: "no boris.json")
            )
        }
        guard let secret else {
            return JobResult(
                exit: 3,
                summary: "publish: no app password",
                problems: CoordinatorProblems.fromFailure(
                    code: "standard-site",
                    message: "no app password (cancelled or empty)"
                )
            )
        }

        let profile = try loadProfile(from: source)
        let identity = standardSiteIdentity(from: profile?.publication)
        guard identity.did != nil || identity.handle != nil else {
            return JobResult(
                exit: 2,
                summary: "publish: profile needs publication.did",
                problems: CoordinatorProblems.fromFailure(
                    code: "standard-site",
                    message: "publication.did (or a handle) is required for login --app-password"
                )
            )
        }

        let login = try await engine.standardSiteLogin(
            did: identity.did,
            handle: identity.handle,
            password: secret,
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        if login.exitCode != 0 {
            return JobResult(
                exit: login.exitCode,
                summary: "Standard.site login exit \(login.exitCode)",
                problems: CoordinatorProblems.fromCommand(
                    code: "standard-site",
                    exitCode: login.exitCode,
                    stderr: login.stderr
                )
            )
        }

        let published = try await engine.standardSitePublish(profileURL: profileURL)
        return JobResult(
            exit: published.exitCode,
            summary: "Standard.site publish exit \(published.exitCode)",
            problems: CoordinatorProblems.fromCommand(
                code: "standard-site",
                exitCode: published.exitCode,
                stderr: published.stderr
            )
        )
    }

    private static func publishNostr(
        source: LocalSource,
        engine: BorisEngine,
        secret: SecureBuffer?
    ) async throws -> JobResult {
        defer { secret?.wipe() }
        guard let profileURL = source.profileURL() else {
            return JobResult(
                exit: 3,
                summary: "publish: no boris.json",
                problems: CoordinatorProblems.fromFailure(code: "nostr", message: "no boris.json")
            )
        }
        guard let secret else {
            return JobResult(
                exit: 3,
                summary: "publish: no signing key",
                problems: CoordinatorProblems.fromFailure(
                    code: "nostr",
                    message: "no signing key (cancelled or empty)"
                )
            )
        }

        let work = try source.artifactDirectory(named: "_boris")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let planURL = work.appendingPathComponent("nostr-plan.json")
        let bundleURL = work.appendingPathComponent("nostr-bundle.json")
        let reportURL = work.appendingPathComponent("nostr-publish.json")

        let planned = try await engine.nostrPlan(profileURL: profileURL)
        if planned.exitCode != 0 {
            return JobResult(
                exit: planned.exitCode,
                summary: "Nostr plan exit \(planned.exitCode)",
                problems: CoordinatorProblems.fromCommand(
                    code: "nostr",
                    exitCode: planned.exitCode,
                    stderr: planned.stderr
                )
            )
        }
        try Data(planned.stdout.utf8).write(to: planURL, options: .atomic)

        let signed = try await engine.nostrSign(
            planURL: planURL,
            outURL: bundleURL,
            secret: secret,
            workingDirectory: profileURL.deletingLastPathComponent()
        )
        if signed.exitCode != 0 {
            return JobResult(
                exit: signed.exitCode,
                summary: "Nostr sign exit \(signed.exitCode)",
                problems: CoordinatorProblems.fromCommand(
                    code: "nostr",
                    exitCode: signed.exitCode,
                    stderr: signed.stderr
                )
            )
        }

        let published = try await engine.nostrPublish(bundleURL: bundleURL, reportURL: reportURL)
        var items: [ProblemItem] = []
        var summaryText = "Nostr publish exit \(published.exitCode)"
        let reportData = (try? Data(contentsOf: reportURL)) ?? (published.stdout.isEmpty ? nil : Data(published.stdout.utf8))
        if let reportData,
           let report = try? JSONDecoder().decode(NostrPublishReport.self, from: reportData) {
            if let verdict = report.verdict {
                summaryText = "Nostr publish \(verdict) (exit \(published.exitCode))"
            }
            if let relays = report.relays {
                for relay in relays {
                    let isOk = relay.isSuccess
                    let severity = isOk ? "info" : "error"
                    items.append(ProblemItem(
                        severity: severity,
                        code: "nostr-relay",
                        message: "\(relay.relayURL): \(relay.displayMessage)"
                    ))
                }
            }
        }
        if items.isEmpty, published.exitCode != 0 {
            items = CoordinatorProblems.fromCommand(
                code: "nostr",
                exitCode: published.exitCode,
                stderr: published.stderr
            )
        }
        return JobResult(
            exit: published.exitCode,
            summary: summaryText,
            problems: items
        )
    }

    private static func standardSiteIdentity(
        from publication: PublicationDeclaration?
    ) -> (did: String?, handle: String?) {
        guard let raw = publication?.did?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return (nil, nil) }
        if raw.hasPrefix("did:") {
            return (raw, nil)
        }
        return (nil, raw)
    }

    private static func loadProfile(from source: LocalSource) throws -> PublicationProfile? {
        let root = try source.workspaceRoot()
        guard let pair = try InspectorProfile.load(from: root) else { return nil }
        return try JSONDecoder().decode(PublicationProfile.self, from: pair.data)
    }

    private struct EditionSpec {
        var kind: String
        var output: String
        var scope: String?
        var splitSize: Int?
    }

    private static func editionSpec(id: String, profile: PublicationProfile?) -> EditionSpec? {
        switch id {
        case "ir":
            guard let output = profile?.editions?.ir?.output else { return nil }
            return EditionSpec(kind: "ir", output: output)
        case "rag":
            guard let rag = profile?.editions?.rag else { return nil }
            return EditionSpec(kind: "rag", output: rag.output, scope: rag.scope, splitSize: rag.split_size)
        case "context":
            guard let context = profile?.editions?.context else { return nil }
            return EditionSpec(
                kind: "context",
                output: context.output,
                scope: context.scope,
                splitSize: context.split_size
            )
        default:
            return nil
        }
    }
}
