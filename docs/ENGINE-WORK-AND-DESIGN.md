# Engine Work & Design Decisions — Solipsist ↔ Boris

**Date:** 2026-08-17
**Status:** brainstorming notes — companion to [PLAN-MAC-APP.md](PLAN-MAC-APP.md)
**Engine baseline:** boris v0.8.0, IR schema `0.2.0`

This document lists (A) the work we should ask Boris to do — phrased as
ready-to-file GitHub issues — and (B) the design decisions we need to make on
the Solipsist side. The guiding rule throughout: **everything proposed for
Boris must be strictly additive or opt-in, and must not touch the properties
that make Boris Boris** — deterministic output, stable exit codes, closed
frontmatter, workspace containment, single-native-binary.

Fact-checked against boris `main` this session (v0.8.0):

- No `--version` flag exists (`error: unknown option: --version`).
- Output containment is **asymmetric** (verified empirically): HTML output
  targets are **cwd-constrained** — `--html-dir`/`--target` outside the
  workspace fail with `WorkspaceEscape` (exit 2), `--llms-path` fails with
  `error: invalid value for --llms` (exit 2) — but `--out` (IR),
  `--rag-dir`, `--context-dir`, and analysis `--report` **write anywhere**
  (all verified writing to `/tmp` with exit 0). The workspace boundary for
  HTML is the process cwd (path-boundary check; targeting cwd itself is
  `TargetOutputCollision`). See A7.
- Analysis reports (`check` / `impact`) print to **stderr** by default;
  `--report PATH` writes them to a file. `check` exits 1 when it finds
  unreferenced pages (documented, CI-useful behavior).
- `build-report.json` (IR mode) has no `compiler` field; `manifest.json` does.
- Watch mode is **HTML-only** (`--watch` with IR/RAG/context is a usage
  error) and emits human-readable lines to stderr.
- Incremental HTML builds atomically write `.boris-cache/manifest.json`
  (`format_version: "boris-cache-v2-layout-rules"`) with per-page
  fingerprints, output paths, digests — a ready-made build-completion signal.

---

## Part A — Issues to file against Boris

> Ready-to-paste issue bodies live in [`docs/issues/`](issues/): A1
> ([boris-A1-watch-events.md](issues/boris-A1-watch-events.md)), A2
> ([boris-A2-version-flag.md](issues/boris-A2-version-flag.md)), A3
> ([boris-A3-build-report-compiler.md](issues/boris-A3-build-report-compiler.md)),
> A4 ([boris-A4-stream-contract.md](issues/boris-A4-stream-contract.md)), A6
> ([boris-A6-completion-signal.md](issues/boris-A6-completion-signal.md)), A7
> ([boris-A7-workspace-rule.md](issues/boris-A7-workspace-rule.md)). Each
> was fact-checked against the current source (exact stderr lines, emission
> points, exit-code table, existing doc stubs) so they can be filed as-is.

### A1. Machine-readable watch events (NDJSON) — **P0**

**Problem.** Watch mode is the backbone of the app's live-preview workflow,
but its only output is human text on stderr (`watch: rebuild succeeded.`,
`error: rebuild failed: …`). A GUI either parses fragile prose or ignores it
and polls. We want typed events: build started / succeeded / failed, changed
page set, error counts, target names.

**Proposal.** Add an opt-in structured event stream, e.g. `--watch-json` that
emits one JSON object per line (NDJSON) on stderr instead of (or alongside)
the human lines:

```json
{"event":"build-started","targets":["default"]}
{"event":"rebuild-succeeded","pages":45,"changed":["guides/overview.md"],"targets":["default"],"durationMs":42}
{"event":"rebuild-failed","errors":2,"diagnostics":["EFRONTMATTER"],"targets":["default"]}
{"event":"watch-stopped"}
```

