# Engine Work & Design Decisions — Solipsist ↔ Boris

**Date:** 2026-08-17
**Status:** brainstorming notes — companion to [PLAN-MAC-APP.md](PLAN-MAC-APP.md)
**Engine baseline:** ⚠️ **afterparty line, boris v0.8.1 candidate** (`boris/0.8.1`, IR schema `0.2.0`) — **not `main` v0.8.0**.
`main` is frozen; `afterparty` (847 commits ahead) is where everything current lives. The local
boris checkout is on `afterparty`, and the bundled engine is built from it. Full capability map:
[BORIS-CAPABILITIES.md](BORIS-CAPABILITIES.md). Mission: [MISSION.md](MISSION.md).

## ✅ Issue-batch reconciliation — DRAFTS RE-BASELINED (2026-08-17)

All drafts in `docs/issues/` are re-written against the afterparty binary; statuses are final:

| Issue | Status after re-baselining | Notes |
|-------|---------------------------|-------|
| A2 `--version` | ⛔ **withdrawn** | Shipped on afterparty: `boris --version` → `boris/0.8.1`, exit 0, test-pinned; A8 `init` and A9 (`--fail-on-unreferenced`) too — evidence in `boris-A2-version-flag.md` |
| A1 watch events | ✅ **ready** | Typed events for subprocess consumers; cites `watch --serve`'s SSE channel as the browser sibling; `mode` field future-proofs A5 |
| A3 compiler in IR build-report | ✅ **filed [boris#638](https://github.com/drawmeanelephant/boris/issues/638)** | The naming zoo: `manifest`=`compiler`, `completion`=`compiler_id`, `html-build-report`=`compilerId`, IR build-report=absent — the sharpest consistency gap |
| A4 stream docs + `--report` help | ✅ **filed [boris#639](https://github.com/drawmeanelephant/boris/issues/639)** | Help still says `--report … instead of stdout` (verified); stdout is now a machine payload surface (`--version`, `--timings`, plans) — document the rule |
| A6 completion signal | ⛔ **moot** | `build --report` solved the original ask; the cache-manifest doc idea is P2 nice-to-have, not a blocker |
| A7 workspace rule | ✅ **ready** | Containment now uniform (HTML/IR/RAG/context verified); docs ask + the IR absolute-output-path quirk (`--out /abs` inside cwd escapes, HTML doesn't) |
| A12 signal contract | ⛔ **moot** | watch-mode.md §6 documents signals; C06 pins exit classes; shutdown-latch test is nice-to-have |
| A13 watch recovery bug | ✅ **filed [boris#640](https://github.com/drawmeanelephant/boris/issues/640)** | Verified: `GraphValidationFailed` on a rebuild exits the watcher (contract says recoverable); should recover like `ParseFailed` |
| A5 `check --watch` RFC | 🔵 **ready (reformulated)** | `boris validate` exists — the RFC is now `validate --watch` (join validate + watch, A1 events), far more tractable |

**Filing order:** A1 → A7 → A5 RFC (A3/A4/A13 already filed; A6/A12 moot). See `docs/issues/README.md`.

This document lists (A) the work we should ask Boris to do — phrased as
ready-to-file GitHub issues — and (B) the design decisions we need to make on
the Solipsist side. The guiding rule throughout: **everything proposed for
Boris must be strictly additive or opt-in, and must not touch the properties
that make Boris Boris** — deterministic output, stable exit codes, closed
frontmatter, workspace containment, single-native-binary.

Fact-checked against boris `afterparty` this session (v0.8.1 candidate).
The early session's facts were gathered against `main` v0.8.0; the deltas
are called out inline:

- **`--version` / `-V` EXISTS on afterparty** (`boris/0.8.1`, stdout, exit 0,
  no content scan; pinned by `test-version-pin`) — this was a gap on `main`.
  → **A2 withdrawn.**
- **Containment now covers ALL output trees** (verified): `--html-dir`,
  `--target`, `--out` (IR), `--rag-dir`, `--context-dir` outside cwd all
  fail with `WorkspaceEscape` (exit 2). The earlier `main`-era asymmetry
  (IR/RAG/context wrote anywhere) is resolved. `--report` single-file paths
  remain free. Boundary: process cwd, path-boundary check, root collision is
  `TargetOutputCollision`. → **A7 reduced to a docs ask.**
- Analysis reports (`check` / `impact`) print to **stderr** by default;
  `--report PATH` writes them to a file. **`check` no longer fails on
  findings** — exit 0 with unreferenced pages; `--fail-on-unreferenced` is
  the CI opt-in (verified: 0 by default, 1 with the flag). → **A9 withdrawn.**
- IR `build-report.json` still has **no `compiler` field** (verified), while
  the new `html-build-report-0.1.0` (via `build --report PATH`) **does**
  (`compilerId`) and is written on success *and* failure. → **A3 reframed as
  HTML/IR report parity.**
- Watch mode is **HTML-only** and emits human-readable lines to stderr, but
  afterparty adds `watch --serve`: a loopback HTTP server (default port
  8090) with an SSE reload stream at `/__boris/events` (browser channel).
  The new `validate` command is an artifact-free preflight with an in-memory
  link audit. → **A1 reframed (typed events still missing for subprocess
  consumers; cite `--serve`); A5 becomes `validate --watch`.**
- Incremental HTML builds atomically write `.boris-cache/manifest.json`
  (`format_version: "boris-cache-v2-layout-rules"`) with per-page
  fingerprints, output paths, digests — a ready-made build-completion signal.
  `build --report PATH` now also gives HTML a machine result artifact on
  success and failure. → **A6 mostly done.**
- **Kill/cancel is clean (verified empirically on `main`; afterparty's C06
  conformance pins watch failure/exit classes):** watch catches SIGTERM/
  SIGINT → graceful exit 0 within one idle poll (≤500ms) with a cleanup
  message; an in-flight rebuild completes before shutdown (no partial
  publish); SIGKILL leaves no `.boris-stage` leftovers and the last-good
  cache manifests intact, and the next build recovers. No orphan processes.
  The app distinguishes "cancelled" via Swift
  `Process.terminationReason == .uncaughtSignal`, not a Boris exit code
  (→ A12, reduced).

---

## Part A — Issues to file against Boris

> Ready-to-paste issue bodies live in [`docs/issues/`](issues/) (batch
> overview: [`issues/README.md`](issues/README.md) — each issue is framed to
> stand on its own for boris, independent of Solipsist): A1
> ([boris-A1-watch-events.md](issues/boris-A1-watch-events.md)), A2
> ([boris-A2-version-flag.md](issues/boris-A2-version-flag.md)), A3
> ([boris-A3-build-report-compiler.md](issues/boris-A3-build-report-compiler.md)),
> A4 ([boris-A4-stream-contract.md](issues/boris-A4-stream-contract.md)), A6
> ([boris-A6-completion-signal.md](issues/boris-A6-completion-signal.md)), A7
> ([boris-A7-workspace-rule.md](issues/boris-A7-workspace-rule.md)), A12
> ([boris-A12-signal-contract.md](issues/boris-A12-signal-contract.md)). Each
> was fact-checked against the current source (exact stderr lines, emission
> points, exit-code table, existing doc stubs) so they can be filed as-is.
> The consumer-driven contract audit that produced the bucketing
> (🟢/🟡/🔴) is in [CONTRACT-AUDIT.md](CONTRACT-AUDIT.md).

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
`boris check --watch` (RFC drafted:
[boris-A5-check-watch-rfc.md](issues/boris-A5-check-watch-rfc.md)). Fact-checked
findings that shaped the RFC:

- The seam already exists: `check`/`impact` (`runIntelligence`) calls
  `pipeline.compile` read-only (`.quiet = true`) then `intelligence.analyze`
  — "recompile in memory without writing" is today's one-shot code.
- The watch coordinator already owns debounce/coalescing/ignore-rules/
  signals — only the rebuild *action* changes (HTML publish → validate +
  emit A1 events).
- `boris check --watch` is **currently a usage error** (exit 2,
  `error: conflicting options` — verified) — the RFC redefines it.
- Honest scope: v1 = the `check` surface (scan/parse/graph/IR); the full
  HTML surface (includes/wiki-links/assets) requires factoring validate from
  render in the HTML pipeline — real refactoring, deferred.

**Why it's not a compromise.** The compile/validate path is the same
deterministic pipeline; we just opt into not writing outputs. It needs a
Boris-side RFC because it touches watch-mode's conflict rules — hence P1/P2,
not P0. If Boris declines, Solipsist does its own FSEvents watcher + one-shot
IR builds (Part B, decision D3) and this becomes a non-issue.

### A6. A written completion/result signal for one-shot builds — **moot** (solved by `build --report`)

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

### A12. Document signal/cancellation behavior — **moot** (documented in watch-mode.md §6)

**Problem.** The user-asked question: *"can I kill Boris?"* The behavior is
good — verified: SIGTERM/SIGINT → graceful exit 0 (≤500ms, cleanup
message); an in-flight rebuild finishes before shutdown (latch checked
between loop iterations, so no partial publish); SIGKILL leaves no
`.boris-stage` leftovers, last-good manifests intact, next build recovers.
But none of it is documented as a contract, so a GUI consumer either
discovers it empirically or assumes the worst and builds process-killing
workarounds.

**Proposal.** A short Signals section in `docs/contracts/watch-mode.md`
(drafted in [boris-A12-signal-contract.md](issues/boris-A12-signal-contract.md)):
the signal table above, the "rebuild completes before shutdown" rule, the
SIGKILL atomicity guarantee, and the note that consumers infer *cancelled*
from OS signal-termination status, not a Boris exit code.

**Why it's not a compromise.** Docs only; the behavior already exists and is
sound. App-side, we still enforce our own timeout + SIGKILL escalation — the
subprocess boundary makes that safe by construction.

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
| A12 | Document signal/cancellation | XS | P1 | ✅ docs |

**Suggested filing order:** A2 + A4 first (XS, docs, unblock us immediately),
then A1 (+A11) as the flagship P0, then A3 + A6 + A7 + A12 (all XS), then the
A5 design discussion. The 🔴/🟡/🟢 bucketing in
[CONTRACT-AUDIT.md](CONTRACT-AUDIT.md) says the same thing: the watch-prose
(A1/A5), HTML-result (A6), and versioning (A2/A3) gaps are the architectural
blockers to feed back into Boris.

---

## Part B — Solipsist-side design decisions

These are decisions *we* own. Statuses reflect the afterparty re-baseline
(2026-08-17).

### D1. Where build artifacts live — ✅ decided: Boris defaults

The app runs boris with `cwd = project folder`; afterparty confines **all**
output trees to the cwd (`WorkspaceEscape`, exit 2). Artifacts stay at Boris
defaults — `dist/`, `.boris/`, `rag/`, `context/`, `llms.txt` — so the
project stays CLI-compatible and the security-scoped bookmark covers them.
README guidance gitignores `dist/`, `.boris/`, `.boris-cache/`, `rag/`,
`context/`, `llms.txt`. (No hidden `.solipsist/` folder.)

### D2. Settings storage — ✅ decided: two layers, split by what Boris consumes

afterparty ships a native project config (`boris.json`,
`boris-publication-profile` schema v1), so the old app-vs-repo question
resolves by ownership:

- **Project configuration → the Boris profile (repo-side):** `input`,
  `input_format`, `site`, `publication`, `targets`, `editions`. This is what
  `plan` validates and `build --profile` consumes — the single shareable,
  reproducible, `plan`-validated truth. The console edits this file.
- **Execution controls + machine-local state → app-side plist:** `jobs`,
  `incremental`, `quiet` (deliberately *not* plan identity), plus window
  layout, recent projects, pinned preview port, last-opened project.

Rule: if a setting affects Boris output it lives in the profile; the plist
never duplicates it.

### D3. Who watches the files — ✅ decided: Boris owns it; no app-side watcher

- **Preview:** `boris watch --serve` (debounce/coalescing, self-trigger
  protection, loopback + SSE reload).
- **Diagnostics:** save-triggered `boris validate --report` (artifact-free;
  binary-verified to run alongside `watch`). No FSEvents watcher, no one-shot
  IR builds for diagnostics.
- **Revisit:** A5 (`validate --watch`) would fold diagnostics into the daemon;
  not required in the meantime.

### D4. Editor scope for v1 — ✅ decided

**Decision: native ergonomics + embedded `boris-editor`. No from-scratch
native editor in v1.**

- **Authoring** is `boris-editor` embedded in a `WKWebView`: the app spawns
  the Zig loopback host and loads its session-token URL. Fallback if the
  sandbox/token/CSP spike fails: "Open in Boris Editor" (link out).
- **Solipsist builds the native ergonomics around it**, not a text editor:
  the problems panel (`validate --report` + IR `build-report.json`), the
  completion-driven frontmatter/theme inspector (`completion.json`), and
  preview (`watch --serve`).
- **Rationale:** `boris-editor` is compiler-owned — its completion is sourced
  exclusively from `completion.json` and its problems panel consumes only
  Boris-owned reports. A native editor would reimplement that coupling,
  against the "never reimplement Boris semantics in Swift" boundary.
  Solipsist's real edge is Mac citizenship (security-scoped open, menus,
  bookmarks) + the publishing console, not text editing.
- **Revisit trigger:** only if the embed proves brittle on real content or a
  concrete native-editor need (pasteboard/drag-drop/Spotlight) outweighs the
  duplication cost. That is post-M5, not v1.

Tradeoffs accepted: the embed is a browser surface inside a native app;
building `boris-editor`'s Svelte UI needs `npm` at *build* time (runtime
stays toolchain-free). Pin the editor to the same `b82e9e2` commit as the
engine.

### D5. Preview transport — ✅ decided: engine-owned `watch --serve`

afterparty ships the preview server, so the app writes neither an HTTP
server nor uses `file://`. The app runs `boris watch --serve --port 0`,
parses the one stderr startup line for the ephemeral port, and loads
`http://127.0.0.1:PORT/__boris/` in a `WKWebView`; SSE `event: reload`
drives refresh. Entitlements: `network.server` (loopback listen);
`network.client` only for remote theme assets or publication flows.

### D6. Sandbox vs non-sandbox — ✅ decided: stay sandboxed

Security-scoped bookmarks for project folders; `network.server` for the
preview server; `network.client` added only when publication/remote assets
need outbound. Nothing in v1 needs unsandboxed access.

### D7. Engine provisioning & version policy — ✅ decided: bundle + pin

Bundle the engine in the app (no download-on-first-run). **Pin commit
`b82e9e2` (`boris/0.8.1`)**; vendor the SHA256-verified agent-kit binary
when present, else rebuild from the pin (see
[`AGENT-KIT-REVIEW.md`](AGENT-KIT-REVIEW.md)). Gate features on IR
`schemaVersion` (D8), not assumed compatibility. About screen shows the
compiler id (`boris --version`).

### D8. SchemaVersion gating policy — ✅ decided

Decoders branch on `schemaVersion` (string `"0.2.0"` on IR artifacts, integer
`1` on `completion.json`) and degrade, never crash:

- `schemaVersion == "0.2.0"` → full feature set.
- Unknown/newer → "engine newer than app" banner; disable IR-dependent
  features or degrade to HTML-only.

Consider generating the Codable mirrors from the published JSON Schemas under
`docs/contracts/schemas/`.

### D9. Project identity & detection — ✅ decided: any folder; `boris init` for new projects

Any folder is a project (default input root `content/`). "New Project" runs
`boris init` (shipped on afterparty) — no app-side template.

### D10. Watch-stderr fallback parsing — ⛔ withdrawn (superseded by afterparty)

No stderr parser. `build --report` / `validate --report` (machine JSON) and
`watch --serve`'s SSE reload replaced prose parsing; the only stderr line the
app parses is the `watch --serve` startup port line.

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
