# A5 — RFC: `boris check --watch` — live diagnostics as a daemon

> **Design discussion for the boris repo.** Companion to A1
> ([boris-A1-watch-events.md](boris-A1-watch-events.md)) — this mode consumes
> A1's event protocol. Not a contract change; an RFC to decide whether boris
> wants a validate-only watch mode at all.
> Status: proposal. Priority: P1/P2. Size: L (if approved).

---

**Title:** RFC: `boris check --watch` — recompile in memory, emit diagnostics as events, never touch outputs

## Summary

Watch mode exists but is HTML-only: it rebuilds a site on every change and
writes artifacts. `check` exists but is one-shot: it compiles read-only,
analyzes graph health, prints a report, exits. Neither gives a consumer what
an editor or live-dashboard actually wants — **continuous, artifact-free
validation**: "is the tree healthy right now, and what broke the moment it
did?" Today that consumer either (a) polls one-shot `check` runs, (b) runs
HTML watch and scrapes stderr prose while churning `dist/` on every keystroke,
or (c) reimplements a file watcher itself. All three are strictly worse than
what boris could offer with two existing halves joined.

## The key insight: the seam already exists

- **`check` already compiles in memory and writes nothing.** `runIntelligence`
  (`src/main.zig:165`) calls `pipeline.compile` with `.quiet = true`, runs
  `intelligence.analyze` over the resulting pages/edges, and prints (or
  `--report`s). It never touches `dist/`, `.boris/`, or any cache. The
  "recompile in memory without touching outputs" behavior is *today's code*,
  just run once.
- **Watch mode already has all the machinery.** `WatchCoordinator`
  (`src/watch.zig`) owns: polling watcher with ignore rules
  (`.boris-cache`, `dist`), 100ms debounce, 2s coalescing burst cap, sorted
  pending-path tracking, SIGINT/SIGTERM graceful shutdown, and per-target
  fan-out. The only thing it does with a change is call
  `compileHtmlSite`/`compileHtmlSiteMulti` and print prose.
- **Today `boris check --watch` is a usage error** (exit 2,
  `error: conflicting options` — verified). The conflict rule exists because
  `--watch` promises HTML; this RFC redefines what `--watch` can promise.

So the proposal is: let the watch coordinator drive the *check* action
instead of the *HTML publish* action, and emit results over A1's event
protocol instead of prose.

## Proposed design

### CLI

```
boris check --watch [--input DIR] [--format json]
```

- Extends the existing `check` command; lifts the `--watch` conflict *for
  the check command only*. `--watch` on HTML/IR/RAG/context modes keeps its
  current meaning and rules.
- `--format json` controls the *findings payload* shape inside events (see
  below). Human prose is not emitted in this mode at all; A1's
  `--watch-json`-style exclusivity applies (stderr = NDJSON only).
- No output flags are accepted (`--html-dir`, `--out`, `--rag-dir`,
  `--target`, `--report`): this mode writes nothing, and the conflict rules
  should say so loudly (exit 2) rather than silently ignore.

### Event protocol (reuses A1 verbatim where possible)

The stream is A1's NDJSON with the same `hello` handshake
(`watch_events_schema`, `compiler`) and the same lifecycle events. The only
delta is what `build-*` events carry:

```json
{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.0"}
{"event":"build-started","phase":"initial","mode":"check"}
{"event":"build-succeeded","phase":"initial","mode":"check","errors":0,"findings":{"unreferenced_pages":1,"hotspots":0}}
{"event":"build-started","phase":"rebuild","mode":"check","changed":["guides/overview.md"]}
{"event":"build-failed","phase":"rebuild","mode":"check","changed":["guides/overview.md"],"errors":1,"diagnostics":[{"severity":"error","code":"EFRONTMATTER","message":"unknown key \"category\"","remediation":"","sourcePath":"guides/overview.md","line":2,"column":1,"id":null}]}
{"event":"watch-error","message":"poll error (BrokenPipe)","recoverable":true}
{"event":"watch-stopped","reason":"signal"}
```

- `mode: "check"` distinguishes this from HTML-watch events (same schema, so
  consumers gate on `watch_events_schema` and branch on `mode`).
- `build-succeeded` carries the analysis summary (`findings`) when the
  intelligence pass runs — the `unreferenced_pages` / `hotspots` numbers
  consumers need for a graph-health indicator. Full findings payload (the
  existing `renderAnalysisJson` shape) is available on request; open question
  O2 below.
- `build-failed` carries the full diagnostic objects — identical shape to
  `build-report.json` — because the pipeline already holds them.
- `pages_written` / `targets` are absent: nothing is written.

### What the coordinator does differently

The delta in `WatchCoordinator` is one seam: the rebuild action becomes
"run `pipeline.compile` (the check path) and emit events" instead of "run
`compileHtmlSite` and print prose." Everything else — polling, ignore rules,
debounce, burst cap, signal handlers, graceful shutdown — is reused
verbatim. Because the action writes nothing:

- **Self-trigger protection is trivially satisfied** (no own-writes to
  ignore).
