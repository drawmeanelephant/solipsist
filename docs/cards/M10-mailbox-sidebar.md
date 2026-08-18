# Card M10-2 — Mailbox sidebar

**Milestone:** M10 · **Issue:**
[#100](https://github.com/drawmeanelephant/solipsist/issues/100) ·
**Lane:** Mailboxes. One worktree, one PR against `main`; branch
suggestion `feat/m10-mailbox-sidebar`.

Design: [`docs/M10-DESIGN.md`](../M10-DESIGN.md). Nested `graph.parent`
trunks are **out of this card**. Do not edit `Project.yml`.

## Owns

- `Sources/Chrome/SourceSidebar.swift` (recut into an account +
  mailbox tree; do not add a second sidebar file)
- `Sources/Chrome/MainWindow.swift` — **sole M10 owner**: column
  width + Editor toolbar `.disabled(!store.selection.canEditPage)`
- `Sources/Workspace/WorkspaceSelection.swift` — `mailbox`,
  `WorkspaceMailbox`, `MailboxRowID`, `canEditPage`,
  `WorkspaceSelectionRules`, `WorkspaceNoun.sourcePath`
- `Sources/Workspace/WorkspaceStore.swift` — `select(mailbox:)`;
  persist-on-select if changed; changing source writes `pages`
- `Sources/Workspace/WorkspacePersistence.swift` —
  `mailbox: String? = nil` (raw string; do not canonicalize on load)
- Thin adapter in `Sources/Play/Local/LocalPlay.swift` so today's
  segmented tabs follow `selection.mailbox` (Reading will delete the
  tabs). **#101 must not start until this PR is on `main`.**
- `Tests/ContractTests/WorkspaceSelectionTests.swift` (new) + extend
  `WorkspacePersistenceTests.swift`. Do **not** add `WorkspaceStore`
  to ContractTests.

## Do not touch

- `Sources/App/Settings/` (M10-1)
- `Sources/App/Commands.swift` (#102)
- `Sources/Inspector/**`
- `Sources/Engine/**`
- `Sources/Companions/**`
- Play row rendering, preview, editor
- `Project.yml` / `scripts/embed-boris.sh`

## Why

Mail's left pane is folders, not a flat account list. Each source is
an account header. Under it: Pages, Outputs, Publish, Plan, Activity.
Selecting a mailbox is what the reading place will listen to.

This is **not** a Finder tree. Do **not** show nested Pages folders
in this card (later: `graph.parent` trunks only, never a disk walk).

## Do

1. Grow `WorkspaceSelection` with `mailbox: String? = nil`. Persist
   the **raw** string. M10 UI admits five tokens; unknown → Pages
   *display* without writing `pages` back (`WorkspaceMailbox.display`).
2. Sidebar `List` + `Section`, selection type `MailboxRowID`:
   - Header per source (title, stale badge, Relocate / Remove).
     Header tap is **best-effort** (macOS Section + gesture is
     flaky); the Pages row is the accessible control.
   - Child rows: Pages, Outputs, Publish, Plan, Activity.
   - Selecting a header (if it registers) selects that source + `pages`.
   - Selecting a child writes `sourceID` + `mailbox` and clears
     `noun` when the mailbox changes.
3. Keep the plus button as a shortcut to `presentOpenPanel()`.
4. Point `LocalPlay`'s segmented control at `selection.mailbox`.
   Do not redesign the center list.
5. Empty workspace: keep the No Sources empty state.
6. `MainWindow`: wider sidebar column; Editor toolbar uses
   `canEditPage`. Do not add views.

## Do not

- Walk `content/` as folders.
- Show `.boris/`, `themes/`, or `dist/` as mailboxes.
- Delete the play tabs (M10-3).
- Add GitHub-specific rows.

## Gate

Open `Stunts/happy`. Sidebar shows the folder as an account with
five mailboxes. Clicking the **Pages** child (and the header if the
tap registers) selects Pages. Clicking Outputs / Publish / Plan /
Activity changes the play tab (via `mailbox`). Changing source
resets to Pages and clears the page noun. Restart restores the
mailbox string. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
