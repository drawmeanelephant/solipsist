# Boris Issue Batch — "Complete the Process ABI"

Ready-to-paste GitHub issues for the **boris** repo, **re-baselined against
the afterparty line (v0.8.1 candidate)**. Each issue is framed to stand on
its own merits — the arguments survive if you remove every mention of who
filed them. Afterparty already closed several gaps from the earlier draft
batch (A2 `--version`, A8 `init`, A9 `--fail-on-unreferenced`, most of A6,
most of A7); the issues below are the ones that remain genuinely open.

## The pitch, in one paragraph

Boris is a compiler whose machine surface is unusually well-designed:
deterministic, versioned, atomic, documented — and afterparty keeps closing
the remaining holes itself. The genuinely open gaps for a black-box
consumer: watch mode still speaks prose instead of typed events (A1, with
`--serve`'s SSE channel as the browser sibling), the IR `build-report.json`
still omits its compiler id while every other artifact carries it under
three different field names (A3), the `--report` help text still misleads
and the new stdout machine surfaces are unspecified (A4), and the
signal/cancellation contract isn't written down or test-pinned (A12). The
smaller asks: document the incremental changed-page contract (A6) and the
now-uniform containment rule (A7). The RFC: join `validate` + `watch` into
a live, artifact-free diagnostics daemon (A5).

## The issues (final afterparty status)

| # | Issue | Status | What it completes |
|---|-------|--------|-------------------|
| [A1](boris-A1-watch-events.md) | `--watch-json`: NDJSON event stream for watch mode | ✅ ready | Typed lifecycle + diagnostic events for subprocess consumers; `mode` field future-proofs A5; compatible with `--serve` |
| [A2](boris-A2-version-flag.md) | ~~`--version` flag~~ | ⛔ withdrawn | Shipped on afterparty (`boris/0.8.1`, exit 0, test-pinned) — file holds the evidence |
| [A3](boris-A3-build-report-compiler.md) | Compiler identity in IR `build-report.json` + the field-name zoo | ✅ ready | The one mute artifact; `compiler` / `compiler_id` / `compilerId` triplicate |
| [A4](boris-A4-stream-contract.md) | Fix `--report` help text; document stdout machine surfaces | ✅ ready | Factual help-text bug + the stdout-payload rule (`--version`, `--timings`, plans) |
| [A6](boris-A6-completion-signal.md) | Document `.boris-cache/manifest.json` changed-page contract | ✅ ready (P2, honest won't-do option) | Fingerprint-diff change attribution for incremental consumers |
| [A7](boris-A7-workspace-rule.md) | Document containment rule + IR absolute-path quirk | ✅ ready | Uniform containment made a specified contract; one clarifying question |
| [A12](boris-A12-signal-contract.md) | Signal/cancellation contract for watch mode | ✅ ready | Graceful SIGTERM/SIGINT + SIGKILL atomicity, doc + latch test |
| [A5](boris-A5-check-watch-rfc.md) | RFC: `validate --watch` — live diagnostics daemon | ✅ ready (RFC) | Join the artifact-free preflight with the watch daemon, A1 events |

## Suggested filing order

1. **A3** — XS, the sharpest consistency gap (single build, four artifacts
   carry identity, one doesn't; three different field names).
2. **A4** — XS; a factual bug in the tool's own help text.
3. **A1** — the flagship; concrete schema in the body, cites `--serve`.
4. **A12** — XS docs + one test.
5. **A6, A7** — small docs asks (A6 carries an honest won't-do option).
6. **A5** — the RFC, as a discussion after A1 lands.

A10 (library mode) stays not-recommended; the Wasm `compileBundle` ABI is
the embed path boris itself chose, and subprocess isolation remains right
for a Mac app.