- **Zero artifact churn** — no `dist/` writes, no cache-manifest updates,
  no `.boris-stage`; a keystroke never costs a render.
- **Determinism holds** — sorted paths, stable diagnostic order, no
  timestamps in the payloads (duration/`at` stay optional metadata as in A1).

### Exit codes and lifecycle

- Runs until signal; SIGINT/SIGTERM → graceful exit 0 (A12 semantics).
- Findings are **events, not exit codes** — the one-shot `check` exit-1-on-
  findings contract is untouched; this is a daemon, and a daemon has no
  final exit code to signal findings with.

## Why this is a strong decision for boris

- It completes the "compiler as a daemon" story with the *validate-only*
  half that editors and dashboards want, without asking consumers to render
  sites to get diagnostics.
- It reuses two battle-tested halves (read-only compile + watch machinery)
  rather than inventing anything; the design work is a seam, not a rewrite.
- It is strictly additive: one-shot `check`, HTML watch, IR/RAG/context, and
  all artifacts are byte-identical when the flag isn't used.
- It keeps the single-binary, no-server posture — a live diagnostics stream
  on stderr, not IPC.

## The real design work (honest scope)

The pipeline surface question is the actual decision:

- **v1 (recommended): the `check` surface.** `pipeline.compile` +
  `intelligence.analyze` — scan, parse, frontmatter, graph topology, IR
  dependency resolution. This is what `check` already validates, so the
  semantics are defined today.
- **Follow-up: the HTML surface.** Full HTML validation minus publish
  (layout marker, includes, wiki-links, components, content-local assets —
  the `EINCLUDEMISSING`/`EREFERENCEMISSING`/`EASSET` class). This is *not*
  free: `compileHtmlSite` currently couples validation with rendering and
  layout loading, so factoring "validate without render/publish" out of the
  HTML pipeline is real refactoring. Worth its own issue if there's appetite.

The RFC deliberately proposes v1 scope; the HTML surface is the extension
path, not the first step.

## Alternatives considered

1. **Poll one-shot `check`.** Works today with zero boris changes, but
   reimplements debounce/coalescing in every consumer, has no incremental
   cost savings, and produces no change attribution (which page broke it).
2. **HTML watch + poll artifacts.** Renders on every keystroke, churns
   `dist/`, publishes no `build-report.json`, and diagnostics only exist on
   failure — no graph-health signal at all.
3. **A1 only, no check-watch.** Consumers get typed events but still have to
   choose between rendering HTML or polling one-shot checks; A1 makes the
   prose pain go away but not the render-or-poll dilemma.
4. **App-side watcher (status quo workaround).** Fine, but duplicates
   machinery boris already owns and tests.

## Open questions

- **O1 — Validation surface:** confirm v1 = `check` surface (recommended)
  vs HTML-full-minus-publish as v1.
- **O2 — Findings in events:** emit full findings array, or just the summary
  numbers? (Recommend summary in `build-succeeded` + full report via a
  `--report`-style opt-in, keeping events lean.)
- **O3 — State-change events:** add an explicit `diagnostics-clear` event
  (or rely on `build-succeeded` with `errors: 0`)? (Recommend the latter —
  fewer event types.)
- **O4 — Naming:** `check --watch` (recommended; reuses an existing command)
  vs `boris --diagnostics --watch` vs a new `doctor` command.
- **O5 — Watch roots:** `--watch` for check should watch the content root +
  nothing else (no layouts), since no layout is loaded in v1 scope.

## Compatibility

Strictly additive. One-shot `check` (including its exit-1-on-findings CI
contract), HTML watch, and all output modes are unchanged when the new flag
combination isn't used. The only existing-surface change is that
`check --watch` stops being a usage error and becomes a defined mode.

## Implementation sketch

- `src/cli.zig`: allow `--watch` for the `check` command; reject output
  flags with it; extend the conflict-rule tests.
- `src/main.zig`: `runCheckWatch(io, gpa, opts)` — the watch loop's rebuild
  action calls the same `pipeline.compile` + `intelligence.analyze` path
  `runIntelligence` uses, then emits events via the A1 NDJSON writer.
- `src/watch.zig`: parameterize the coordinator's rebuild action (enum:
  `html` | `check`) rather than branching inside; reuse everything else.
- `src/json_out.zig` / A1: the NDJSON event writer and schema land with A1;
  check-watch is its first consumer.

## Testing

- `FakeWatcher`-driven tests asserting exact event sequences for: initial
  success with findings summary; rebuild failure with a diagnostics array;
  change-set attribution; graceful shutdown (A12 latch test applies).
- CLI parse tests: `check --watch` valid; `check --watch --out x` usage
  error; `check --watch --report x` usage error.
- Golden: one-shot `check` output byte-identical with and without the new
  code paths.

## Acceptance criteria (for the decision)

- [ ] Decision recorded on scope (O1), findings payload (O2/O3), and naming
      (O4).
- [ ] If approved: `check --watch` streams A1 events on stderr, writes
      nothing, exits 0 on signal; one-shot `check` and HTML watch unchanged.
