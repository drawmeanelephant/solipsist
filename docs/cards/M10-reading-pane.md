# Card M10-3 — Reading pane

**Milestone:** M10 · **Issue:**
[#101](https://github.com/drawmeanelephant/solipsist/issues/101) ·
**Lane:** Reading. One worktree, one PR against `main`; branch
suggestion `feat/m10-reading-pane`.

Depends on [#100](https://github.com/drawmeanelephant/solipsist/issues/100)
(`selection.mailbox` exists).

## Owns

- `Sources/Play/Local/` — `LocalPlay.swift` and the pane files it
  already hosts. Tabs go away. Center becomes mailbox contents + a
  reading pane for a selected page.
- Shared preview URL loading **inside Play only** (reuse
  `PreviewURL` / the existing `PreviewSession` if it is already up;
  do not spawn a second watch)

## Do not touch

- `Sources/Chrome/SourceSidebar.swift` / `WorkspaceSelection` shape
  (M10-2)
- `Sources/Engine/**` (no new `Process`)
- `Sources/Companions/Preview/` beyond calling into the existing
  session
- `Sources/Inspector/**`
- Native text editing (M10-4 / Later)

## Why

Mail's middle is messages, then the letter. Play is currently five
tabs and a problems strip. After M10-2 the tabs are just a view of
`mailbox`. This card makes the center a message list plus a reading
pane, and leaves Outputs / Publish / Plan / Activity as the body of
those mailboxes — not as a segmented control on top of Pages.

## Do

1. Remove the segmented `PlayTab` picker. Switch on
   `store.selection.mailbox`.
2. **Pages mailbox:** keep the existing graph list (filter, badges,
   indent). Under it or beside it, a reading pane for the selected
   page:
   - If preview watch is up, load that page's served URL in a
     `WKWebView` (path from `sourcePath` / already-decoded graph —
     do not invent a permalink). Reuse the existing watch; do not
     start a second one.
   - If watch is down: contract-backed summary (title, id, status,
     `sourcePath`, relations from `completion.json` if the inspector
     already decoded them) + Preview / Edit buttons that open the
     existing companions.
3. **Other mailboxes:** the existing Outputs / Publish / Plan /
   Activity panes, full-height, no fake message list.
4. Problems strip stays under the reading place (it is the diagnostic
   mailbox-adjacent surface we already have).
5. Empty / failed / unavailable states stay
   `ContentUnavailableView`. No monospaced dump.

## Do not

- `file://` the built HTML.
- Write a Markdown renderer or frontmatter parser.
- Spawn `Process`. Only `BorisEngine` / the existing
  `PreviewSession`.
- Grow `MainWindow`.
- Walk the disk for the list — `graph.json` is the structure.

## Gate

Open `Stunts/happy`, select Pages, click a page → reading pane shows
the summary (and the served page if Preview is already running).
Select Outputs → the outputs pane, no tab bar. No `file://`. No
Swift Markdown. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
