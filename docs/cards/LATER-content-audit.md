# Card LATER-1 — Content-audit mailbox

**Issue:** [#165](https://github.com/drawmeanelephant/solipsist/issues/165)
· **Lane:** workspace / mailbox. One worktree, one PR against `main`;
branch suggestion `mailbox/content-audit`.

## Owns

- `Sources/Workspace/**` — the `WorkspaceMailbox` token (`content-audit`)
  and selection wiring
- `Sources/Chrome/SourceSidebar.swift` — the new mailbox row
- The center pane (alongside Plan / Outputs / Activity) that runs the audit
- Binary locate/embed for `boris-content-audit` — a **separate kit
  binary**, not the embedded `boris`

## Do

1. **Probe first — already done.** The probed contract is recorded in
   `docs/ENGINE-CONTRACTS.md` §8 (PR #168); the short version is on
   [#165](https://github.com/drawmeanelephant/solipsist/issues/165#issuecomment-5341401505):
   flags, verified exit codes 0/1/2/3/4, `report.json` shape,
   `missing_id` → structural semantics, and the `--out`-must-be-real-path
   gotcha.
2. Add the `content-audit` mailbox token (displayName, symbolName, `all`)
   and a sidebar row.
3. Add the center pane: run the audit against the selected source's
   workspace root, render `exceptions[]`, never swallow diagnostics or
   non-zero exit codes (D11).
4. Run it through the coordinator's single `Process?` slot — no second
   subprocess.

## Do not

- Reimplement audit semantics in Swift (D11) — run the binary.
- Touch `Sources/Engine/**` beyond an additive, single-owner change
  (future lanes #160/#161 own the boundary).
- Mutate the content tree — read-only mailbox.
- Grow `Sources/Chrome/MainWindow.swift`.

## Gate

Open a source → select the content-audit mailbox → findings render;
non-zero exit surfaces in the problems/status UI. `SKIP_EMBED_BORIS=1
make build` + `make test` green.
