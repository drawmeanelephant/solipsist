import Foundation

// Solipsist M1 / M4-S0 engine spike.
//
//   1. locate the `boris` binary (SOLIPSIST_BORIS_BIN, app bundle, or the
//      dev checkout at ../boris)
//   2. print `boris --version`
//   3. attempt `boris plan --profile` (do not invent a profile)
//   4. run `boris validate --report` and decode html-build-report-0.1.0
//   5. run an IR build (with --timings); decode IR artifacts + completion
//   6. run `boris check` and `boris impact`, decode the reports
//   7. print a human-readable summary
//
// Usage:
//   boris-spike [content-root]
//   (default content root: ../boris/content relative to the working directory)

// Unbuffered stdout so progress lines survive a crash mid-run.
setvbuf(stdout, nil, _IONBF, 0)

let fm = FileManager.default

guard let binary = BorisBinary.locate() else {
    FileHandle.standardError.write(Data("error: \(BorisRunnerError.binaryNotFound)\n".utf8))
    exit(2)
}

let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let contentRoot: URL
if CommandLine.arguments.count > 1 {
    contentRoot = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
} else {
    contentRoot = cwd.appendingPathComponent("../boris/content").standardizedFileURL
}

guard fm.fileExists(atPath: contentRoot.path) else {
    FileHandle.standardError.write(
        Data("error: content root not found: \(contentRoot.path)\n".utf8)
    )
    exit(2)
}

let engine = try BorisEngine(binaryURL: binary)
print("boris binary : \(binary.path)")
print("content root : \(contentRoot.path)")

// --- 0. version -----------------------------------------------------------
print("\n== boris --version ==")
let version = try await engine.version()
print("version      : \(version.line)")
print("exit code    : \(version.exitCode)")

// --- 0b. plan -------------------------------------------------------------
// Use a real profile if one sits next to (or inside) the content root.
// Dogfood may have none — still invoke plan and surface the exit; never
// write a fake boris.json.
let profileURL: URL
if fm.fileExists(atPath: contentRoot.appendingPathComponent("boris.json").path) {
    profileURL = contentRoot.appendingPathComponent("boris.json")
} else if fm.fileExists(atPath: contentRoot.deletingLastPathComponent().appendingPathComponent("boris.json").path) {
    profileURL = contentRoot.deletingLastPathComponent().appendingPathComponent("boris.json")
} else {
    profileURL = contentRoot.appendingPathComponent("boris.json")
}
print("\n== boris plan --profile \(profileURL.lastPathComponent) ==")
print("profile      : \(profileURL.path) (exists: \(fm.fileExists(atPath: profileURL.path)))")
let planned = try await engine.plan(profileURL: profileURL)
print("exit code    : \(planned.exitCode)")
if let plan = planned.plan {
    print("format       : \(plan.format)")
    print("schema       : \(plan.schema_version.map(String.init) ?? "n/a")")
    print("input        : \(plan.input ?? "n/a")")
    print("input_format : \(plan.input_format ?? "n/a")")
    print("targets      : \(plan.targets?.count ?? 0)")
} else {
    let err = planned.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if !err.isEmpty {
        print("stderr       : \(err)")
    }
    let out = planned.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !out.isEmpty {
        print("stdout       : \(out)")
    }
}

// --- 0c. validate --report ------------------------------------------------
let validateReportURL = fm.temporaryDirectory
    .appendingPathComponent("solipsist-spike-validate-\(UUID().uuidString).json")
defer { try? fm.removeItem(at: validateReportURL) }
print("\n== boris validate --input … --report ==")
let validated = try await engine.validate(
    contentRoot: contentRoot,
    reportURL: validateReportURL
)
print("exit code    : \(validated.exitCode)")
if let report = validated.report {
    print("ok           : \(report.ok)")
    print("schema       : \(report.schemaVersion)")
    print("compilerId   : \(report.compilerId ?? "n/a")")
    print("errors       : \(report.errorCount ?? -1)")
    for d in report.diagnostics {
        let loc = "\(d.sourcePath ?? "-"):\(d.line.map(String.init) ?? "-"):\(d.column.map(String.init) ?? "-")"
        print("  [\(d.severity)] \(d.code) \(loc) \(d.message)")
    }
} else {
    print("report       : not written")
    let err = validated.stderr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    if !err.isEmpty {
        print("stderr       : \(err)")
    }
}

// --- 1. IR build ----------------------------------------------------------
let outDir = fm.temporaryDirectory.appendingPathComponent("solipsist-spike-\(UUID().uuidString)")
defer { try? fm.removeItem(at: outDir) }

print("\n== IR build (boris --out … --input … --quiet --timings) ==")
let build = try await engine.buildIR(contentRoot: contentRoot, outDir: outDir, timings: true)
print("exit code    : \(build.exitCode)")
print("ok           : \(build.report.ok)")
print("schema       : \(build.report.schemaVersion)")
print("compiler     : \(build.report.compiler ?? "n/a")")
print("pages        : \(build.report.pageCount ?? -1)")
print("errors       : \(build.report.errorCount ?? -1)")
for d in build.report.diagnostics {
    let loc = "\(d.sourcePath ?? "-"):\(d.line.map(String.init) ?? "-"):\(d.column.map(String.init) ?? "-")"
    print("  [\(d.severity)] \(d.code) \(loc) \(d.message)")
}

