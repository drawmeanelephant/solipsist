# Solipsist — macOS App Plan ("Boris Desktop")

**Date:** 2026-08-17
**Author:** Codebuff exploration session (both repos cloned, Boris built & verified locally)
**Status:** Planning document — no app code written yet

---

## 1. TL;DR — what we're building

**Solipsist** is a native **macOS Swift/SwiftUI application** that wraps
**[Boris](https://github.com/drawmeanelephant/boris)** — a deterministic
Zig documentation compiler — as its engine, giving a GUI for authoring,
validating, previewing, and publishing Boris content sites.

- **Solipsist repo today:** empty scaffold (MIT license + Xcode `.gitignore`).
  It is clearly *intended* to be the Swift/Xcode repo — the `.gitignore`
  is already the Xcode one.
- **Boris repo today:** v0.8.0, mature. Builds **natively on macOS arm64**
  (verified this session: `zig build` → `Mach-O 64-bit executable arm64`).
  Ships HTML site output, JSON IR, RAG, AI Context Bundles, `llms.txt`,
  `check`/`impact` analysis commands, incremental builds, watch mode,
  multi-target HTML, closed themes, and machine-readable diagnostics.
- **Feasibility verdict: HIGH.** Boris already has everything a desktop app
  needs as a subprocess backend: a typed CLI, deterministic JSON contracts,
  a watch mode with debounce/coalescing, and stable exit codes. The app is
  "frontend plumbing": run the binary, parse its JSON, watch its output,
  edit Markdown, preview HTML.

The rest of this document is the exploration report and the implementation
plan. Nothing here is set in stone — open questions are flagged in
[§8](#8-risks--open-questions).

---

## 2. What exists today

### 2.1 Solipsist — the (empty) app repo

| Item | Value |
|------|-------|
| URL | `https://github.com/drawmeanelephant/solipsist.git` |
| Latest commit | `52cc6b0 Initial commit` |
| Files | `LICENSE` (MIT, "draw me an elephant"), `.gitignore` |
| `.gitignore` | Full Xcode/Swift ignore set (xcuserdata, .build, *.dSYM, etc.) |
| Branch | `main` only |

There is **no code, no README, no Xcode project**. This is a clean slate.

### 2.2 Boris — the engine

| Item | Value |
|------|-------|
| URL | `https://github.com/drawmeanelephant/boris.git` |
| HEAD | `e65e674` (merge of `codex/v080-release`) — product **v0.8.0** |
| Language | Zig 0.16+, single native binary |
| IR schema | `0.2.0`, compiler id `boris/0.8.0` |
| Branches | `main`, `afterparty` (has v0.8.1 changelog reassembly) |

**What Boris is** (from its README): *"a deterministic documentation compiler
and static-site generator. It turns Markdown into a validated static site,
then can export the same content graph as JSON IR, RAG, an AI Context Bundle,
or llms.txt."*

Pipeline: `Markdown + frontmatter → discover → validate graph → render →
{ HTML site | JSON IR | RAG corpus | AI Context Bundle | llms.txt }`

**Content model:** *Trunks* (primary pages, no `parent`) and *Satellites*
(pages with exactly one `parent` naming a Trunk). One-level forest. In-page
`<Aside>`/`<Details>` components. Closed frontmatter grammar (deliberately
**not** general YAML). Broken parents, wiki-links, headings, includes, and
cycles fail with structured diagnostics instead of silently producing a
broken site.

**Verified locally this session:**

```
zig build                 → OK (builds vendored ApexMarkdown C ABI via CMake)
./zig-out/bin/boris       → Mach-O 64-bit executable arm64 (6.2 MB)
./zig-out/bin/boris --quiet → dist/ HTML site (45 pages)
./zig-out/bin/boris --out .boris --quiet → .boris/{manifest,graph,build-report}.json
./zig-out/bin/boris check --format json  → full documentation-intelligence report
```

Toolchain present on this machine: macOS 27.0 (arm64), Xcode 27.0 (Swift 6.4),
Zig 0.16.x at `/opt/homebrew/bin/zig`, CMake at `/opt/local/bin/cmake`.
Boris CI runs `macos-latest` — macOS is an officially supported build target.

---

## 3. The product vision

Solipsist = **a native Mac app for working with a Boris content site.**
No Node, no browser tab, no terminal required. Modeled after apps like
Obsidian, Notion, and static-site managers:

### Core features (v1 target)

1. **Open / create a Boris project** — a folder containing `content/`,
   `layouts/`, and app settings. Security-scoped access.
2. **Project tree sidebar** — Trunk/Satellite hierarchy from `manifest.json`
   / `graph.json`, with status badges (`published`, `draft`, etc.), tags,
   and unreferenced-page warnings.
3. **Markdown editor** — built-in editor with frontmatter awareness
   (title/parent/status/tags), wiki-link and include syntax support.
   (Fallback v1 option: open files in an external editor, app just watches.)
4. **Live preview** — `WKWebView` showing the rendered HTML site, refreshed
   on rebuild. Powered by Boris `--watch --incremental`.
5. **Diagnostics panel** — parse `build-report.json` / watch stderr into a
   clickable error list (severity, code, message, remediation, source
   path:line:column) that jumps to the offending line.
6. **Build controls** — Build (HTML), Check (graph health), Impact (per-page
   transitive impact), and export actions: JSON IR, RAG, Context Bundle,
   `llms.txt`.
7. **Theme picker** — choose a `--theme ROOT` (Boris ships several themes
   under `examples/`), set layout rules, multi-target outputs.
8. **Status bar** — last build result, page count, error count, watch state.
9. **App menu integration** — recent projects, keyboard shortcuts, macOS
   conventions (window restoration, open documents, etc.).

### Out of scope for v1 (flag for later)

- Publishing/deployment to hosting (could wrap `boris-package` archive).
- The migration labs (`tools/migration-lab`) — CLI developer tools.
- Building Boris from inside the app (dev-time only).
- iOS version.

---

## 4. Integration architecture

### 4.1 The decision: Boris runs as a subprocess, not a library

**Recommended:** Solipsist bundles the compiled `boris` binary and drives it
as a child `Process`. We parse its JSON contracts and stderr lines.

**Alternatives considered:**

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Subprocess + JSON contracts** | Zero language interop; contracts are stable & versioned; watch mode already exists; process isolation (a buggy compile can't crash the app); easy to update engine by swapping binary | Need to manage process lifecycle; parse JSON | ✅ **Chosen** |
| Embed as Zig static lib via C ABI | No process overhead; in-process compile state | Boris has no public library API today (only `main.zig` CLI); ApexMarkdown C ABI is internal; couples app to Zig toolchain; much more work | ❌ Later possibility, not v1 |
| Reimplement Boris in Swift | Full control | It's a mature, tested, contract-heavy compiler (~dozens of Zig modules, vendored C markdown engine). Reimplementation would be months of work and lose determinism guarantees | ❌ Never, that's the whole point of the "Content Exit Hatch" |

The subprocess boundary is *exactly* what Boris was designed for: a
"local Zig binary" with machine-readable output. We stay on the right side
of every hard contract.

### 4.2 Boris binary provisioning

**Development:** a build phase / Make target that runs `zig build` in the
boris checkout and copies `zig-out/bin/boris` (arm64) into the app's
`Resources/`. Version-pin the boris commit the app is tested against.

**Shipping:** `boris` goes in the app bundle as an embedded, signed helper
binary. Xcode signs nested code automatically when the binary is included
via Copy Bundle Resources / a copy phase; verify with
`codesign -dv --verbose=4` and `spctl`. Because Boris links ApexMarkdown
**statically**, the shipped binary has no dylib dependencies to worry about
(big win — no `DYLD`/`@rpath` pain).

**Sandbox note:** the app runs the embedded binary with no network, so
`com.apple.security.network.client` is only needed if preview pages load
remote fonts/CDN assets (see §7).

**Architecture note:** `boris-package` and `boris-source-rag` are separate
binaries in the same build. v1 needs only `boris`; keep the others as
optional later (publishing, source-RAG upload).

### 4.3 Process management spec

Swift `Process` (Foundation) drives Boris. Key requirements:

- **One-shot builds** (Build / Check / Impact / IR / RAG / Context / llms):
  spawn, stream stdout/stderr into buffers, wait with timeout, parse exit
  code, read output artifacts.
- **Watch session** (Live preview): one long-lived `Process` running
  `boris --watch --incremental --html-dir <dist>`; stdout/stderr drained
  asynchronously (never block on a full pipe — use `readabilityHandler`);
  terminate cleanly on stop; kill + restart on project settings change.
- **Exit code mapping** (from Boris contract):
  - `0` success
  - `1` content validation failure (diagnostics in `build-report.json`)
  - `2` usage error (should never happen from the app — means we built a
    bad command line; surface as an app bug)
  - `3` I/O/system failure
- **Command construction:** all paths absolute; `--input`, `--html-dir`,
  `--out`, `--rag-dir`, `--context-dir`, `--llms-path` point inside the
  user-selected project folder (see §4.7).
- **Quiet mode:** pass `--quiet` and rely on JSON artifacts + our own UI;
  keep stderr only for watch status lines and unexpected errors.
- **Timeout:** builds should be fast (incremental), but guard with a
  generous timeout and a "Cancel" button that terminates the process.

**Watch stderr lines the app should parse** (from `src/watch.zig`):

```
watch: initial build succeeded (N pages written). Starting watcher...
watch: changed paths detected:
  - <path>
watch: triggering incremental rebuild...
watch: selective rebuild of N/M target(s)
watch: rebuild succeeded.
error: rebuild failed: <err>. Waiting for correction...
watch: received shutdown signal, cleaning resources...
```

Plus diagnostics lines in text form:
`error: EDUPLICATEID: beta.md:1:1: duplicate id "shared" (also alpha.md)`

### 4.4 JSON contracts to parse (real samples from this session)

**`build-report.json`** — always written on compile attempt. The app's
single source of truth for build success/failure:

```json
{
  "schemaVersion": "0.2.0",
  "ok": true,
  "contentRoot": "content",
  "outDir": ".boris",
  "pageCount": 45,
  "errorCount": 0,
  "diagnostics": []
}
```

**`manifest.json`** — page summaries, sorted by id (drives the sidebar):

```json
{
  "schemaVersion": "0.2.0",
  "compiler": "boris/0.8.0",
  "contentRoot": "content",
  "pageCount": 45,
  "pages": [
    {
      "index": 0,
      "id": "agents",
      "sourcePath": "agents/index.md",
      "role": "trunk",
      "parent": null,
      "title": "Agent Field Notes",
      "status": "published"
    }
  ]
}
```

**`graph.json`** — full frozen graph: nodes (`id`, `sourcePath`, `role`,
`parent`, `parentIndex`, `title`, `status`, `tags`, `bodyOffset`), typed
edges (`parent` / `include` / `reference`), deterministic `reverseIndex`,
and `nav`. Only published when `ok: true` and `frozen: true`.

**Diagnostics** (in `build-report.json`), closed field order:
`severity, code, message, remediation, sourcePath, line, column, id`.
Severities: `error | warning | info`. Codes are a stable closed set
(`EDUPLICATEID`, `EPARENTMISSING`, `EPARENTSELF`, `EPARENTNOTTRUNK`,
`EPARENTCYCLE`, `EFRONTMATTER`, `EINVALIDUTF8`, `EINVALIDPATH`, `ETEXTILE`,
`ECOMPONENT`, `EINCLUDESYNTAX`, `EINCLUDEMISSING`, `EINCLUDECYCLE`,
`EREFERENCESYNTAX`, `EREFERENCEMISSING`, `ERELATIONMISSING`,
`ERELATIONSELF`, `ERELATIONDUPLICATE`, `EASSET`, `EUSAGE`, `EIO`).

**Analysis reports** (`boris check` / `boris impact`, `--format json`):
`format: "boris-documentation-intelligence"`, `schemaVersion 0.1.0`,
`summary { pages, roots, satellites, sourceEndpoints, unreferencedPages,
hotspots }`, `pages`, `sources`, `findings`, `impact`. Great for a
"graph health" panel.

**Note on IR body text:** v0.2 IR deliberately does **not** include page
bodies — nodes carry `bodyOffset` only. For preview we use the rendered
HTML site, not the IR.

### 4.5 File watching strategy

Two options, not mutually exclusive:

1. **Let Boris watch** (recommended for preview): run
   `boris --watch --incremental --html-dir <dist>`. Boris owns debounce
   (100ms coalesce window), idle polling (500ms), self-trigger protection
   (ignores output dirs, `.boris-cache`, staging trees), and rebuild
   serialization. This is the battle-tested path.
2. **App-side watcher** (for editor integration / non-HTML modes): use
   `DispatchSource.makeFileSystemObjectSource` or `FSEventStream` to watch
   `content/` for our own refresh of the tree/diagnostics while a one-shot
   IR build runs. IR/RAG/Context/llms modes have **no** watch mode — only
   HTML does — so if we want live "check" behavior in non-HTML modes we
   either rebuild on demand or add app-side watching.

**Design note:** keep it simple in v1 — one `boris --watch` process for
preview; the sidebar/tree and diagnostics refresh from a one-shot
`boris --out` build triggered on file save (debounced in-app).

### 4.6 Preview strategy

- `WKWebView` loading `file://<dist>/index.html` with the dist folder as
  `baseURL` (so relative assets resolve).
- On `watch: rebuild succeeded` → reload (or diff only changed pages).
- App Sandbox: the dist folder lives inside the user-selected project
  folder, so a security-scoped bookmark covers read access.
- If themes reference remote assets, add network-client entitlement
  (decide per theme; the reference theme is self-contained).

### 4.7 Project model & settings

Boris has **no config file** — everything is flags. The app needs a
per-project settings store. Proposal:

- A `solipsist.json` (or `.solipsist.json`) at the project root, or an app-
  side settings plist in `~/Library/Application Support/Solipsist/`.
  **Open question** — do we want settings inside the content repo
  (shareable with collaborators, but then it's content) or app-side
  (machine-local)? Default recommendation: app-side plist keyed by project
  folder path; keep content folders pure Boris.
- Settings captured: `inputDir` (default `content`), `htmlDir` (default
  `dist`), `themeRoot`, `targets` (NAME=DIR map), `layoutRules`,
  `incremental`, `jobs` (1–64), and export dirs (`out`, `ragDir`,
  `contextDir`, `llmsPath`).
- Recent-projects list via `NSDocumentController`-style persistence or
  `UserDefaults`.

---

## 5. App architecture (Swift/SwiftUI)

### 5.1 Project generation

**Recommendation: XcodeGen** — commit a `Project.yml` and generate the
`.xcodeproj` (don't hand-edit `project.pbxproj`). This keeps the repo
diff-friendly and lets CI regenerate. (Alternative: Tuist; or a pure
SwiftPM executable target + a thin Xcode app wrapper — XcodeGen is the
pragmatic middle.)

- Deployment target: **macOS 14+** (or 15+; decide — no reason to chase
  older than 14).
- Swift 6 language mode; strict concurrency is on by default in Swift 6 —
  plan actors for the process/engine layer up front.
- App name: **Solipsist**, bundle id e.g. `dev.drawmeanelephant.solipsist`
  (open question — exact id matters for signing).

### 5.2 Module layout (suggested)

```
Solipsist/
  App/                    # @main, AppDelegate, Window scene, menus
  Models/                 # Codable mirrors of Boris JSON contracts
    BuildReport.swift     # ok, errorCount, diagnostics
    Manifest.swift        # PageSummary (id, sourcePath, role, parent, title, status)
    Graph.swift           # Node, Edge, ReverseIndex, Nav
    Diagnostic.swift      # severity, code, message, remediation, sourcePath, line, column, id
    AnalysisReport.swift  # check/impact JSON
    ProjectSettings.swift # per-project settings store
  Engine/                 # Boris process layer (actor-isolated)
    BorisBinary.swift     # locate embedded binary, version probe (`boris --help` / run)
    BorisRunner.swift     # one-shot command runner (exit codes, timeout, cancel)
    BorisWatcher.swift    # long-lived --watch process + stderr line parser
    BuildState.swift      # ObservableObject: last result, pageCount, diagnostics
  UI/
    SidebarView.swift     # trunk/satellite tree, status badges
    EditorView.swift      # Markdown editor + frontmatter inspector
    PreviewView.swift     # WKWebView wrapper + reload on rebuild
    DiagnosticsView.swift # error list, click-to-jump
    StatusBarView.swift   # build state, watch toggle, page counts
    ExportView.swift      # IR / RAG / Context / llms buttons + progress
    ProjectPicker.swift   # open/create project, recent projects
  Support/
    FileWatching.swift    # (optional) app-side watcher
    SecurityScoped.swift  # bookmarks for sandboxed folder access
    ThemePicker.swift     # --theme ROOT discovery under examples/
```

### 5.3 Key Swift types (sketch)

```swift
// Codable mirrors of the Boris contracts — parse with JSONDecoder.
struct BuildReport: Codable { var schemaVersion, compiler: String; var ok: Bool; var errorCount: Int; var diagnostics: [Diagnostic] }
struct Diagnostic: Codable { var severity, code, message, remediation: String; var sourcePath: String?; var line, column: Int?; var id: String? }
struct PageSummary: Codable { var index: Int; var id, sourcePath, role, title, status: String; var parent: String? }
struct GraphNode: Codable { var index: Int; var id, sourcePath, role, title, status: String; var parent: String?; var parentIndex: Int?; var tags: [String]?; var bodyOffset: Int? }

// Engine: one actor owns all process launches so builds never overlap.
actor BorisEngine {
    func build(project: Project, mode: BuildMode) async throws -> BuildReport
    func check(project: Project) async throws -> AnalysisReport
    func impact(project: Project, pageId: String) async throws -> AnalysisReport
    func startWatch(project: Project) async throws
    func stopWatch() async
    var watchEvents: AsyncStream<WatchEvent>  // .initialBuildSucceeded(pages), .rebuildSucceeded, .rebuildFailed(reason), .diagnostics([Diagnostic])
}
```

### 5.4 Concurrency & lifecycle

- `BorisEngine` as an `actor`; `BuildState` as `@MainActor ObservableObject`.
- Watch process lives as long as the preview window; terminate on window
  close / project switch / app quit (`terminate()` + wait for exit).
- Never parse watch output on the main thread — `readabilityHandler` runs
  on a background queue; funnel lines into the actor.
- Handle process crash: if the watch process dies unexpectedly, surface
  state and offer restart.

---

## 6. Milestones

Suggested order. Each milestone is independently shippable/testable.

### M0 — Repo bootstrap ✅ (trivial)
- Add `README.md` to solipsist (what this app is).
- Commit `Project.yml` (XcodeGen), `.gitignore` already present.
- Pin the boris commit used (submodule or a `boris.version` file + fetch script).

### M1 — Engine spike: run Boris from Swift
- Embed a built `boris` binary; `BorisRunner` runs one-shot `--out` build
  on the boris sample site.
- Parse `build-report.json` / `manifest.json` / `graph.json` into Codable
  structs. Print results to console.
- **Accept:** a command-line Swift harness (or app menu action) runs a full
  build + exports the three JSON files and decodes them.

### M2 — Project open + sidebar
- Open folder (sandbox bookmark), one-shot build, render Trunk/Satellite
  tree from `manifest.json` with status badges.
- Recent projects in File menu.

### M3 — Editor + frontmatter inspector
- Built-in Markdown editor (v1: plain text + frontmatter-aware sidebar
  fields: title, parent, status, tags).
- Save → debounced rebuild → sidebar + status bar update.
- (Fallback if in-app editor is too much for v1: "Open in External Editor"
  + app-side watcher to detect saves.)

### M4 — Live preview
- `boris --watch --incremental` + `WKWebView` preview reload.
- Watch status in status bar (idle/building/succeeded/failed).
- Error recovery demo: break a file, see "Waiting for correction…" state,
  fix it, see rebuild succeed.

### M5 — Diagnostics panel
- Error list from `build-report.json` diagnostics (and watch stderr).
- Click row → open file at line:column in the editor.
- Severity coloring, remediation text display.

### M6 — Check / Impact / exports
- Buttons: `boris check`, `boris impact <page>` (with page picker),
  JSON IR export, RAG, Context Bundle, `llms.txt`.
- Show analysis reports in a read-only pane.

### M7 — Themes & multi-target
- Theme picker (`--theme ROOT`), layout rules UI, `--target NAME=DIR`.
- Project settings editor (all flags captured in §4.7).

### M8 — Packaging & distribution
- Sandbox entitlements, codesign, notarization, DMG/zip export.
- Test on a clean Mac (no Zig/CMake installed — prove the embedded binary
  is self-contained).

---

## 7. Packaging & distribution details

- **Signing:** Developer ID Application cert; hardened runtime. The embedded
  `boris` binary gets nested-code-signed by Xcode automatically; verify with
  `codesign --verify --deep --strict` and `spctl --assess`.
- **Notarization:** `xcrun notarytool submit` + staple. Direct distribution
  (no App Store) unless desired later — App Store would require review of
  the "runs an embedded executable" story (fine, but worth knowing).
- **Entitlements (sandbox):**
  - `com.apple.security.app-sandbox` = true
  - `com.apple.security.files.user-selected.read-write` = true (project folders)
  - `com.apple.security.files.bookmarks.app-scope` = true (persist access)
  - `com.apple.security.network.client` = true *only if* preview loads remote assets
- **Architecture:** arm64 (this machine); optionally universal (add x86_64
  by building boris with `zig build -Dtarget=x86_64-macos` — Zig cross-compiles
  natively; CI can do both).
- **Updating the engine:** bump the pinned boris commit, rebuild binary,
  re-verify IR `schemaVersion` still `0.2.0` (the contracts say consumers
  MUST branch on `schemaVersion` — decode defensively and show a
  "newer/older engine" notice if it changes).

---

## 8. Risks & open questions

1. **IR/watch asymmetry** — watch mode is HTML-only. If we want live
   diagnostics in IR mode we add app-side file watching (option 2 in §4.5)
   or trigger one-shot builds on save. Decide in M4/M5.
2. **Config file location** — settings inside the repo vs app-side (§4.7).
   Needs a product decision.
3. **Editor scope** — full in-app Markdown editor (big feature: syntax
   highlighting, frontmatter forms, wiki-link autocomplete) vs external-editor
   workflow for v1. Recommend: start with a basic editor, graduate later.
4. **Bundle id / app identity** — needed before signing. 
   `dev.drawmeanelephant.solipsist` as a placeholder.
5. **Deployment target** — macOS 14 vs 15 vs 16. Suggest 14+ for reach;
   nothing in the plan needs newer APIs (WKWebView, Process, SwiftUI are old).
6. **Boris binary provenance** — build ourselves at release time vs CI
   artifact. Pin commit + record in the app's About screen
   (`compiler` string from manifest/build-report is already there).
7. **App Store vs direct** — direct Developer ID is the simple path; App
   Store is possible but the "embedded executable" needs a clear review story.
8. **Universal binary** — arm64-only is fine for a personal tool; universal
   adds a second boris build (Zig makes it easy) and ~6MB.
9. **Boris version drift** — new boris releases could change flags or IR.
   Mitigate: version probe at app start (`boris --help` parse / run a tiny
   build), pin the binary, branch on `schemaVersion` in all decoders.
10. **Migration labs / source-RAG / package binaries** — out of v1 scope;
    the app targets the core `boris` binary only.

---

## 9. Appendix A — Boris CLI reference (verbatim from `boris --help`, v0.8.0)

```
Boris — Zig content compiler (HTML site + IR + optional RAG)

Usage: boris [options]

Modes:
  check               Read-only graph health report (CI findings exit 1)
  impact <ID>         Read-only transitive impact report for a page
  (default)           HTML site → pages under dist/ (content/ + layouts/main.html)
  --html              Explicit HTML site mode → --html-dir (default dist)
  --html-dir <DIR>    HTML site mode with output directory DIR
  --target NAME=DIR   HTML multi-target mode (repeatable; order-independent); implies HTML
  --out <DIR>         IR mode → write JSON under DIR (default .boris when --no-rag)
  --no-rag            Explicit IR mode (JSON under --out, default .boris)
  --rag               RAG-only mode → corpus under --rag-dir (default rag)
  --rag-dir <DIR>     RAG-only mode with output directory DIR
  --context           Context-only mode → bundle under --context-dir (default context)
  --context-dir DIR   Context-only mode with output directory DIR
  --llms              Deterministic llms.txt export → llms.txt
  --llms-path PATH    llms.txt export path (implies --llms)

Options:
  --input <DIR>       Content root (default: content)
  --textile          Explicit .textile-only input adapter mode (no mixed trees)
  --out <DIR>         IR output directory (selects IR mode; default: .boris)
  --rag-dir <DIR>     RAG corpus directory (implies RAG-only; default: rag)
  --html-dir <DIR>    HTML output directory (implies HTML; default: dist)
  --html-layout PATH  Global layout template (default: layouts/main.html)
  --theme ROOT        Theme root sugar → ROOT/layouts/main.html (+ managed assets/)
  --target NAME=DIR   Named HTML output root (repeatable; exclusive with --html-dir)
  --target-layout N=P Per-target layout (NAME=PATH; may precede or follow --target)
  --layout-rule T S P HTML layout rule: TARGET SELECTOR LAYOUT_PATH (repeatable; max 256/target)
                      Selectors: id:<entity-id> | glob:<seg-pattern> | role:trunk|satellite
  --incremental       Content-addressed incremental HTML rendering (HTML mode)
  --watch             Local-development watch mode for HTML builds (implies --incremental)
  --jobs N, -j N      Bounded parallel HTML page workers (1–64; HTML mode; default 1; smoke-validated)
  --quiet             Suppress progress + diagnostic stderr (exit codes/artifacts unchanged)
  --format human|json  Analysis output format for check/impact (default human)
  --report PATH        Write an analysis report instead of stdout
  -h, --help          Show this help and exit 0

HTML artifacts (success; Apex + layout splice):
  <html-dir>/**/*.html   or   <each-target-dir>/**/*.html
  <target-dir>/.boris-cache/manifest.json  (with --incremental / --watch)
  Staging: <target-dir>.boris-stage (ephemeral; committed only on full target success)

IR artifacts (success; --out or --no-rag):
  <out>/manifest.json  <out>/graph.json  <out>/build-report.json

RAG artifacts (success; same graph validation as IR):
  INDEX.md  UPLOAD-GUIDE.md  catalog.jsonl  catalog_meta.json
  system/**  content/pages/**  graph/entity-catalog.md  graph/relations.md

Context artifacts (success; same graph validation as IR/RAG):
  bundle.md  manifest.json  graph.json  pages/<entity-id>.md

Conflicts (exit 2):
  --rag with --no-rag
  --no-rag with --rag-dir
  --context / --context-dir with --rag, --out, or HTML selectors
  explicit --out with --rag or --rag-dir
  --html / --html-dir / --target / --target-layout / --layout-rule with --rag, --rag-dir, --context, or explicit --out
  --target with --html-dir
  --watch, --incremental, or --jobs with IR (--out / --no-rag) or RAG / context
  Invalid target names, duplicate names, output collisions, workspace escape,
  content/layout overlap, unknown --target-layout / --layout-rule target,
  duplicate or invalid layout selectors, invalid layout paths (.. / absolute),
  mixed theme roots, >256 rules/target

Exit codes: 0 success, 1 content validation, 2 usage, 3 I/O/system

Note: Bare `boris` builds HTML under dist/ as target "default". Use --out for JSON IR.
      --html / --html-dir / bare CLI map to a single target named "default".
      Equivalent --target / --target-layout / --layout-rule permutations yield the
      same config (targets sorted by name; rules canonicalized). No layout frontmatter.
```

## 10. Appendix B — Boris content model & frontmatter quick reference

- Frontmatter is **optional**, only when file starts with `---` at byte 0.
- Keys: `id`, `title`, `parent`, `status`, `tags`, relations
  (`relkind=entity-id`). Closed grammar — not YAML.
- Status values: `published` etc. (see `docs/contracts/frontmatter.md`).
- Example page:

```markdown
---
title: Getting Started with Boris
status: published
tags: [setup, cli]
---

# Getting Started
...
```

- Components: `<Aside kind="tip" id="...">...</Aside>` and `<Details>` only,
  recognized outside code fences, kept in document order.
- Includes: `{{include path/to/file.md}}`. Wiki-links: `[[entity-id]]`,
  `[[entity-id#heading-id]]`. Both fail loudly on bad targets.
- Content root layout seen in boris itself: `content/{trunk dirs}/{satellites}`,
  `content/includes/` for include sources, `layouts/main.html` global layout.

## 11. Appendix C — Boris docs that matter for the app

Normative contracts live in `boris/docs/contracts/` (the app's integration
truth):

| Contract | Why the app cares |
|----------|-------------------|
| `ir-schema.md` | Manifest/graph/build-report shapes, schemaVersion branching |
| `diagnostics.md` | Diagnostic object fields, codes, exit codes |
| `watch-mode.md` | Watch semantics, debounce, stderr lines, exclusions |
| `frontmatter.md` | What the editor must generate/validate |
| `components.md` | Aside/Details syntax for editor support |
| `identity-and-paths.md` | Entity ids, sourcePath rules, case sensitivity |
| `html-output.md`, `templating-and-themes.md` | Preview + theme picker |
| `rag-export.md`, `context-bundle.md`, `llms-txt.md` | Export features |
| `scanner.md`, `parent-relationships.md` | Tree semantics for the sidebar |
| `docs/STATUS.md` | Current phase/known gaps (read at each milestone start) |
| `docs/ROADMAP-post-f8.md` | Historical direction notes |

Also useful: `boris/examples/` (7 themes incl. `reference-theme`),
`boris/fixtures/` (test content), `boris/CHANGELOG.md` (release rhythm —
fragments under `docs/changelog.d/`).

## 12. Environment & evidence (this machine, 2026-08-17)

| Tool | Version |
|------|---------|
| macOS | 27.0 (arm64) |
| Xcode | 27.0 (Build 27A5228h) |
| Swift | 6.4 (swiftlang-6.4.0.27.1) |
| Zig | 0.16.x (`/opt/homebrew/bin/zig`) |
| CMake | present (`/opt/local/bin/cmake`) |

Verified commands + outputs from this session:

```
zig build                          → OK (libapex.a static build)
file zig-out/bin/boris             → Mach-O 64-bit executable arm64, 6.2 MB
./zig-out/bin/boris --quiet        → dist/ (45 pages)
./zig-out/bin/boris --out .boris   → build-report.json, graph.json, manifest.json
./zig-out/bin/boris check --format json  → boris-documentation-intelligence report
```

Both repos are cloned locally:
- `solipsist/` → will become the Swift app
- `boris/` → engine checkout (dev builds + reference content only)

---

*Next step: review §8 open questions, pick a direction for the editor
scope and config-file location, then start at M0/M1 tomorrow.*