**Why it's not a compromise.** Purely additive and opt-in; the human lines
and all output artifacts stay byte-identical. The event schema can live under
`docs/contracts/watch-mode.md` like everything else. A cheaper fallback if
Boris prefers not to grow the flag surface: **canonicalize and document the
existing stderr line grammar** so consumers can parse it with confidence.
Either way, Solipsist wants *one* stable machine contract.

### A2. `--version` flag — **P0** (tiny)

**Problem.** There is no way to ask the binary its version. `manifest.json`
carries `compiler: boris/0.8.0`, but the app needs the engine version before
running a build (About screen, engine-update check, schema compatibility).

**Proposal.** `boris --version` prints the compiler id (`boris/0.8.0`) and
exits 0. Reuses the existing `compiler_id` constant; no behavior change
elsewhere.

**Why it's not a compromise.** A standard, read-only flag. Zero impact on
compilation, determinism, or exit-code semantics.

### A3. `compiler` field in `build-report.json` — **P1** (tiny)

**Problem.** `build-report.json` is the artifact Solipsist decodes on every
build — including failures — but it lacks the `compiler` id that
`manifest.json` has. On a failed build we currently can't report *which*
engine produced the diagnostics.

**Proposal.** Add `"compiler": "boris/0.8.0"` to `build-report.json` (it
already exists as a constant). Additive field; whether it bumps
`schemaVersion` is Boris's call (it arguably should not, since it's additive
and the IR shape is unchanged).

**Why it's not a compromise.** One field, already-computed value, on a file
Boris controls and version-gates.

### A4. Document stdout/stderr contract per mode — **P1** (docs)

**Problem.** Analysis reports print to stderr, which surprised us and cost a
debug cycle (we assumed stdout, found `--report PATH`). Builds print progress
to stderr too. Nothing states what goes where in which mode.

**Proposal.** A short section in the CLI docs (and help text): which stream
carries progress, diagnostics, analysis reports, and JSON in each mode; and
that `--report PATH` is the machine path. Optionally add `--report -` as a
spelled-out "stdout" for symmetry.

**Why it's not a compromise.** Documentation only. If Boris ever wants to
*change* the streams, that would be a breaking change — but documenting the
status quo is pure win.

### A5. Watch + diagnostics for non-HTML modes — **P1/P2** (design discussion)

**Problem.** Watch is HTML-only. For the app's editor workflow we want live
*diagnostics* (graph health) as the user types — not necessarily rendered
HTML. Today that means either an app-side file watcher + one-shot IR builds,
or rebuilding HTML in watch mode and reading `build-report.json`… which HTML
mode doesn't publish.

**Proposal (the interesting one).** A watch variant that recompiles in
memory and emits only diagnostics/events *without touching the output tree* —
call it `boris check --watch` or `boris --watch-diagnostics`. The compile
pipeline already runs (scan → parse → validate) before rendering; rendering
is the part we'd skip. Events streamed via A1; failed files get structured
diagnostics. This gives the app a live "problems panel" with zero artifact
churn.

**Why it's not a compromise.** The compile/validate path is the same
deterministic pipeline; we just opt into not writing outputs. It needs a
Boris-side RFC because it touches watch-mode's conflict rules — hence P1/P2,
not P0. If Boris declines, Solipsist does its own FSEvents watcher + one-shot
IR builds (Part B, decision D3) and this becomes a non-issue.

### A6. A written completion/result signal for one-shot builds — **P1** (small)

**Problem.** For one-shot HTML builds (no `--watch`), the app currently gets
exit code + stderr prose only — HTML mode publishes no `build-report.json`.
We want a durable, parseable "build finished, here are the results" artifact
for every mode.

**Proposal.** Extend `build-report.json` publication to HTML mode (same
`ok`/`errorCount`/`diagnostics` shape), or — minimal — document
`.boris-cache/manifest.json` as the *completion marker* for incremental HTML
builds (it is already written atomically on success; Solipsist can poll its
mtime and diff fingerprints to learn exactly which pages changed, enabling
targeted preview reloads). A `completedAt` timestamp inside the cache
manifest would make polling trivial.