if let manifest = build.manifest {
    print("\n== manifest.json ==")
    print("pages: \(manifest.pages.count)")
    let trunks = manifest.pages.filter { $0.isTrunk }
    let satellites = manifest.pages.filter { !$0.isTrunk }
    print("trunks: \(trunks.count), satellites: \(satellites.count)")
    for trunk in trunks {
        let kids = satellites.filter { $0.parent == trunk.id }
        print("  \(trunk.id) [\(trunk.status)] — \(kids.count) satellite(s)")
        for kid in kids.prefix(3) {
            print("      \(kid.id)")
        }
        if kids.count > 3 {
            print("      … (\(kids.count - 3) more)")
        }
    }
}

if let graph = build.graph {
    print("\n== graph.json ==")
    print("frozen       : \(graph.frozen)")
    print("nodes        : \(graph.nodes.count)")
    print("edges        : \(graph.edges.count)")
    print("reverseIndex : \(graph.reverseIndex.count) entries")
    print("nav          : \(graph.nav.count) entries")
    if let first = graph.edges.first {
        print("sample edge  : \(first.from.value) -(\(first.kind))-> \(first.to.value)")
    }
}

if let completion = build.completion {
    print("\n== completion.json ==")
    print("format       : \(completion.format)")
    print("schema       : \(completion.schema_version.map(String.init) ?? "n/a")")
    print("compiler_id  : \(completion.compiler_id ?? "n/a")")
    print("frozen       : \(completion.frozen.map { $0 ? "true" : "false" } ?? "n/a")")
    print("entities     : \(completion.entities.count)")
    print("relation_kinds: \(completion.relation_kinds.joined(separator: ", "))")
    print("parent_targets: \(completion.parent_targets.count)")
    print("layout_slots : \(completion.layout_slots.count)")
}

if let timings = build.timings {
    print("\n== boris-timings ==")
    print("format       : \(timings.format)")
    print("schema       : \(timings.schemaVersion ?? "n/a")")
    print("mode         : \(timings.mode ?? "n/a")")
    print("totalNs      : \(timings.totalNs.map(String.init) ?? "n/a")")
    if let phases = timings.phases {
        let names = phases.keys.sorted().joined(separator: ", ")
        print("phases       : \(names)")
    }
}

// --- 2. check -------------------------------------------------------------
print("\n== boris check --format json ==")
let check = try await engine.check(contentRoot: contentRoot)
// `check` exits 1 when it finds unreferenced pages — expected here (the
// sample site has one), so don't treat it as a hard failure.
print("exit code    : \(check.exitCode) (1 only with --fail-on-unreferenced on afterparty)")
let s = check.report.summary
print("summary      : \(s.pages) pages, \(s.roots) trunks, \(s.satellites) satellites, \(s.unreferencedPages) unreferenced, \(s.hotspots) hotspots")
for f in check.report.findings {
    print("  finding: \(f.code) \(f.type)=\(f.value) (count \(f.count))")
}

// --- 3. impact ------------------------------------------------------------
print("\n== boris impact getting-started --format json ==")
let impact = try await engine.impact(contentRoot: contentRoot, pageID: "getting-started")
print("exit code    : \(impact.exitCode)")
if let pages = impact.report.impact {
    print("impact set   : \(pages.count) item(s)")
    for p in pages.prefix(5) {
        print("  \(p.type): \(p.value)")
    }
    if pages.count > 5 {
        print("  … (\(pages.count - 5) more)")
    }
}

// --- 4. watch --serve (M4 preview surface, D5) ----------------------------
// Spin up a live watch server on the spike's content root, wait for the
// ephemeral port line, then SIGTERM it and expect a graceful exit (A12).
print("\n== boris watch --serve: start → port line → stop ==")
// cwd must be the project folder so workspace-relative layouts/themes
// resolve (D1); --input may be absolute. Mirror the app's LocalSource logic:
let watchProjectRoot: URL =
    fm.fileExists(atPath: contentRoot.appendingPathComponent("layouts").path)
    ? contentRoot
    : contentRoot.deletingLastPathComponent()
let watchServer = try engine.previewStart(
    contentRoot: contentRoot,
    workingDirectory: watchProjectRoot,
    port: 0
)
let serveURL: URL? = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
    watchServer.onServe = { url in continuation.resume(returning: url) }
}
guard let serveURL else {
    FileHandle.standardError.write(Data("error: watch --serve printed no port line\n".utf8))
    watchServer.stop()
    exit(2)
}
print("serve url    : \(serveURL.absoluteString)")
let stopExit: Int32 = await withCheckedContinuation {
    (continuation: CheckedContinuation<Int32, Never>) in
    watchServer.onExit = { exit in continuation.resume(returning: exit.exitCode) }
    watchServer.stop()
}
print("stop exit    : \(stopExit) (0 = graceful SIGTERM, A12)")

print("\nSPIKE OK — all Boris JSON contracts decoded.")
exit(build.exitCode)
