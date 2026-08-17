# A1 — `--watch-json`: structured NDJSON event stream for watch mode

> **Filed:** [boris#644](https://github.com/drawmeanelephant/boris/issues/644).
> **Fixed by:** [boris#648](https://github.com/drawmeanelephant/boris/pull/648) (merged into `afterparty` 2026-08-17).
> Priority: P0 (flagship). Size: M. Additive, opt-in — no behavior change without the flag.
> **Rebaselined against afterparty v0.8.1.** Afterparty added `watch --serve`
> (an SSE `reload` channel for *browsers*) and `--timings` (one-shot machine
> timing on stdout). This issue completes the machine surface for
> *subprocess* consumers, which still get prose.

---

**Title:** `--watch-json`: machine-readable NDJSON event stream for watch mode

## Summary

Boris's contract discipline is its identity: every surface that produces
output for humans also produces a typed, versioned, machine-readable form —
IR artifacts, analysis reports, diagnostics, exit codes, `--timings`,
`--version`. **Watch mode is the one surface that doesn't.** Its stderr is
still prose:

```
watch: performing initial build...
  wrote dist/comparison.html
  wrote dist/getting-started.html
…
watch: received shutdown signal, cleaning resources...
```

Afterparty gave browsers a channel — `watch --serve` serves the built tree
on loopback and streams `event: reload` over SSE at `/__boris/events` — but
that is a *served* channel for a page, not a process contract. Anything that
drives `boris watch` as a subprocess — an editor plugin, a GUI, a CI
dashboard, a dev-server wrapper — still must either regex-parse the prose
(fragile) or poll the output tree. Watch mode is a compile *daemon*, and a
daemon without a typed event protocol is the one hole in the compiler's
otherwise-complete process ABI.

## Proposal

Add an opt-in flag `--watch-json`. When set:

- **stderr carries exclusively NDJSON** — one JSON object per line, no human
  prose, no diagnostic text lines (equivalent to implying `--quiet`).
- **stdout is unchanged.** **`--serve` is compatible** — the SSE reload
  channel keeps serving browsers; NDJSON is the sibling subprocess channel.
- **All output artifacts are byte-identical** to a non-`--watch-json` run.

`--watch-json` without the `watch` command is a usage error (exit 2), so a
typo can't silently produce an empty stream.

## Event schema

First line of the stream is a handshake so consumers can gate on the event
contract version (mirrors how the IR artifacts gate on `schemaVersion`):

```json
{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}
{"event":"build-started","phase":"initial","mode":"html","targets":["default"]}
{"event":"build-succeeded","phase":"initial","mode":"html","targets":["default"],"pages_written":25,"duration_ms":312}
{"event":"watcher-started","mode":"html","targets":["default"]}
{"event":"serve-started","url":"http://127.0.0.1:53202/","helper":"http://127.0.0.1:53202/__boris/","port":53202}
{"event":"build-started","phase":"rebuild","mode":"html","targets":["default"],"changed":["guides/overview.md","index.md"]}
{"event":"build-succeeded","phase":"rebuild","mode":"html","targets":["default"],"changed":["guides/overview.md","index.md"],"pages_written":2,"duration_ms":18}
{"event":"build-failed","phase":"rebuild","mode":"html","targets":["default"],"changed":["guides/overview.md"],"errors":1,"diagnostics":[{"severity":"error","code":"EFRONTMATTER","message":"unknown key \"category\"","remediation":"","sourcePath":"guides/overview.md","line":2,"column":1,"id":null}],"recoverable":true,"duration_ms":14}
{"event":"watch-error","message":"poll error (BrokenPipe)","recoverable":true}
{"event":"watch-stopped","reason":"signal"}
```

### Fields

| Field | Type | Events | Notes |
|-------|------|--------|-------|
| `event` | string | all | Enum: `hello`, `build-started`, `build-succeeded`, `build-failed`, `watcher-started`, `serve-started`, `watch-error`, `watch-stopped` |
| `watch_events_schema` | int | `hello` | Version of this event contract. Consumers must refuse (or surface) unknown versions. |
| `compiler` | string | `hello` | `pipeline.compiler_id` (e.g. `boris/0.8.1`). |
| `mode` | string | build-*, watcher-started | Which surface the build is for. `html` today; `validate`/`check` if A5 (`validate --watch`) lands. |
| `phase` | string | build-* | `initial` \| `rebuild` |
| `targets` | string[] | build-*, watcher-started | For selective rebuilds, the subset actually rebuilt, not the full configured set. |
| `changed` | string[] | build-* (rebuild) | Content-relative paths, sorted, exactly the keys logged after the changed-path listing today. |
| `pages_written` | int | build-succeeded | Initial-build value available today; rebuild value requires capturing the `CompileStats` the coordinator currently discards. Optional on rebuild if undesired. |
| `errors` | int | build-failed | Count of `error`-severity diagnostics in `diagnostics`. |
| `diagnostics` | array | build-failed | Diagnostic objects **byte-identical in shape and field order** to `build-report.json` / `html-build-report-0.1.0`: `severity, code, message, remediation, sourcePath, line, column, id`. |
| `recoverable` | bool | build-failed, watch-error | Whether the watch loop continues (recoverable content/layout errors) or exits (unrecoverable I/O). |
| `duration_ms` | int | build-* | Wall time of the compile. |
| `message` | string | watch-error | The `@errorName(err)` text. |
| `reason` | string | watch-stopped | `signal` (SIGINT/SIGTERM handler) today; future stop reasons add values. |
| `url` | string | serve-started | `http://127.0.0.1:<port>/` — only when `--serve` is on. |
| `helper` | string | serve-started | `http://127.0.0.1:<port>/__boris/` — the auto-reload helper page. |
| `port` | int | serve-started | The bound loopback port (required for `--port 0`). |

## Mapping to existing emission points

All events slot into code paths that already exist in the watch coordinator
(no new phases, no restructured control flow); the existing stderr lines
mark the points:

| Event | Existing site |
|-------|---------------|
| `hello` | Start of the watch run, before the initial build |
| `build-started` (initial) | `watch: performing initial build...` |
| `build-succeeded` (initial) | the per-page `wrote <path>` block ends (stats available) |
| `watcher-started` | After initial build, before the poll loop / signal handlers |
| `serve-started` | `preview: http://127.0.0.1:{d}/  (auto-reload helper: …)` in `watch.zig` after `s.start()` — **must emit even when quiet**. Today's prose line is gated on `!quiet`; `--watch-json` implying quiet would otherwise hide the only port discovery the `--serve` consumer has. |
| `build-started` (rebuild) | the changed-path listing + rebuild trigger |
| `build-succeeded` (rebuild) | `watch: rebuild succeeded.` |
| `build-failed` | the `error: … rebuild failed` / `initial build failed` sites; `recoverable` from `isRecoverableBuildError` |
| `watch-error` | the poll-error retry line |
| `watch-stopped` | `watch: received shutdown signal, cleaning resources...` |

Because the compiler already prints structured diagnostic text lines to stderr
during watch compiles, the `build-failed` event's `diagnostics` array should
carry the same objects (the pipeline already holds them as structured data;
`--watch-json` should suppress the text form, not the data).

## Why this is a strong decision for boris

- It **completes the machine-contract story**: watch mode joins IR, analysis,
  diagnostics, `--timings`, and `--version` as a typed, versioned, documented
  surface (`docs/contracts/watch-mode.md` already exists as the home).
- Afterparty already gave browsers the SSE channel; this gives the *same*
  compile daemon a subprocess channel. The two are siblings, not rivals —
  the issue explicitly keeps `--serve` compatible.
- Purely additive and opt-in; without the flag, stderr and all artifacts are
  byte-identical to today. Human users lose nothing; tool users gain a
  contract.
- The event schema reuses existing shapes and constants (`compiler_id`,
  diagnostic objects, sorted content-relative paths) — nothing new is
  invented, only serialized.
- The `mode` field future-proofs the protocol for A5 (`validate --watch`).

## Alternative considered

Canonicalize and document the existing human line grammar instead. Cheaper,
but leaves consumers regex-parsing prose with no schema versioning — strictly
worse for a durable contract. Rejected as primary; the grammar should still be
documented (see A4).

## Testing (matches repo conventions)

- `FakeWatcher`-driven integration tests asserting the **exact NDJSON line
  sequence** (stable key order via `json_out`) for: initial success; rebuild
  success with a multi-file changed set; recoverable rebuild failure carrying
  a `diagnostics` array; unrecoverable failure ending the stream; selective
  multi-target rebuild emitting the subset in `targets`; shutdown on signal.
- CLI parse tests: `--watch-json` valid with the `watch` command; usage error
  without.
- Golden assertion that non-`--watch-json` output is unchanged.

## Acceptance criteria

- [ ] `boris watch --watch-json` emits the NDJSON stream above on stderr,
      nothing else, with `hello` first and `watch-stopped` last.
- [ ] `boris watch --watch-json --serve` serves both channels: SSE reload
      for browsers, NDJSON for the subprocess. `--port 0` emits
      `serve-started` with the bound `port` / `url` / `helper` even when
      quiet.
- [ ] `build-failed` events carry diagnostics in the shared report shape;
      `recoverable` distinguishes loop-continuing failures.
- [ ] Existing watch behavior and artifacts unchanged without the flag.
- [ ] Event contract documented under `docs/contracts/watch-mode.md`.

## Non-goals

- No change to the human lines, exit codes, or any artifact format.
- No library/JSON-RPC mode (see A10) — this is a stream on stderr, not IPC.