**Why it's not a compromise.** Publishing an extra report is additive; HTML
artifacts remain byte-identical. The cache manifest already exists — this is
mostly a documentation + timestamp ask.

### A7. Document the workspace-containment rule — **P1** (docs + decision)

**Problem.** Output containment is undocumented and **asymmetric** (see the
corrected fact-check above): HTML targets are cwd-constrained
(`WorkspaceEscape` exit 2; root collision is a distinct error), while
`--out` / `--rag-dir` / `--context-dir` / `--report` write anywhere.
`--llms-path` is constrained via a separate "invalid value" usage error. It's
a *good* safety property for HTML (the app can never be pointed at an
arbitrary output tree), but the rule — and the asymmetry — deserve an
explicit decision, not documentation-by-discovery.

**Proposal.** Document: workspace = process cwd; the path-boundary check
semantics; both HTML errors; exit-2 mapping; and the per-flag table including
which outputs are open. Then decide explicitly whether the asymmetry is
intentional (recommended: document-as-is — HTML outputs are clobbering,
deployable trees; data products writing elsewhere is legitimate) or whether
containment should extend to all output flags (a behavior change; separate
RFC). Solipsist keeps all artifacts in-project via Boris defaults anyway
(D1), so this is mainly a contract question.

**Why it's not a compromise.** Docs only unless Boris chooses the extend
alternative, which would ship as its own additive-contract change.

### A8. `boris init` project scaffold — **P2**

**Problem.** "New Project" UX in the app needs a starter layout
(`content/`, `layouts/main.html`, a sample page). Today that's copy-paste
from `examples/`.

**Proposal.** `boris init [dir]` writes the minimal scaffold. Nice-to-have;
Solipsist can ship its own template bundle in the meantime, so this is not a
blocker.

### A9. Exit-code granularity for `check` — **P2** (likely: don't change)

**Problem.** `check` exits 1 for findings (unreferenced pages), which the app
wants to present as an *advisory panel*, not a broken build.

**Recommendation: leave exit codes alone.** They are a CI contract, and
changing them would compromise Boris. Solipsist adapts: exit 1 + successful
report decode = "findings", and we render them as warnings. File an issue
only if Boris wants to add a *distinct* code (e.g. exit 4 = "findings") —
purely additive, opt-in for consumers. Low priority; document, don't change.

### A10. Library / C ABI mode — **P2** (long-term; likely: never)

**Problem.** Subprocess = process spawn per build, IPC cost, no shared memory.

