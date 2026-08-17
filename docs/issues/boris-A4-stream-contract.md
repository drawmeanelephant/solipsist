# A4 — Document stdout/stderr/exit behavior per mode

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Documentation only — no behavior change.

---

**Title:** Docs: specify stdout/stderr behavior for every mode (and fix the misleading `--report` help text)

## Summary

Boris keeps a deliberate stream discipline — **stdout is sacred, everything
human goes to stderr** — and it's a good one for a machine-consumed CLI. But
it is almost entirely undocumented, and one piece of help text actively
contradicts it:

| Stream | Today's actual content |
|--------|------------------------|
| **stderr** | All progress lines (`ok: wrote IR under …`, `boris: …`); all diagnostics (text form); `--help` text; `check`/`impact` analysis reports in `human`/`json` format; all watch-mode lines (`watch: …`, `error: rebuild failed: …`, changed-path listings) |
| **stdout** | Empty on every success path in every mode (deliberately reserved) |

Two concrete problems:

1. **The help text lies.** `--help` says
   `--report PATH  Write an analysis report instead of stdout` — but the
   default render target is **stderr**, not stdout. Any user reading the
   help will point `--report` at a file thinking they're redirecting what
   they already see, and will be confused about why stderr still shows the
   report. This is a factual bug in the tool's own documentation of its
   machine surface.
2. **The stream contract is unspecified.** `docs/contracts/diagnostics.md`
   has a two-row stub table; nothing states what goes where in each mode, or
   what the watch-mode stderr line grammar is. A consumer of `--watch` (a
   GUI, an editor plugin, a CI wrapper) cannot know that status lines,
   changed-path listings, and rebuild errors all arrive on stderr, or how to
   distinguish them.

## Proposal

1. **Fix the help text**: `--report PATH  Write the analysis report to PATH
   (default: stderr, human format)`.
2. **Extend `docs/contracts/diagnostics.md`** into a full per-mode table:
   default HTML, `--out`/IR, `--rag`, `--context`, `--llms`, `check` /
   `impact`, `--watch`, `package`, and `--help`. Columns: mode, stream,
   content, machine path.
3. **Document the watch-mode stderr line grammar** (the `watch:` / `error:`
   prefixes and the changed-path listing format) so tooling can parse it with
   confidence until structured events land (A1). Mark it explicitly as the
   stopgap contract.
4. **Optionally** add `--report -` as an explicit "stdout" target for
   symmetry with shell conventions — flag as open question; not required.
5. Note explicitly that `--help` on stderr is intentional (consistent with
   `std.debug.print` usage); changing it is out of scope for this issue.

`--quiet` interplay is already documented (diagnostics.md rule 7: suppresses
progress + diagnostic text on stderr; exit codes and artifacts unchanged) —
this issue extends, not rewrites, that contract.

## Why this is a strong decision for boris

Documentation of a discipline the tool already keeps. Making the stream
contract explicit — and fixing the one place it's mis-stated — turns an
implicit, empirically-discovered property into a promise any consumer can
rely on. *Changing* any stream would be a breaking change and is explicitly
out of scope; this is pure contract hygiene at zero behavior cost.

## Acceptance criteria

- [ ] `docs/contracts/diagnostics.md` contains a per-mode stream table
      covering every mode in `--help`.
- [ ] Watch-mode stderr line grammar documented as the stopgap contract.
- [ ] `--report` help text no longer claims stdout.
