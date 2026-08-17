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
still omits its compiler id while other artifacts carry it under three
different field names (A3), the `--report` help text still misleads and the
new stdout machine surfaces are unspecified (A4), and the now-uniform
containment rule needs one documenting pass (A7). Probing the binary also
surfaced a real watch defect: graph-validation failures kill the watcher
(A13). The RFC: join `validate` + `watch` into a live, artifact-free
diagnostics daemon (A5). A6 (completion signal) and A12 (signal contract)
are moot — afterparty solved them (`build --report`; watch-mode.md §6).

## The issues (final afterparty status)

| # | Issue | Status | What it completes |
|---|-------|--------|-------------------|
| [A1](boris-A1-watch-events.md) | `--watch-json`: NDJSON event stream for watch mode | ✅ ready | Typed lifecycle + diagnostic events for subprocess consumers; `mode` field future-proofs A5; compatible with `--serve` |
| [A2](boris-A2-version-flag.md) | ~~`--version` flag~~ | ⛔ withdrawn | Shipped on afterparty (`boris/0.8.1`, exit 0, test-pinned) — file holds the evidence |
| [A3](boris-A3-build-report-compiler.md) | Compiler identity in IR `build-report.json` + the field-name zoo | ✅ filed [boris#638](https://github.com/drawmeanelephant/boris/issues/638) | The one mute artifact; `compiler` / `compiler_id` / `compilerId` triplicate |
| [A4](boris-A4-stream-contract.md) | Fix `--report` help text; document stdout machine surfaces | ✅ filed [boris#639](https://github.com/drawmeanelephant/boris/issues/639) | Factual help-text bug + the stdout-payload rule (`--version`, `--timings`, plans) |
| [A6](boris-A6-completion-signal.md) | ~~completion signal~~ | ⛔ moot | Original ask solved by `build --report` (`html-build-report-0.1.0`); the cache-manifest doc idea is P2 nice-to-have, retained as evidence only |
| [A7](boris-A7-workspace-rule.md) | Document containment rule + IR absolute-path quirk | ✅ ready | Uniform containment made a specified contract; one clarifying question |
| [A12](boris-A12-signal-contract.md) | ~~signal/cancellation contract~~ | ⛔ moot | watch-mode.md §6 documents SIGINT/SIGTERM + finish-rebuild + staged-publish atomicity; C06 pins exit classes; a shutdown-latch test is nice-to-have |
| [A13](boris-A13-watch-graph-failure-recovery.md) | watch: graph-validation failures kill the watcher | ✅ filed [boris#640](https://github.com/drawmeanelephant/boris/issues/640) | Bug: `GraphValidationFailed` exits the watcher; should recover like `ParseFailed` |
| [A5](boris-A5-check-watch-rfc.md) | RFC: `validate --watch` — live diagnostics daemon | ✅ ready (RFC) | Join the artifact-free preflight with the watch daemon, A1 events |

## Suggested filing order

Already filed: **A3** [boris#638], **A4** [boris#639], **A13** [boris#640].

Remaining, in order:

1. **A1** — the flagship; concrete schema in the body, cites `--serve`.
2. **A7** — small docs ask (containment rule + IR absolute-path quirk).
3. **A5** — the RFC, as a discussion after A1 lands.

Moot / withdrawn (no action): **A2** (`--version` shipped), **A6**
(`build --report` solved the completion signal), **A12** (watch-mode.md §6
already documents signals; C06 pins exit classes). The draft files retain
the evidence.

A10 (library mode) stays not-recommended; the Wasm `compileBundle` ABI is
the embed path boris itself chose, and subprocess isolation remains right
for a Mac app.
