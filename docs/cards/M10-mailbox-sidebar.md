# Card M10-2 — Mailbox sidebar

**Milestone:** M10 · **Issue:**
[#100](https://github.com/drawmeanelephant/solipsist/issues/100) ·
**Lane:** Mailboxes. One worktree, one PR against `main`; branch
suggestion `feat/m10-mailbox-sidebar`.

## Owns

- `Sources/Chrome/SourceSidebar.swift` (recut into an account +
  mailbox tree; do not add a second sidebar file unless the current
  one cannot hold it)
- `Sources/Workspace/WorkspaceSelection.swift` — add `mailbox`
- `Sources/Workspace/WorkspaceStore.swift` — select mailbox; changing
  source picks that source's default mailbox (`pages`)
- Thin adapter in `Sources/Play/Local/LocalPlay.swift` so today's
  segmented tabs follow `selection.mailbox` (Reading will delete the
  tabs)

## Do not touch

- `Sources/App/Settings/` (M10-1)
- `Sources/Inspector/**`
- `Sources/Engine/**`
- `Sources/Companions/**`
- `Sources/Chrome/MainWindow.swift` beyond a title / column-width
  tweak if the sidebar needs it
- Play row rendering, preview, editor

## Why

Mail's left pane is folders, not a flat account list. Each source is
an account header. Under it: Pages, Outputs, Publish, Plan, Activity.
Selecting a mailbox is what the reading place will listen to.

This is **not** a Finder tree. Nested folders under Pages, if you
show any, come from `graph.json` `parent` (trunks as folders). Do not
walk the content directory.

## Do

1. Grow `WorkspaceSelection` with `mailbox: String?` (open string,
   same style as `noun.kind`). Default `pages`.
2. Sidebar `List`:
   - Section / header per source (title, stale badge, existing
     Relocate / Remove context menu).
   - Child rows: Pages, Outputs, Publish, Plan, Activity.
   - Selecting a header selects that source + `pages`.
   - Selecting a child writes `sourceID` + `mailbox` and clears
     `noun` when the mailbox changes.
3. Keep the plus button as a shortcut to `presentOpenPanel()`.
4. Point `LocalPlay`'s segmented control at `selection.mailbox` so
   the app does not go dark if M10-3 has not landed. Do not redesign
   the center list in this card.
5. Empty workspace: keep the No Sources empty state.

## Do not

- Walk `content/` as folders.
- Show `.boris/`, `themes/`, or `dist/` as mailboxes.
- Delete the play tabs (M10-3).
- Add GitHub-specific rows.

## Gate

Open `Stunts/happy`. Sidebar shows the folder as an account with
five mailboxes. Clicking Outputs / Publish / Plan / Activity changes
the play tab (via `mailbox`). Changing source resets to Pages and
clears the page noun. `SKIP_EMBED_BORIS=1 make build` + `make test`
green.
