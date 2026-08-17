# A4 — Stream contract: fix the `--report` help text; document the stdout machine surfaces

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Documentation only — no behavior change.
> **Rebaselined against afterparty v0.8.1.** The per-mode stream tables are
> largely documented now (`docs/contracts/cli.md`, `watch-mode.md`); this is
> trimmed to the remaining factual/contract gaps.

---

**Title:** Docs: fix the misleading `--report` help text and specify the stdout machine surfaces

## Summary

Two concrete gaps remain in the stream contract after the afterparty docs
work:

1. **The help text still lies about `--report`.** `boris --help` says
   `--report PATH  Write an analysis report instead of stdout` — but the
   default render target for `check`/`impact` is **stderr**, not stdout
   (verified: the report prints to stderr with no `--report`; stdout stays
   empty). A user reading the help will point `--report` at a file thinking
   they are redirecting what they already see, and will be confused about
   why stderr still shows the report. This is a factual bug in the tool's
   own documentation of its machine surface, and it survived the afterparty
   CLI rewrite.
2. **stdout is now a real machine surface and it isn't specified.** The
   old contract was "stdout is empty on success paths." Afterparty broke
   that, deliberately and usefully: `--version` / `-V`, `--timings`,
   `plan`/`standard-site plan`/`records`/`verify`, and `nostr sign` all
   emit machine-readable documents on stdout. Nothing states the rule for
   when stdout carries payloads vs when it stays clean — a consumer cannot
   tell "stdout is empty because nothing was requested" from "stdout is
   empty because I forgot a flag."

## Proposal

1. **Fix the help text**: `--report PATH  Write the analysis report to PATH
   (default: stderr, human format; rejected on watch and non-HTML modes)`.
2. **Document the stdout contract** in `docs/contracts/cli.md`: the closed
   list of commands/flags that emit on stdout (`--version`, `--timings`,
   `plan`, `standard-site plan|records|verify`, `nostr plan|sign`), the
   format each emits, and the rule that *everything else* keeps stdout
   empty (progress/diagnostics/help stay on stderr, as today).
3. **Note the per-mode `--report` semantics** in one table: `check`/`impact`
   default to stderr; `build`/`validate --report PATH` write a file only
   (no stderr default); `watch` rejects `--report`.

## Why this is a strong decision for boris

Pure contract hygiene at zero behavior cost: one help-text bug fixed, one
new machine surface specified. Afterparty already moved stdout from "sacred
empty" to "machine payloads" — the docs should catch up with the
implementation, or the next CLI writer will assume stdout is still sacred
and break a consumer.

## Acceptance criteria

- [ ] `--help` no longer claims `--report` writes "instead of stdout".
- [ ] `docs/contracts/cli.md` lists the stdout-emitting commands/flags and
      the empty-stdout rule for everything else.
- [ ] Per-mode `--report` semantics documented in one table.
