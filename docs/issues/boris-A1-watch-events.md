# A1 — `--watch-json`: structured NDJSON event stream for watch mode

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P0 (flagship). Size: M. Additive, opt-in — no behavior change without the flag.

---

**Title:** `--watch-json`: machine-readable NDJSON event stream for watch mode

## Summary

Boris's contract discipline is its identity: every surface that produces
output for humans also produces a typed, versioned, machine-readable form —
IR artifacts, analysis reports, diagnostics, exit codes. **Watch mode is the
one surface that doesn't.** Its entire output is human prose on stderr:

```
watch: changed paths detected:
  - guides/overview.md
watch: triggering incremental rebuild...
watch: rebuild succeeded.
```

Anything that drives `boris --watch` as a subprocess — an editor plugin, a
dev-server wrapper, a GUI, a CI dashboard, a `watch(1)`-style script — must
either regex-parse this prose (fragile, breaks on any wording change) or
ignore it and poll the output tree. Watch mode is effectively a compile
*daemon*, and a daemon without a typed event protocol is the one hole in the
compiler's otherwise-complete process ABI.

## Proposal

Add an opt-in flag `--watch-json`. When set:

- **stderr carries exclusively NDJSON** — one JSON object per line, no human
  prose, no diagnostic text lines (equivalent to implying `--quiet`).
- **stdout is unchanged** (still empty on the success path).
- **All output artifacts are byte-identical** to a non-`--watch-json` run.

`--watch-json` without `--watch` is a usage error (exit 2), so a typo can't
silently produce an empty stream.

## Event schema

First line of the stream is a handshake so consumers can gate on the event
contract version (mirrors how the IR artifacts gate on `schemaVersion`):

```json
{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.0"}
{"event":"build-started","phase":"initial","targets":["default"]}
{"event":"build-succeeded","phase":"initial","targets":["default"],"pages_written":45,"duration_ms":312}
{"event":"watcher-started","targets":["default"]}
{"event":"build-started","phase":"rebuild","targets":["default"],"changed":["guides/overview.md","index.md"]}
{"event":"build-succeeded","phase":"rebuild","targets":["default"],"changed":["guides/overview.md","index.md"],"pages_written":2,"duration_ms":18}
{"event":"build-failed","phase":"rebuild","targets":["default"],"changed":["guides/overview.md"],"errors":1,"diagnostics":[{"severity":"error","code":"EFRONTMATTER","message":"unknown key \"category\"","remediation":"","sourcePath":"guides/overview.md","line":2,"column":1,"id":null}],"recoverable":true,"duration_ms":14}
{"event":"watch-error","message":"poll error (BrokenPipe)","recoverable":true}
{"event":"watch-stopped","reason":"signal"}
```

### Fields

| Field | Type | Events | Notes |
|-------|------|--------|-------|
| `event` | string | all | Enum: `hello`, `build-started`, `build-succeeded`, `build-failed`, `watcher-started`, `watch-error`, `watch-stopped` |
| `watch_events_schema` | int | `hello` | Version of this event contract. Consumers must refuse (or surface) unknown versions. |
| `compiler` | string | `hello` | `pipeline.compiler_id` (e.g. `boris/0.8.0`). |
| `phase` | string | build-* | `initial` \| `rebuild` |
| `targets` | string[] | build-*, watcher-started | For selective rebuilds, the subset actually rebuilt (from `selectTargetsForRebuild`), not the full configured set. |
| `changed` | string[] | build-started/succeeded/failed (rebuild) | Content-relative paths, sorted, exactly the keys currently logged after `watch: changed paths detected:`. |
| `pages_written` | int | build-succeeded | Available for the initial build today; for rebuilds this requires capturing the `CompileStats` the coordinator currently discards (`_ = compile.compileHtmlSite(...)` in `triggerRebuild`). Optional on rebuild if undesired. |
| `errors` | int | build-failed | Count of `error`-severity diagnostics in `diagnostics`. |
| `diagnostics` | array | build-failed | Diagnostic objects **byte-identical in shape and field order** to `build-report.json`: `severity, code, message, remediation, sourcePath, line, column, id` (see `docs/contracts/diagnostics.md`). |
| `recoverable` | bool | build-failed, watch-error | Whether the watch loop continues (recoverable content/layout errors) or exits (unrecoverable I/O). |
| `duration_ms` | int | build-* | Wall time of the compile. |
| `message` | string | watch-error | The `@errorName(err)` text. |
| `reason` | string | watch-stopped | `signal` (SIGINT/SIGTERM handler) today; future stop reasons add values. |

## Mapping to existing emission points

All events slot into code paths that already exist in `src/watch.zig` (no new
phases, no restructured control flow):

| Event | Existing site |
|-------|---------------|
| `hello` | Start of `WatchCoordinator.run`, before the initial build |
| `build-started` (initial) | `watch: performing initial build...` (~line 737) |
| `build-succeeded` (initial) | `watch: initial build succeeded (N pages written)` (~line 791); `pages_written` from `stats` |
| `watcher-started` | Immediately after initial build, before signal handlers / poll loop |
| `build-started` (rebuild) | `watch: triggering incremental rebuild...` (~line 663); `changed` = the sorted paths list |
| `build-succeeded` (rebuild) | `watch: rebuild succeeded.` (~line 729) |
| `build-failed` | All four `error: ... build failed:` sites (rebuild ~696/717, initial ~755/779); `recoverable` from `isRecoverableBuildError` |
| `watch-error` | `watch: poll error ({s}); retrying...` (~line 811) |
| `watch-stopped` | Shutdown line (~line 837) |

Because the compiler already prints structured diagnostic text lines to stderr
during watch compiles, the `build-failed` event's `diagnostics` array should
carry the same objects (the pipeline already holds them as structured data;
`--watch-json` should suppress the text form, not the data).

## Why this is a strong decision for boris

- It **completes the machine-contract story**: watch mode joins IR, analysis,
  and diagnostics as a typed, versioned, documented surface
  (`docs/contracts/watch-mode.md` already exists as the natural home).
- Purely additive and opt-in; without the flag, stderr and all artifacts are
  byte-identical to today. Human users lose nothing; tool users gain a
  contract.
- The event schema reuses existing shapes and constants (`compiler_id`,
  diagnostic objects, sorted content-relative paths) — nothing new is
  invented, only serialized.
- It follows the repo's own precedent: versioned contracts, deterministic
  field order via `json_out`, golden-tested output.

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
- CLI parse tests: `--watch-json` valid with `--watch`; usage error without.
- Golden assertion that non-`--watch-json` output is unchanged (existing
  tests already cover the prose path).

## Acceptance criteria

- [ ] `boris --html --watch --watch-json` emits the NDJSON stream above on
      stderr, nothing else, with `hello` first and `watch-stopped` last.
- [ ] `boris --watch --watch-json` without `--watch` exits 2.
- [ ] `build-failed` events carry diagnostics in the `build-report.json`
      shape; `recoverable` distinguishes loop-continuing failures.
- [ ] Existing watch behavior and artifacts unchanged without the flag.
- [ ] Event contract documented under `docs/contracts/watch-mode.md`.

## Non-goals

- No change to the human lines, exit codes, or any artifact format.
- No library/JSON-RPC mode (see A10) — this is a stream on stderr, not IPC.
