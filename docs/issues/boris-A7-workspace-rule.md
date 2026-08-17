# A7 — Document the workspace-containment rule (and its asymmetry)

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Documentation + a design question — no behavior change.

---

**Title:** Docs: specify the workspace-containment rule — HTML targets only, and why

## Summary

Which outputs Boris confines to the workspace is currently undocumented and —
after verification — **asymmetric**. HTML output targets are strictly
contained to the process working directory; the IR / RAG / context / analysis
outputs are not. We hit the HTML wall the hard way (pointing `--html-dir` at
a temp folder fails), then discovered the others write anywhere. The rule
deserves to be stated precisely, and the asymmetry deserves an explicit
decision rather than being incidental.

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
  process cwd — an app running boris with `cwd = project folder` confines all
  HTML output to the project folder automatically.

## Proposal

1. **Document the de-facto rule.** Add a short section to the CLI docs (and a
   pointer from `docs/contracts/diagnostics.md`, which owns the exit-code
   contract) stating: workspace = cwd; the boundary check semantics; the two
   HTML errors; exit 2 mapping; and the per-flag table above including the
   explicitly-open outputs (`--out`, `--rag-dir`, `--context-dir`,
   `--report`, `--llms-path`'s "invalid value" rule).
2. **Decide the asymmetry explicitly** — two options, pick one:
   - **(a) Document as-is (recommended).** HTML outputs are hardened because
     they're deployable artifacts that clobber a tree; IR/RAG/context/report
     are data products where writing elsewhere (e.g. `--report /tmp/x`, an
     IR dump into a scratch dir) is legitimate. Containment stays
     HTML-specific; docs state this is intentional.
   - **(b) Extend containment to all outputs.** More consistent
     defense-in-depth, but a behavior change: today IR/RAG/context/report
     legitimately write outside cwd, and users may rely on it. This deserves
     its own RFC if pursued.

## Why this is not a compromise

Documentation only. No behavior changes without an explicit maintainer
decision; if (b) is chosen, that ships as a separate, additive-contract
change with its own issue.

## Acceptance criteria

- [ ] CLI docs state the workspace rule (cwd boundary, both HTML errors,
      exit 2) and the per-flag table, including which outputs are open.
- [ ] The asymmetry is resolved with an explicit recorded decision
      (document-as-is vs extend), not left incidental.
