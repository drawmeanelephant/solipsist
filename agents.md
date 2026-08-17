# Solipsist — Agent Operating Manual

> **Read this file first.** It tells you what this repo is, what you may and
> may not touch, and where everything lives. It is written for agents (and
> humans) picking up this codebase cold.

## What this is

Solipsist is a native **macOS Swift/SwiftUI app** that wraps
[Boris](https://github.com/drawmeanelephant/boris) — a deterministic Zig
documentation compiler — as its **engine**. Boris is not a library and never
will be; the app drives the `boris` binary as a subprocess and decodes its
versioned JSON contracts.

**Current status:** M1 done (engine spike verified end-to-end). The app shell
runs the bundled binary and decodes `build-report.json`, `manifest.json`,
`graph.json`, and the `check`/`impact` analysis reports. Everything beyond
that is M2+ (see [Milestones](#milestones)).

## ⛔ Hard boundaries (non-negotiable)

These are the rules that keep this project healthy. Violating them is worse
than shipping slowly.

1. **Never touch the `boris` repo.** No commits, no pushes, no edits, no
   branches — ever. It is read-only upstream. We *vendor* its binary and
   *file issues* against it. Boris lives at `../boris` next to this repo and
   only ever gets read (source) and executed (binary).
2. **Issues against Boris are drafted here, filed there.** Ready-to-paste
   issue bodies live in [`docs/issues/`](docs/issues/). Filing them means
   pasting into a GitHub issue on the boris repo — never a PR, never a patch
   to boris.
3. **Never reimplement Boris semantics in Swift.** No homegrown frontmatter
   parser, no parallel graph/topology logic, no copied diagnostic codes. The
   JSON contracts are the single source of truth; Swift only mirrors them
   (Codable) and displays them.
4. **Never silently ignore diagnostics or exit codes.** Surface them. Exit 1
   from `check` means *findings*, not a broken build — render them as an
   advisory panel.
5. **Never mutate the user's content tree from the app** except as the direct
   result of an explicit user action (saving an edit).
6. **The subprocess boundary is a feature.** A crashing/looping Boris process
   must never take down the app. Keep the engine behind `Process` isolation;
   do not try to embed Zig as a library.

## Doc tree (read in this order)

| File | Purpose |
|------|---------|
| [`README.md`](README.md) | Project overview, prerequisites, quick commands |
| [`docs/PLAN-MAC-APP.md`](docs/PLAN-MAC-APP.md) | Architecture + the full 9-milestone plan (M0–M8) |
| [`docs/ENGINE-WORK-AND-DESIGN.md`](docs/ENGINE-WORK-AND-DESIGN.md) | Boris work items (Part A: issues) + our design decisions (Part B: D1–D11) |
| [`docs/CONTRACT-AUDIT.md`](docs/CONTRACT-AUDIT.md) | Consumer-driven audit of the boris boundary, bucketed 🟢/🟡/🔴 (the 🔴s are what we feed back into boris) |
| [`docs/issues/`](docs/issues/) | Ready-to-paste GitHub issues for boris (A1–A4, A6, A7, A12 drafted) |

If you are new: README → PLAN-MAC-APP → ENGINE-WORK-AND-DESIGN →
CONTRACT-AUDIT. The issue drafts are the "what we want Boris to do for us"
list; the design decisions are the "how we build on our side" list; the
audit is why each issue exists.

## Repo layout

```
Project.yml            XcodeGen spec — source of truth for the Xcode project
Sources/
  App/                 SwiftUI app shell (SolipsistApp, ContentView)
  Models/              BorisContracts.swift — Sendable Codable mirrors of all contracts
  Engine/              BorisBinary (locate), BorisRunner (subprocess), BorisEngine (actor)
Spike/main.swift       M1 CLI spike (shares Sources/Models + Sources/Engine)
scripts/embed-boris.sh Builds the engine from ../boris and copies it into the app bundle
Solipsist/             Entitlements (sandbox + security-scoped bookmarks)
docs/                  Plans, decisions, issue drafts
Makefile               tools / generate / build / run-spike / clean
```

**Never hand-edit the generated `Solipsist.xcodeproj`** — edit `Project.yml`
and run `make generate`.

## Build & run

Prereqs: macOS 14+ arm64, Xcode 16+ (tested Xcode 27 / Swift 6), Zig 0.16+
(only to build the engine), and the boris checkout at `../boris`
(`BORIS_REPO_DIR` overrides). XcodeGen is vendored into `.tools/` — no global
install.

```bash
make tools      # vendor XcodeGen 2.46.0
make generate   # Solipsist.xcodeproj from Project.yml
make build      # app + embedded engine binary
make run-spike  # M1 spike against ../boris/content — the CI-able gate
```

The engine is located in this order: `SOLIPSIST_BORIS_BIN` env → app bundle
(`Resources/boris`) → `../boris/zig-out/bin/boris`. `make build` runs the
pre-build embed script, so the app bundle always carries its own engine.

## Engine contract facts (verified — don't re-derive)

These were established empirically and written up in
[`docs/ENGINE-WORK-AND-DESIGN.md`](docs/ENGINE-WORK-AND-DESIGN.md). Trust the
docs over assumptions:

- **Exit codes:** 0 success · 1 content/validation findings · 2 usage · 3 I/O.
  `check` exits 1 on unreferenced-page findings *by design*.
- **Streams:** virtually everything human-readable goes to **stderr**
  (progress, diagnostics, `--help`, `check`/`impact` reports). stdout is
  empty on success paths. Machine consumers use `--report PATH` (analysis)
  and the JSON artifacts — never parse prose.
- **Output containment is asymmetric:** HTML targets (`--html-dir`,
  `--target`) are confined to the process cwd (`WorkspaceEscape`, exit 2);
  `--llms-path` rejects invalid values (exit 2); but `--out` (IR),
  `--rag-dir`, `--context-dir`, and analysis `--report` write anywhere. The
  app runs boris with `cwd = project folder`, so HTML stays in-project.
- **Completion signal:** for `--incremental`/`--watch` HTML builds,
  `<dist>/.boris-cache/manifest.json` is written **atomically on success
  only** (a failed build leaves it untouched). Its fingerprint diff between
  builds = the exact changed-page set — our targeted-reload mechanism.
- **Watch mode is HTML-only and speaks prose on stderr** — that's the D10
  stopgap parser's territory until boris lands A1 (`--watch-json`).
- **No `--version` flag exists yet** (A2 is drafted). Engine version comes
  from `manifest.json`'s `compiler` today.
- **Killing boris is safe (verified):** watch mode catches SIGTERM/SIGINT →
  graceful exit 0 (≤500ms); an in-flight rebuild completes before shutdown;
  SIGKILL leaves no `.boris-stage` leftovers and the next build recovers.
  The app infers *cancelled* from `Process.terminationReason ==
  .uncaughtSignal`, never from a Boris exit code. Full evidence in
  [`docs/CONTRACT-AUDIT.md`](docs/CONTRACT-AUDIT.md).

## Design decisions (Part B) — status

From [`docs/ENGINE-WORK-AND-DESIGN.md`](docs/ENGINE-WORK-AND-DESIGN.md) §Part B:

| # | Decision | Status |
|---|----------|--------|
| D1 | Artifacts at Boris defaults (`dist/`, `.boris/`, `rag/`, …) | ✅ decided |
| D2 | App-side settings plist (seam for repo-side JSON later) | ✅ decided |
| D3 | Watch ownership: Boris for preview, app FSEvents for diagnostics | ⏳ revisit after A5 |
| D4 | Built-in *basic* Markdown editor for v1 | ⏳ biggest scope lever |
| D5 | Local HTTP server preview (`127.0.0.1`) over `file://` | ✅ decided |
| D6 | Stay sandboxed | ✅ decided |
| D7 | Bundle engine; **pin the boris commit** tested against | ⏳ pin note TODO |
| D8 | `schemaVersion` gating: unknown/newer → degrade, never crash | ✅ decided — write decoders defensively from day one |
| D9 | Any-folder project detection | ✅ decided |
| D10 | Watch-stderr stopgap parser, JSON artifacts as ground truth | ⏳ not built yet |
| D11 | The never-compromise boundary list (see above) | ✅ agreed |

**D7's pin note is a known TODO** — record the exact boris commit (v0.8.0)
tested against, somewhere the build can read it.

## Issue pipeline (boris)

Drafted and ready to paste: **A1** (NDJSON watch events — flagship P0),
**A2** (`--version` — P0), **A3** (`compiler` in build-report — P1), **A4**
(stream docs + fix `--report` help text — P1), **A6** (completion signal —
P1), **A7** (workspace-rule docs — P1), **A12** (signal/cancellation docs —
P1). The 🔴 blockers per the audit: A1/A5 (watch prose), A6 (HTML has no
result artifact), A2/A3 (no version identity).

Filing order: A2 + A4 first (XS, unblocks us), then A1, then A3 + A6 + A7 +
A12.
Not yet drafted: **A5** (watch diagnostics for non-HTML — the one that would
simplify our architecture the most; write it as an RFC), A8 (`boris init`),
A9/A10 (we recommend *not* doing — see doc).

Rule: every issue draft must be fact-checked against the current boris source
before it's filed — exact stderr lines, emission points, exit codes. The
existing drafts are the template.

## Milestones

From `docs/PLAN-MAC-APP.md`: **M0** bootstrap ✅ · **M1** engine spike ✅ ·
**M2** project open + sidebar · **M3** editor + frontmatter inspector · **M4**
live preview · **M5** diagnostics panel · **M6** check/impact/exports · **M7**
themes & multi-target · **M8** packaging & notarization.

Good next tasks for a fresh agent: lock D7's pin note; build the D10
watch-stderr stopgap parser (unblocks preview without waiting on A1); or
start M2 (security-scoped project open is already scaffolded in
`ContentView.swift`).

## Git workflow

- Work happens on **`planning/engine-integration`** (pushed). `main` stays
  tidy — only merged milestones land there, and only deliberately.
- Commit style: concise imperative subject + body; conventional commits
  welcome. Keep commits focused on one concern (scaffold / engine / docs /
  issue drafts).
- Never stage or commit changes you didn't make — this is a shared checkout;
  check `git status` before staging and add explicit paths, not `-A`.
- `boris/` is *never* touched by git operations from this repo.
