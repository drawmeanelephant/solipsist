# A7 — Document the workspace-containment rule (uniform now) + the IR absolute-path rule

> **Filed:** [boris#646](https://github.com/drawmeanelephant/boris/issues/646).
> **Fixed by:** [boris#648](https://github.com/drawmeanelephant/boris/pull/648) (merged into `afterparty` 2026-08-17).
> Priority: P1. Size: XS. Documentation + one clarifying question.
> **Rebaselined against afterparty v0.8.1.** The asymmetry that motivated
> this issue is **resolved**: all output trees are now cwd-contained
> (verified). What remains is documenting the rule precisely — including one
> surprising quirk.

---

**Title:** Docs: specify the workspace-containment rule, including the IR absolute-output-path rejection

## Summary

Boris's containment posture is now coherent: **all output trees — HTML, IR,
RAG, context — are confined to the process working directory**, and
violations fail with `WorkspaceEscape` (exit 2). That is a strong safety
property (a misconfigured build can never clobber an arbitrary tree), and
the root-prefix fix (cwd = `/`) keeps it sound for container runtimes. But
the rule is still undocumented, and empirical probing surfaced two
consumer-facing specifics that deserve to be *specified*, not discovered:

## Verified behavior (afterparty, v0.8.1)

| Case | Result |
|------|--------|
| `--html-dir`, `--target`, `--out`, `--rag-dir`, `--context-dir` pointing outside cwd | `WorkspaceEscape`, exit 2 |
| Relative output paths (`--out ir`, `--out ./ir`, `--out ../x/ir` inside cwd) | ✅ work |
| **IR `--out /abs/path` even *inside* cwd** | ❌ `WorkspaceEscape` (exit 2) |
| HTML `--html-dir /abs/path` inside cwd | ✅ works |
| `check`/`build`/`validate --report /abs/path` (single file) | ✅ works |
| `--input /abs/path` (content root) | ✅ works — input is not constrained |

The interesting item: **IR mode rejects absolute output paths even when they
resolve inside the workspace**, while HTML mode accepts them. That looks like
the direct-IR export-safety policy (rejecting absolute/nested-under-content/
symlink outputs) being stricter than HTML's — and it is exactly the kind of
asymmetric rule a consumer will hit on the first IR build that isn't
cwd-relative.

## Proposal

1. **Document the rule** in `docs/contracts/cli.md` (and/or
   `multi-target-isolated-output.md`): workspace = process cwd; the
   path-boundary check; `TargetOutputCollision` for the root itself; the
   per-flag table above (output trees contained, `--report` single files
   free, `--input` unconstrained); exit-2 mapping.
2. **Decide + specify the IR absolute-path rule**: is rejecting
   `--out /abs/path-inside-cwd` intended policy (deterministic
   workspace-relative outputs for IR) or an artifact of the resolve logic?
   If intended, say so in one sentence and pin it with a test; if not, it
   should work like HTML's does. Either way, consumers need it written down
   — "relative paths work everywhere; absolute paths work in HTML but not
   IR" is exactly the kind of asymmetry that generates bug reports.

## Why this is a strong decision for boris

Containment is a safety *claim*, and claims are only as good as their
documentation and their test pins. The posture is already uniform; this
issue makes the boundary — including the IR quirk — a specified, tested
contract instead of an empirical discovery. Docs only; no behavior change
unless the IR absolute-path rule is deemed a bug (then the fix is
one-line).

## Acceptance criteria

- [ ] CLI docs state the containment rule and the per-flag table above.
- [ ] The IR absolute-output-path behavior is either documented as intended
      (with a test pin) or fixed to match HTML.
