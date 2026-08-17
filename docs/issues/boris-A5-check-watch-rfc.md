# A5 — RFC: `boris validate --watch` — live, artifact-free validation as a daemon

> **Filed:** [boris#647](https://github.com/drawmeanelephant/boris/issues/647) — as an issue (Discussions disabled on the repo). Companion to A1
> ([boris-A1-watch-events.md](boris-A1-watch-events.md)) — this mode consumes
> A1's event protocol. Not a contract change; an RFC to decide whether boris
> wants a validate-only watch mode at all.
> **Rebaselined against afterparty v0.8.1.** The original framing
> (`check --watch`) is superseded: **`boris validate` now exists** — an
> artifact-free HTML preflight with an in-memory link audit — so the ask
> becomes *joining validate + watch*, which is far more tractable than
> inventing a new mode.
> Status: proposal. Priority: P1/P2. Size: M (if approved).

---

**Title:** RFC: `boris validate --watch` — join the artifact-free preflight with the watch daemon

## Summary

Afterparty has two halves of a story that don't touch:

- **`boris validate`** — artifact-free HTML source/configuration preflight:
  canonical compiler semantics, in-memory output link audit
  (`EROUTEMISSING`/`EROUTEESCAPE`/`EPUBLICATIONLOCATION` fail validation
  exactly as they fail compilation), `--report PATH` for a machine
  diagnostics report, zero writes to any output tree.
- **`boris watch`** — the daemon half: debounced (100ms) + coalesced (2s
  burst cap) rebuilds, ignore rules, graceful SIGTERM/SIGINT shutdown,
  recoverable-failure persistence.

Today **`boris validate --watch` is a usage error** (verified:
`error: conflicting options`, exit 2). The consumer that wants "is the tree
healthy *right now*, and what broke the moment it did" — an editor problems
panel, a live dashboard, a GUI — must either poll one-shot `validate` runs
(reimplementing debounce) or run full HTML watch (rendering `dist/` on every
keystroke just to get diagnostics). Both are strictly worse than what boris
could offer by joining the two halves it already has.

## Proposed design

### CLI

```
boris validate --watch [--input DIR] [--report PATH]
```

- The `watch` command's daemon loop drives the `validate` action instead of
  the HTML publish action. No new machinery: same polling watcher, same
  debounce/coalescing, same ignore rules, same signal handlers.
- `--report PATH` is **rewritten on every validation cycle** with the
  current diagnostics (`html-build-report-0.1.0` shape — already what
  one-shot `validate --report` emits) so a consumer can read the latest
  report file without parsing the stream. This is a *replacement*, not an
  append; stale-failure state cannot linger.
- No output flags are accepted (`--html-dir`, `--out`, `--rag-dir`,
  `--target`, `--serve`): this mode writes nothing but the optional report
  file. Conflicts stay exit 2.
- Because the action writes nothing, self-trigger protection is trivially
  satisfied and artifacts never churn.

### Events (consumes A1)

When A1 (`--watch-json`) lands, `validate --watch` emits the same protocol
with `mode: "validate"`:

```json
{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}
{"event":"build-started","phase":"initial","mode":"validate"}
{"event":"build-succeeded","phase":"initial","mode":"validate","errors":0}
{"event":"build-started","phase":"rebuild","mode":"validate","changed":["guides/overview.md"]}
{"event":"build-failed","phase":"rebuild","mode":"validate","changed":["guides/overview.md"],"errors":1,"diagnostics":[{"severity":"error","code":"EFRONTMATTER","message":"unknown key \"category\"","remediation":"","sourcePath":"guides/overview.md","line":2,"column":1,"id":null}]}
{"event":"watch-error","message":"poll error (BrokenPipe)","recoverable":true}
{"event":"watch-stopped","reason":"signal"}
```

Until A1 lands, the mode can ship with `--report`-file-only consumers and
the existing prose, with A1's events added when the protocol exists.

### Lifecycle

- Runs until signal; SIGINT/SIGTERM → graceful exit 0 (A12 semantics).
- Recoverable content failures keep the watcher alive (same
  `isRecoverableBuildError` rule as watch).
- Determinism: sorted changed paths, stable diagnostic order, no timestamps.

## Why this is a strong decision for boris

- It completes the "compiler as a daemon" story with the *validate-only*
  half, using two battle-tested halves that already exist. The design work
  is a seam (watch's rebuild action → validate), not a rewrite.
- It gives editors and dashboards live diagnostics with **zero artifact
  churn** — a keystroke never costs a render.
- Strictly additive: one-shot `validate`, HTML `watch`, and all artifacts
  are unchanged when the flag isn't used.
- It reuses the `mode` field A1 already defines, so the protocol family
  stays one.

## Alternatives considered

1. **Poll one-shot `validate`.** Works today with zero boris changes, but
   reimplements debounce/coalescing in every consumer and produces no
   change attribution (which page broke it).
2. **HTML `watch` + `build --report`.** Renders `dist/` on every keystroke
   and churns artifacts to get diagnostics that `validate` computes without
   writing anything.
3. **`check --watch` instead.** Also viable (graph-health findings as
   events), but `validate` already owns the no-publication HTML preflight
   and its link audit; joining watch to validate is the smaller, more
   obvious seam. `check --watch` can be a sibling mode later if the
   findings-as-events story wants its own daemon.

## Open questions

- **O1 — Report file vs events only:** is `--report` rewrite-on-cycle the
  right companion, or should the mode be stream-only until A1 lands?
- **O2 — Validation surface:** confirm v1 = `validate`'s existing surface
  (HTML source/config + in-memory link audit), no IR/RAG.
- **O3 — Name:** `validate --watch` (recommended) vs `watch --validate` vs
  a dedicated `doctor --watch`.

## Compatibility

Strictly additive. One-shot `validate` (including `--report`), HTML watch,
and all output modes are unchanged when the new flag combination isn't used.
The only existing-surface change: `validate --watch` stops being a usage
error and becomes a defined mode.

## Implementation sketch

- `src/cli.zig`: lift the `validate` × `--watch` conflict; reject output
  flags with the combination; extend conflict-rule tests.
- `src/main.zig`: `runValidateWatch` — the watch loop's rebuild action
  calls the same code path one-shot `validate` uses, then emits events
  (A1) / rewrites the report file.
- `src/watch.zig`: parameterize the coordinator's rebuild action (enum:
  `html` | `validate`) rather than branching inside; reuse everything else.

## Testing

- `FakeWatcher`-driven tests asserting exact event sequences for: initial
  clean; rebuild failure with diagnostics; change-set attribution; graceful
  shutdown.
- `--report` file is replaced (not appended) across cycles; a failed cycle
  leaves the previous report replaced with the new failure state.
- CLI parse tests: `validate --watch` valid; `validate --watch --html-dir x`
  usage error.
- Golden: one-shot `validate` output byte-identical with and without the
  new code paths.

## Acceptance criteria (for the decision)

- [ ] Decision recorded on O1/O2/O3.
- [ ] If approved: `validate --watch` streams A1 events (or rewrites the
      report), writes nothing else, exits 0 on signal; one-shot `validate`
      and HTML watch unchanged.
