# Solipsist — Agent Operating Manual

> **Read this file first.** It tells you what this repo is, what you may and
> may not touch, and where everything lives. It is written for agents (and
> humans) picking up this codebase cold.

## What this is

Solipsist is a native **macOS Swift/SwiftUI app** that wraps
[Boris](https://github.com/drawmeanelephant/boris) — a deterministic Zig
**graph-native publication compiler** — as its **engine**. Boris is not a
library and never will be; the app drives the `boris` binary as a subprocess
and decodes its versioned JSON contracts.

**Engine baseline: the `afterparty` line, v0.8.1 candidate (`boris/0.8.1`)** —
NOT `main` (frozen, v0.8.0). The local `../boris` checkout is on
`afterparty`. Mission and full capability map:
[`docs/MISSION.md`](docs/MISSION.md) and
[`docs/BORIS-CAPABILITIES.md`](docs/BORIS-CAPABILITIES.md).

**Current status:** M1 done (engine spike verified end-to-end against `main`
v0.8.0; baseline now afterparty — base IR schema 0.2.0 unchanged, so the
decoders still apply). The app shell runs the bundled binary and decodes
`build-report.json`, `manifest.json`, `graph.json`, `completion.json`, and
the analysis reports. Everything beyond that is M2+ (see
[Milestones](#milestones)).

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
4. **Never silently ignore diagnostics or exit codes.** Surface them. On
   afterparty, `check` exits 0 with findings by default and 1 only with
   `--fail-on-unreferenced` — findings are an advisory panel, never a broken
   build.
5. **Never mutate the user's content tree from the app** except as the direct
   result of an explicit user action (saving an edit).
6. **The subprocess boundary is a feature.** A crashing/looping Boris process
   must never take down the app. Keep the engine behind `Process` isolation;
   do not try to embed Zig as a library.

## Doc tree (read in this order)

| File | Purpose |
|------|---------|
| [`README.md`](README.md) | Project overview, prerequisites, quick commands |
| [`docs/PLANNING-HANDOFF.md`](docs/PLANNING-HANDOFF.md) | **Start here if you're joining the planning effort** — state of the world, decided vs. open, per-agent lanes |
| [`docs/MISSION.md`](docs/MISSION.md) | **What we're trying to do** — one page, updated to the afterparty baseline |
| [`docs/BORIS-CAPABILITIES.md`](docs/BORIS-CAPABILITIES.md) | **The full list of what boris does** — sourced from the afterparty changelog + help + STATUS |
| [`docs/ENGINE-CONTRACTS.md`](docs/ENGINE-CONTRACTS.md) | **Probed machine contracts for M2–M4**: `watch --serve` (URLs, SSE), `completion.json`, `build --report` shapes |
| [`docs/PLAN-MAC-APP.md`](docs/PLAN-MAC-APP.md) | Architecture + the full 9-milestone plan (M0–M8) |
| [`docs/ENGINE-WORK-AND-DESIGN.md`](docs/ENGINE-WORK-AND-DESIGN.md) | Boris work items (Part A: issues) + our design decisions (Part B: D1–D11); **issue-batch reconciliation at the top** |
| [`docs/CONTRACT-AUDIT.md`](docs/CONTRACT-AUDIT.md) | Consumer-driven audit of the boris boundary, bucketed 🟢/🟡/🔴 (largely superseded by the afterparty reconciliation) |
| [`docs/AGENT-KIT-REVIEW.md`](docs/AGENT-KIT-REVIEW.md) | **The prebuilt binary kit (`boris-agent-kit/`)** — 10 verified Darwin-arm64 binaries of our pinned commit; the canonical work-against-binaries reference |
| [`docs/issues/`](docs/issues/) | Issue drafts with afterparty status (✅ withdraw / 🟡 reframe / 🔵 reformulate) |

If you are new: PLANNING-HANDOFF → MISSION → BORIS-CAPABILITIES →
PLAN-MAC-APP → ENGINE-WORK-AND-DESIGN (read the reconciliation table
first).

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
(`Resources/boris`) → `../boris-agent-kit/bin/boris` (verified kit binary,
**may not exist** — it was a temporary transport folder) →
`../boris/zig-out/bin/boris` (source build). `make build` runs the
pre-build embed script, so the app bundle always carries its own engine.
`SOLIPSIST_BORIS_BIN` is the tested drop-in for the kit binary — the M1
spike passes against it unchanged.

**The kit's pin is archived in `vendor/boris-agent-kit/`** (MANIFEST.json +
SHA256SUMS, verbatim) so future work never depends on the temporary
sibling folder. If the kit is gone, rebuild from the pinned commit
`b82e9e2` per the recipe there — behavior is what's pinned, not the exact
binary hash.

## Engine contract facts (verified — don't re-derive)

These were established empirically and written up in
[`docs/ENGINE-WORK-AND-DESIGN.md`](docs/ENGINE-WORK-AND-DESIGN.md). Trust the
docs over assumptions:

- **Exit codes:** 0 success · 1 content/validation · 2 usage · 3 I/O, plus
  Standard.site classes 4–9. **`check` exits 0 with findings by default**;
  `--fail-on-unreferenced` → 1 (verified).
- **Streams:** virtually everything human-readable goes to **stderr**
  (progress, diagnostics, `--help`, reports). stdout carries only
  `--version`, `--timings`, and plan/record declarations. Machine consumers
  use `--report PATH` and the JSON artifacts — never parse prose.
- **Output containment covers ALL output trees** (verified on afterparty):
  `--html-dir`, `--target`, `--out`, `--rag-dir`, `--context-dir` outside
  cwd all fail with `WorkspaceEscape` (exit 2). `--report` single-file paths
  stay free. The app runs boris with `cwd = project folder`, so everything
  stays in-project.
- **`build --report PATH`** writes `html-build-report-0.1.0` on success
  *and* failure (every HTML diagnostic class, `compilerId`, source
  locations) — the app's machine diagnostics surface.
- **`watch --serve [--port N]`** serves the built tree on loopback with an
  SSE reload stream at `/__boris/events` — preview is engine-owned.
- **`--version` / `-V`** prints `boris/0.8.1` (exit 0). **`--timings`**
  prints phase timings JSON on stdout. **`completion.json`** ships with IR
  builds (editor completion surface).
- **The toolchain binaries** (all in the kit, all verified): `boris-package`
  (Proof Pack — IR+RAG archive with MACHINE-READABLE-VERSION),
  `boris-search-index` (`boris-rendered-search-index` v1 from rendered
  HTML), `boris-content-audit` (editorial audit, JSON out),
  `boris-testdata` (deterministic fixtures + evidence runner), and the
  migration/scale/docs/gh-pages tools. Full review + probe results in
  [`docs/AGENT-KIT-REVIEW.md`](docs/AGENT-KIT-REVIEW.md).
- **Completion signal:** for `--incremental`/`--watch` HTML builds,
  `<dist>/.boris-cache/manifest.json` is written **atomically on success
  only** (a failed build leaves it untouched). Its fingerprint diff between
  builds = the exact changed-page set.
- **Watch mode is HTML-only and speaks prose on stderr** — for subprocess
  consumers; browsers get `--serve`'s SSE reload channel. A1
  (`--watch-json`) is the typed-events ask.
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
| D2 | Project config = Boris profile (`boris.json`, repo-side); app plist = `jobs`/`incremental`/`quiet` + UI state only | ✅ decided |
| D3 | Watch ownership: Boris for preview (`watch --serve`), app-side watcher only if needed | ⏳ revisit after A5 |
| D4 | Editor scope: native ergonomics + embedded `boris-editor` (WKWebView token URL; link-out fallback); no from-scratch native editor in v1 | ✅ decided |
| D5 | Preview: **engine-owned `watch --serve`** (loopback + SSE) — app-side HTTP server obsolete | 🔁 changed by afterparty |
| D6 | Stay sandboxed | ✅ decided |
| D7 | Bundle engine; **pin the boris commit** tested against | ✅ pinned — commit `b82e9e2` (`boris/0.8.1`); the kit's MANIFEST+SHA256SUMS are archived in `vendor/boris-agent-kit/`; vendor-from-kit when present, else rebuild from the pin (see [`AGENT-KIT-REVIEW.md`](docs/AGENT-KIT-REVIEW.md)) |
| D8 | `schemaVersion` gating: unknown/newer → degrade, never crash | ✅ decided — write decoders defensively from day one |
| D9 | Any-folder project detection | ✅ decided |
| D10 | Watch-stderr stopgap parser, JSON artifacts as ground truth | ⏳ not built yet |
| D11 | The never-compromise boundary list (see above) | ✅ agreed |

**D7's pin note is a known TODO** — record the exact afterparty commit
(b82e9e2, `boris/0.8.1`) tested against, somewhere the build can read it.

## Issue pipeline (boris) — re-baselined against afterparty

The drafts are re-baselined and ready to paste (statuses in
[`docs/issues/README.md`](docs/issues/README.md)):

- ✅ **Ready:** A1 (`--watch-json`), A7 (containment docs + IR absolute-path quirk).
- 🔵 **RFC:** A5 (`validate --watch` — join validate + watch, A1 events).
- ✅ **Filed:** A3 [boris#638] (IR build-report identity + the
  `compiler`/`compiler_id`/`compilerId` naming zoo), A4 [boris#639]
  (`--report` help bug + stdout surfaces), A13 [boris#640] (watch exits on
  `GraphValidationFailed` instead of recovering).
- ⛔ **Moot / withdrawn:** A2 (`--version` shipped), A6 (`build --report`
  solved the completion signal), A8 (`init`), A9 (`--fail-on-unreferenced`),
  A12 (watch-mode.md §6 documents signals; C06 pins exit classes).

Filing order: A1 → A7 → A5 RFC (A3/A4/A13 filed; A6/A12 moot).

Rule: every issue draft must be fact-checked against the **afterparty**
source before it's filed — exact stderr lines, emission points, exit codes.
The drafts are the template; the reconciliation table is the gate.

## Milestones

From `docs/PLAN-MAC-APP.md`: **M0** bootstrap ✅ · **M1** engine spike ✅ ·
**M2** project open + sidebar · **M3** editor + frontmatter inspector · **M4**
live preview · **M5** diagnostics panel · **M6** check/impact/exports · **M7**
themes & multi-target · **M8** packaging & notarization.

Good next tasks for a fresh agent: re-baseline the issue drafts per the
reconciliation table; lock D7's pin note (afterparty b82e9e2); verify the
M1 spike against the afterparty binary (`make run-spike`); or start M2
(security-scoped project open is already scaffolded in `ContentView.swift`)
— preview via `watch --serve` no longer needs the D10 stopgap parser.

## Git workflow

- Work happens on **`planning/engine-integration`** (pushed). `main` stays
  tidy — only merged milestones land there, and only deliberately.
- Commit style: concise imperative subject + body; conventional commits
  welcome. Keep commits focused on one concern (scaffold / engine / docs /
  issue drafts).
- Never stage or commit changes you didn't make — this is a shared checkout;
  check `git status` before staging and add explicit paths, not `-A`.
- `boris/` is *never* touched by git operations from this repo.
