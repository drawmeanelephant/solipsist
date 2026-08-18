# Card M13-0 — Unknown mailbox is not Pages

**Milestone:** M13 · **Issue:**
[#144](https://github.com/drawmeanelephant/solipsist/issues/144)
(parent [#142](https://github.com/drawmeanelephant/solipsist/issues/142))
· **Lane:** Workspace. One worktree, one PR against `main`;
branch suggestion `feat/m13-unknown-mailbox`.

Prerequisite for M13-1. Without this, a persisted trunk id still
opens the full Pages list.

## Owns

- `Sources/Workspace/WorkspaceSelection.swift` —
  `WorkspaceMailbox.display` / the center-switch helper
- Tests that already compile this file (ContractTests). Do **not**
  add `WorkspaceStore.swift` to the test target
- Call sites that treat `display()` as “which play surface”:
  `Sources/Inspector/Inspectable.swift` if it switches on the
  coerced Pages token

## Do not touch

- `Sources/Chrome/SourceSidebar.swift` (M13-1)
- `Sources/Play/Local/` list filter (M13-2)
- `Sources/Engine/**`
- Settings / `Workspace/Git/` (M12)
- `Project.yml`

## Why

`WorkspaceMailbox.display` maps unknown → `pages` without writing
back. That was the M10 limit (D-S1). A trunk card must stop using
that helper for the center switch **before** it writes a trunk id.

`displayName` / `symbolName` already pass unknown through. Persist
already stores the raw string. Only the switch is wrong.

## Do

1. Stop using `display()` as “this is Pages.” Keep a known-token
   helper for the five M10 mailboxes. Unknown (including a future
   trunk id) stays itself.
2. Center / inspector switch: known five → existing surfaces;
   unknown → **not** the full Pages surface. A placeholder /
   empty “folder” state is fine until M13-2 lands the filter.
3. Persist-on-select must not run unknown through `display()`.
   `WorkspaceSelectionRules.restore` already keeps the raw string
   — do not regress that.
4. Tests: unknown raw displays verbatim (`displayName`);
   `display` / the new helper does not coerce `"index"` to
   `"pages"`; `isKnown("index")` is false.

## Do not

- Write trunk rows in the sidebar.
- Filter the letter list.
- Invent `WorkspaceMailbox.trunk` as a closed case.
- Canonicalize stored mailbox on load.

## Gate

A selection whose `mailbox` is `"index"` (or any string not in
`WorkspaceMailbox.all`) does **not** show the full Pages list.
Unknown displays as the raw string in the UI helper. Reloading
the store does not rewrite it to `pages`.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
