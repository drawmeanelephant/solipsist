# Solipsist ↔ Boris — Planning Handoff

**For the agents joining the planning effort.** `agents.md` (repo root) is the
operating manual — read it first, it overrides anything this brief glosses.
This file is the condensed "state of the world" so you don't spend your first
session re-deriving facts that are already verified and written down.

---

## State of the world (2026-08-17)

- **Solipsist** is a native macOS SwiftUI app that wraps **boris** as a
  subprocess engine. Boris is a deterministic Zig *graph-native publication
  compiler* — Markdown/Textile/Cooklang in → validated graph → contracted
  projections (HTML, JSON IR, RAG packs, publication targets).
- **Engine baseline = the `afterparty` line, `boris/0.8.1` — NOT `main`.**
  `main` is frozen at v0.8.0. The local `../boris` checkout is on
  `afterparty` at commit `b82e9e2`. If something you read contradicts this,
  you're reading pre-reconciliation docs (`CONTRACT-AUDIT.md` and the early
  issue drafts are stale in places).
- **M1 is done and verified:** the app shell runs the bundled engine and
  decodes every IR contract (`build-report.json`, `manifest.json`,
  `graph.json`, `completion.json`, analysis reports) end-to-end against the
  afterparty binary. `make run-spike` is the gate.
- Everything lives on **`planning/engine-integration`** (pushed). `main` is
  untouched. The boris repo is **never** touched.

## What's decided — do not re-litigate

- **D1** artifacts at boris defaults · **D2** project config = Boris profile (`boris.json`); app plist = execution controls + UI state only ·
  **D5** preview is engine-owned via `watch --serve` (loopback + SSE — the
  app-side HTTP server idea is obsolete) · **D6** stay sandboxed ·
  **D8** `schemaVersion` gating: unknown/newer → degrade, never crash ·
  **D9** any-folder project detection · **D11** the never-compromise boundary
  list (in `agents.md`).
- **Non-negotiables:** never touch the boris repo; never reimplement boris
  semantics in Swift (JSON contracts are the single source of truth); never
  silently ignore diagnostics/exit codes; subprocess isolation is a feature.

## What's open — where planning agents earn their keep

| Open item | What's needed |
|-----------|---------------|
| **D4 editor scope** | ✅ decided — native ergonomics + embedded `boris-editor` (WKWebView token URL; link-out fallback); no from-scratch native editor in v1 (see `ENGINE-WORK-AND-DESIGN.md` §D4). |
| **D3 watch ownership** | Revisit after A5. Today: boris owns preview watch (`watch --serve`); app-side save-triggered one-shot diagnostics. |
| **D7 pin note** | ✅ resolved — commit `b82e9e2` (`boris/0.8.1`); the temporary `boris-agent-kit` folder's MANIFEST+SHA256SUMS are archived in `vendor/boris-agent-kit/` with a rebuild recipe (see [`AGENT-KIT-REVIEW.md`](AGENT-KIT-REVIEW.md)) |
| **A5 RFC** | `validate --watch`: join the artifact-free preflight with the watch daemon, emitting A1 events. The design discussion companion to the issue batch. |
| **Issue batch filing** | A3 [boris#638], A4 [boris#639], A13 [boris#640] filed; remaining order A1 → A7 → A5 RFC; A6/A12 moot (see `docs/issues/README.md`). |

## Suggested lanes (pick one, don't overlap)

- **Issues agent** — A3, A4, and A13 are filed; remaining: A1 (flagship),
  then A7, then open the A5 RFC as a discussion. A6/A12 are moot. Rule:
  every draft is fact-checked against the **afterparty** source before
  filing (exact stderr lines, emission points, exit codes).
  Start: `docs/issues/README.md`.
- **Design agent** — D4 is decided; remaining: D3 (watch ownership), write
  the D7 pin note into the build, and pressure-test the A5 RFC against
  `watch.zig` / `validate.zig`. Start: `docs/ENGINE-WORK-AND-DESIGN.md` §B.
- **Implementation agent** — start M2: project open (security-scoped
  bookmarks already scaffolded in `ContentView.swift`) + real graph sidebar
  from `graph.json`. Start: `docs/PLAN-MAC-APP.md` M2, `agents.md` §Build &
  run. Preview and diagnostics can ride on `watch --serve` + `build
  --report`; the D10 stopgap parser is no longer needed.

## Facts that are verified — don't re-derive

- **Exit codes:** 0 success · 1 content/validation (only with
  `--fail-on-unreferenced`; `check` exits 0 with findings by default) ·
  2 usage · 3 I/O.
- **Streams:** human-readable everything goes to **stderr** (progress,
  diagnostics, `--help`). stdout carries only `--version`, `--timings`, plan
  declarations. Machine surface = `--report` + JSON artifacts, never prose.
- **Containment:** all output trees (`--html-dir`, `--target`, `--out`,
  `--rag-dir`, `--context-dir`) are cwd-constrained — `WorkspaceEscape` exit
  2 outside cwd. `--report` single files stay free. Quirk: IR rejects
  **absolute** output paths even inside cwd (A7).
- **Completion signal:** `<dist>/.boris-cache/manifest.json` writes
  atomically on success only; fingerprint diff = changed-page set.
- **`build --report PATH`** writes `html-build-report-0.1.0` on success *and*
  failure, with `compilerId` and source locations — the machine diagnostics
  surface for the problems panel.
- **`watch --serve`** serves on loopback (port in stderr, `--port N`
  available) with SSE reload at `/__boris/events`; `event: reload` +
  generation number, first event on connect.
- **Killing boris is safe:** SIGTERM/SIGINT → graceful exit 0 ≤500ms,
  in-flight rebuild completes first; SIGKILL leaves no stage leftovers, next
  build recovers. Cancelled is inferred from `Process.terminationReason ==
  .uncaughtSignal`, never an exit code.

## Git workflow

- Work on **`planning/engine-integration`**; `main` stays tidy (only
  deliberate milestone merges).
- Never `git add -A` — this is a shared checkout; stage explicit paths.
- Never stage/commit changes you didn't make.
- boris is never touched by git operations from this repo.
