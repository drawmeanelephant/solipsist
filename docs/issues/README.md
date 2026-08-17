# Boris Issue Batch — "Complete the Process ABI"

Ready-to-paste GitHub issues for the **boris** repo. Each one is framed to
stand on its own merits — the arguments below are the ones that survive if
you remove every mention of who filed them. The through-line: boris already
treats its CLI as a typed process contract (versioned JSON artifacts, stable
exit codes, sacred stdout, atomic publication). These issues close the
remaining holes in that contract.

## The pitch, in one paragraph

Boris is a compiler whose machine surface is unusually well-designed:
deterministic, versioned, atomic, documented. But a consumer that treats it
as a black-box process finds four gaps — it can't be asked its **version**
(A2), its long-running **watch mode speaks prose instead of events** (A1),
one-shot HTML builds leave **no parseable result record** (A6), and its
**containment/stream/cancellation semantics** are real but undocumented
(A7, A4, A12). None of these require behavior changes for human users; all
of them complete the story for machines. They are the difference between "a
great CLI with JSON outputs" and "a compiler with a process ABI."

## The issues

| # | Issue | What it completes | Size |
|---|-------|-------------------|------|
| [A1](boris-A1-watch-events.md) | `--watch-json`: NDJSON event stream for watch mode | The one surface that still emits human prose — typed lifecycle events + structured diagnostics, `hello`-handshake versioned | M |
| [A2](boris-A2-version-flag.md) | `--version` flag | Engine identity *before* running a build (identity currently lives only in artifacts) | XS |
| [A3](boris-A3-build-report-compiler.md) | `compiler` in `build-report.json` | Uniform artifact identity — the one machine file that omits it, on the one path (failure) where it matters most | XS |
| [A4](boris-A4-stream-contract.md) | Document stdout/stderr per mode + fix `--report` help | The stream discipline boris already keeps, made a contract; also fixes a factual help-text bug | XS |
| [A6](boris-A6-completion-signal.md) | `.boris-cache/manifest.json` as documented completion contract | Atomicity made observable for HTML builds — completion marker + fingerprint-diff change detection | S |
| [A7](boris-A7-workspace-rule.md) | Decide + document the containment boundary | Safety claim made coherent — HTML is cwd-confined, the other outputs aren't; pick the posture on purpose | XS |
| [A12](boris-A12-signal-contract.md) | Signal/cancellation contract for watch mode | "Can I kill it?" answered as a documented, test-pinned guarantee | XS |
| [A5](boris-A5-check-watch-rfc.md) | RFC: `check --watch` — live diagnostics as a daemon | The validate-only half of the compiler-daemon story: recompile in memory, emit events, never touch outputs | L (RFC) |

## Why each stands on its own

- **A2** is a universal expectation; every compiler answers `--version`.
- **A1** completes the machine-contract story at the one surface that lacks
  it, reusing existing shapes (`compiler_id`, diagnostic objects, sorted
  content-relative paths) and the existing `docs/contracts/watch-mode.md`.
- **A3/A6** restore uniform properties (identity, atomicity) that the rest
  of the artifact set already has — consistency arguments, not feature asks.
- **A4/A7/A12** convert empirically-true behavior into documented contracts;
  the only behavior change on the table is the deliberate A7 decision, which
  is explicitly the maintainers' call.

## Suggested filing order

1. **A2 + A4** — XS, universally agreeable, zero risk. Land these first as a
   good-faith "this batch is cheap" signal.
2. **A1** — the flagship; engage with the concrete schema in the body.
3. **A3 + A6 + A7 + A12** — the consistency + contract batch.

A5 is drafted as the RFC companion ([boris-A5-check-watch-rfc.md](boris-A5-check-watch-rfc.md))
and should be filed as a discussion *after* A1 lands — it consumes A1's event
protocol, and it's the one issue that changes what `--watch` can mean (it
redefines today's `check --watch` usage error into a defined mode).
A8/A9/A10 (init scaffold, exit-code granularity, library mode) are noted in
the source audit as either nice-to-have or explicitly not recommended.