**Recommendation: do not pursue.** Boris is deliberately a single native
binary with a typed CLI; embedding it as a library is a large undertaking
that fights the project's identity, and the subprocess boundary buys us crash
isolation (a bad compile can't take down the app). Revisit only if profiling
ever shows process overhead actually matters (it won't at docs-site scale).

### A11. Structured diagnostics *during* watch (folded into A1)

Covered by A1's NDJSON events — the `rebuild-failed` event should carry the
diagnostic objects (same shape as `build-report.json`), not just counts.

---

### A summary table

| # | Issue | Size | Priority | Additive? |
|---|-------|------|----------|-----------|
| A1 | Machine-readable watch events (NDJSON) | M | P0 | ✅ opt-in flag |
| A2 | `--version` flag | XS | P0 | ✅ |
| A3 | `compiler` in build-report.json | XS | P1 | ✅ additive field |
| A4 | Document stdout/stderr per mode | XS | P1 | ✅ docs |
| A5 | Watch diagnostics for non-HTML | L | P1/P2 | ✅ opt-in mode |
| A6 | Completion signal for one-shot builds | S | P1 | ✅ |
| A7 | Document workspace rule (+ asymmetry) | XS | P1 | ✅ docs |
| A8 | `boris init` scaffold | S | P2 | ✅ new command |
| A9 | `check` exit granularity | S | P2 | 🔒 recommend NOT changing |
| A10 | Library mode | XXL | P2 | 🔒 recommend NOT doing |
| A11 | Structured watch diagnostics | M | P0 | ✅ folded into A1 |

**Suggested filing order:** A2 + A4 first (XS, docs, unblock us immediately),
then A1 (+A11) as the flagship P0, then A3 + A6 + A7, then the A5 design
discussion.

---

## Part B — Solipsist-side design decisions

These are decisions *we* own. Each lists options and a recommendation.

### D1. Where build artifacts live (workspace constraint)

Boris confines HTML outputs to the process cwd, and the app will run boris
with `cwd = project folder`, so HTML artifacts stay in-project. IR/RAG/
context/llms outputs are *not* confined (A7), so defaults matter here. So:

- **Option A (recommended):** use Boris defaults — `dist/`, `.boris/`,
  `rag/`, `context/`, `llms.txt` at project root. Project stays
  CLI-compatible (`boris` from a terminal does the same thing), artifacts are
  obviously gitignorable, and the app's security-scoped bookmark already
  covers them.
- **Option B:** a hidden `.solipsist/` folder for everything. Cleaner-looking
  project, but diverges from the CLI and adds an abstraction layer for zero
  gain.

**Decision needed:** A (recommended). Also: README guidance to gitignore
`dist/`, `.boris/`, `.boris-cache/`, `rag/`, `context/`, `llms.txt`.

### D2. Settings storage: app-side vs repo-side

Boris reads no config file, so project settings (input root, theme, targets,
layout rules, incremental/jobs) are purely our concern.

- **Option A (recommended):** app-side plist in
  `~/Library/Application Support/Solipsist/`, keyed by project folder path.
  Machine-local, no repo pollution, survives git operations.
- **Option B:** `solipsist.json` in the project root. Shareable/committable,
  reproducible builds across machines — but it's content-adjacent config
  inside content repos, and "what if the repo is also built by CLI users"
  gets murky.

**Decision needed:** A for v1, with a clean seam (a `ProjectSettings`
Codable type) so B can be added later if multi-machine reproducibility
matters. Related sub-decision: if we ever do B, JSON (Boris's native
language) not YAML/TOML.

### D3. Who watches the files?

- **Option A:** Boris `--watch` owns watching for the preview (battle-tested
  debounce/coalescing, self-trigger protection). App-side FSEvents watcher
  triggers one-shot IR builds for live diagnostics (since watch is HTML-only).
- **Option B:** App owns ALL watching (FSEvents), Boris only ever runs
  one-shot builds. Full control, but we reimplement debounce/coalescing and
  lose Boris's tested exclusion logic.
- **Option C:** Boris gains `check --watch`/diagnostics watch (A5) and owns
  everything.

**Decision needed:** A for M4, revisit after A5 lands. A5 would simplify us
considerably (no app-side watcher at all).

### D4. Editor scope for v1

- **Option A:** Built-in Markdown editor (plain text + frontmatter inspector
  form: title/parent/status/tags) + save → debounced rebuild.
- **Option B:** "Open in External Editor" + app-side watcher; app is
  read/manage/preview only.

**Decision needed:** This is the biggest scope lever. Recommendation: A, but
with a deliberately *basic* editor (no syntax highlighting or wiki
autocomplete in v1 — those are post-M5). B as a fallback if A balloons.

### D5. Preview transport: WKWebView file:// vs local HTTP server

- **Option A (recommended):** tiny in-app HTTP server on `127.0.0.1` serving
  `dist/`. Avoids `file://` quirks (sandbox, baseURL, some JS), enables
  future live-reload JS injection, and behaves like production. Needs
  `com.apple.security.network.server` entitlement.
- **Option B:** `WKWebView` + `file://` with `baseURL = dist/`. No server,
  but file URLs in WKWebView have real limitations and some themes may
  misbehave.

**Decision needed:** A (recommended); validate early with the reference
theme before committing. Note the network-server entitlement only allows
*listening*, not outbound — outbound (remote fonts/CDN) still needs
`network.client` if a theme uses it.

### D6. Sandbox vs non-sandbox

We scaffolded sandboxed (entitlements already signed in). Options:

- **Option A (recommended):** stay sandboxed. App Store-ready, forces
  security-scoped bookmarks (good hygiene), and nothing in the plan needs
  unsandboxed access.
- **Option B:** non-sandboxed Developer ID distribution — simpler file
  access, but locks out App Store and encourages sloppy paths.

**Decision needed:** A. Revisit only if the HTTP server + file access
combination (D5) proves painful.

### D7. Engine provisioning & version policy

- **Option A (recommended):** bundle the engine in the app (current
  `embed-boris.sh` approach). Deterministic, offline, sandbox-friendly.
  Engine upgrades ship with app updates; About screen shows the compiler id
  (once A2/A3 land).
- **Option B:** download-on-first-run. Fresher engine, but needs network
  entitlement, a download service, and re-signing of a downloaded binary —
  a lot of moving parts.

**Decision needed:** A. Related policy: **pin the boris commit** we test
against, record it in the repo, and gate app features on IR `schemaVersion`
(D8) rather than assuming compatibility.

### D8. SchemaVersion gating policy

Define now how the app treats future IR versions so decoders are written
defensively from day one:

- `schemaVersion == "0.2.0"` → full feature set.
- Unknown/`> 0.2.0` → show "engine newer than app" banner; disable
  IR-dependent features (tree, diagnostics panel) or degrade to HTML-only;
  never crash on decode. All decoders must branch on `schemaVersion`, per
  the Boris contract.

**Decision needed:** adopt this policy + write it into the Models layer as a
documented convention (e.g. a `schemaSupported` check in the engine).

### D9. Project identity & detection

What makes a folder a Solipsist project?

- **Option A (recommended):** any folder; default input root `content/`
  (Boris default); custom `--input` via settings. Zero magic.
- **Option B:** require a marker file (`.solipsist` / `boris.json`).
  Explicit, but an extra file in every repo and friction for "open any docs
  folder".

**Decision needed:** A. A "New Project" template (content/ + layouts +
sample page) lives in the app until/unless A8 (`boris init`) lands.

### D10. Watch-stderr fallback parsing

Until A1 ships, Solipsist must consume the human watch lines. Decision:
implement a small, forgiving parser for the documented stable lines
(`watch: initial build succeeded (N pages written)…`, `watch: rebuild
succeeded.`, `error: rebuild failed: …`), treat unknown lines as ignorable,
and prefer `.boris-cache/manifest.json` / `build-report.json` as ground
truth over any parsed prose. This is a deliberate stopgap with a defined
lifetime (until A1).

### D11. What we will NOT compromise on (our side of the boundary)

- Never reimplement Boris semantics in Swift (no homegrown frontmatter
  parser, no parallel graph logic). The JSON contracts are the single source
  of truth.
- Never silently ignore diagnostics or exit codes — surface them.
- Never mutate the content tree from the app without the user's explicit
  action (the app writes Markdown only when the user saves an edit).
- Never let a Boris process crash the app (subprocess isolation — already
  the architecture).

---

## Part C — Suggested next actions

1. File A2 (`--version`) and A4 (stdout/stderr docs) on boris — XS, unblocks
   the About screen and our debugging.
2. File A1 (+A11) as the flagship issue — structured watch events; engage
   with a concrete event schema in the issue body.
3. File A3, A6, A7 together as "small machine-contract improvements".
4. Open the A5 design discussion (watch diagnostics for non-HTML) as an RFC
   with our exact use case attached.
5. On our side: lock decisions D1, D2, D5, D6, D7, D8 (the ones that shape
   architecture) before starting M3/M4; D3 and D4 can ride along with
   implementation.
6. Keep the spike (M1) as a CI-able gate: it exercises binary discovery,
   the runner, and every decoder against the real engine.
