# Boris Issue Batch — "Complete the Process ABI"

Ready-to-paste GitHub issues for the **boris** repo. Each one is framed to
stand on its own merits — the arguments below are the ones that survive if
you remove every mention of who filed them. The through-line: boris already
treats its CLI as a typed process contract (versioned JSON artifacts, stable
exit codes, sacred stdout, atomic publication). These issues close the
remaining holes in that contract.

> ⚠️ **Reconciliation required before filing.** This batch was drafted
> against boris `main` v0.8.0. We now harness **`afterparty` v0.8.1
> candidate** — and afterparty already ships several of these. The status
> column below is fact-checked against the afterparty binary; **do not file
> anything marked ✅ without first updating its draft.**

## The pitch, in one paragraph

Boris is a compiler whose machine surface is unusually well-designed:
deterministic, versioned, atomic, documented. Afterparty already answers the
version query (`--version`), gives HTML a machine result artifact
(`build --report`), contains all output trees, and makes `check` findings
non-failing by default. The genuinely open gaps for a black-box consumer:
watch mode still speaks prose instead of typed events (A1), the IR
`build-report.json` still omits its compiler id while the HTML report has it
(A3), the stream/`--report` help text still misleads (A4), and the
signal/cancellation contract isn't written down (A12). Those are the issues
worth filing.

## The issues (with afterparty status)

| # | Issue | Status on afterparty | What it completes |
|---|-------|----------------------|-------------------|
| [A1](boris-A1-watch-events.md) | `--watch-json`: NDJSON event stream for watch mode | 🟡 **OPEN — reframe, cite `--serve`** | Watch has an SSE reload channel for browsers; subprocess consumers still get prose. Typed lifecycle + diagnostic events remain the one missing surface |
| [A2](boris-A2-version-flag.md) | `--version` flag | ✅ **DONE — withdraw** | `boris/0.8.1`, exit 0, test-pinned |
| [A3](boris-A3-build-report-compiler.md) | `compiler` in IR `build-report.json` | 🟡 **OPEN — reframe as report parity** | `html-build-report-0.1.0` has `compilerId`; IR `build-report.json` doesn't. The inconsistency is sharper than on main |
| [A4](boris-A4-stream-contract.md) | Document stdout/stderr per mode + fix `--report` help | 🟡 **PARTIAL — trim to the remaining gaps** | Help still says `--report … instead of stdout`; `--timings` (new stdout surface) needs documenting |
| [A6](boris-A6-completion-signal.md) | `.boris-cache/manifest.json` as documented completion contract | 🟡 **MOSTLY DONE — demote** | `build --report` gives HTML a machine result artifact on success *and* failure; the manifest-as-contract ask is now low priority |
| [A7](boris-A7-workspace-rule.md) | Decide + document the containment boundary | 🟡 **MOSTLY DONE — reduce to docs** | All output trees are now cwd-contained (HTML/IR/RAG/context verified); the asymmetry is resolved, only the docs ask remains |
| [A12](boris-A12-signal-contract.md) | Signal/cancellation contract for watch mode | 🟡 **PARTIAL — trim** | C06 conformance pins watch exit classes; explicit signal docs + latch test still open |
| [A5](boris-A5-check-watch-rfc.md) | RFC: `validate --watch` — live diagnostics as a daemon | 🔵 **REFORMULATE** | `boris validate` (artifact-free preflight + in-memory link audit) now exists — the RFC becomes "join validate + watch", far more tractable |
| ~~A8~~ `init` | — | ✅ **DONE — never file** | `boris init [DIR]` ships |
| ~~A9~~ check exit | — | ✅ **DONE — never file** | `--fail-on-unreferenced` opt-in; findings don't fail by default |

## Suggested filing order (after re-baselining)

1. **A3** — XS, the sharpest consistency gap (HTML report has `compilerId`,
   IR report doesn't). Cheapest good-faith win.
2. **A4** — XS; the `--report` help-text bug is a factual error in the
   tool's own docs.
3. **A1** — the flagship; engage with the concrete schema in the body, now
   citing `watch --serve`'s SSE channel as the browser side.
4. **A12** — XS docs + one test.
5. **A5** — the RFC, as a discussion after A1 lands (`validate --watch`).

A10 (library mode) stays not-recommended; the Wasm `compileBundle` ABI is
the embed path boris itself chose, and subprocess isolation remains right
for a Mac app.
