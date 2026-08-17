# A7 — The workspace-containment rule (and its asymmetry)

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Documentation + one architectural decision.

---

**Title:** Decide + document the workspace-containment boundary — HTML targets only, and why

## Summary

Boris has a security posture most compilers don't: **HTML output targets are
strictly confined to the process working directory.** Point `--html-dir` at a
folder outside the workspace and the build refuses (exit 2). That's a
genuinely valuable safety property — a misconfigured build can never clobber
an arbitrary directory tree. But the containment is **asymmetric**: the IR,
RAG, context, and analysis outputs write anywhere. That asymmetry is
currently undocumented and looks incidental rather than deliberate. A
consumer (or a maintainer auditing the tool's safety claims) cannot tell
from any doc whether "outputs are contained" is a promise of boris or a
property of one flag class.

## Verified boundary map (boris 0.8.0, workspace = cwd)

| Flag | Outside-workspace target | Result |
|------|--------------------------|--------|
| `--html-dir /tmp/x` | ✅ attempted | exit 2, `error: invalid target configuration: WorkspaceEscape` |
| `--target site=/tmp/x` | ✅ attempted | exit 2, same |
| `--llms-path /tmp/x` | ✅ attempted | exit 2, `error: invalid value for --llms` |
| `--out /tmp/x` (IR) | ✅ attempted | **exit 0 — writes outside the workspace** |
| `--rag-dir /tmp/x` | ✅ attempted | **exit 0 — writes outside** |
| `--context-dir /tmp/x` | ✅ attempted | **exit 0 — writes outside** |
| `check --report /tmp/x` | ✅ attempted | **exit 0 — writes outside** |

## The exact HTML rule (from `src/target.zig`)

- **Workspace root = the process cwd** (`Io.Dir.cwd()`), not the content root
  and not any config file location. `--input content` is resolved relative to
  cwd; HTML outputs must be descendants of cwd.
- Membership is a **path-boundary** check (`hasAbsPathPrefix`): the resolved
  output must be under cwd, and sibling prefixes are rejected (`/ws` vs
  `/ws-evil`).
- Targeting the workspace root itself is a distinct error
  (`TargetOutputCollision`), not `WorkspaceEscape`.
- Both map to **exit 2** (usage; see `mapHtmlError` in `src/main.zig`).
- A consumer therefore defines the containment boundary by choosing the
  process cwd — which is a clean, composable property: any wrapper decides
  its own sandbox by where it launches boris.

## Proposal

1. **Document the de-facto rule.** Add a short section to the CLI docs (and a
   pointer from `docs/contracts/diagnostics.md`, which owns the exit-code
   contract) stating: workspace = cwd; the boundary check semantics; the two
   HTML errors; exit 2 mapping; and the per-flag table above including the
   explicitly-open outputs (`--out`, `--rag-dir`, `--context-dir`,
   `--report`, `--llms-path`'s "invalid value" rule).
2. **Resolve the asymmetry with an explicit decision** — two options:
   - **(a) Document as-is (recommended).** HTML outputs are hardened because
     they are deployable artifacts that clobber a tree; IR/RAG/context/report
     are data products where writing elsewhere (e.g. `--report /tmp/x`, an
     IR dump into a scratch dir) is legitimate. Containment stays
     HTML-specific; docs state this is intentional.
   - **(b) Extend containment to all outputs.** More consistent
     defense-in-depth — a single "all outputs live under cwd" invariant. But
     it is a behavior change: today IR/RAG/context/report legitimately write
     outside cwd, and users may rely on it. If pursued, it deserves its own
     RFC; the decision here is which way the tool's promise goes.

## Why this is a strong decision for boris

Containment is a safety *claim*, and safety claims that are half-true are
worse than none — they train consumers to test empirically instead of
trusting the contract. Naming the boundary (option a) or extending it
(option b) turns an accident of implementation into a deliberate,
documented posture that every future consumer can rely on. Either way, the
tool's security story becomes coherent rather than asymmetric-by-omission.

## Acceptance criteria

- [ ] CLI docs state the workspace rule (cwd boundary, both HTML errors,
      exit 2) and the per-flag table, including which outputs are open.
- [ ] The asymmetry is resolved with an explicit recorded decision
      (document-as-is vs extend), not left incidental.
