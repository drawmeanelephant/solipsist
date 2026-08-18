# Card M10-3 — Reading pane

**Milestone:** M10 · **Issue:**
[#101](https://github.com/drawmeanelephant/solipsist/issues/101) ·
**Lane:** Reading. One worktree, one PR against `main`; branch
suggestion `feat/m10-reading-pane`.

Depends on [#100](https://github.com/drawmeanelephant/solipsist/issues/100)
on `main` (`selection.mailbox` exists). **#102 merges after this
card.** Design: [`docs/M10-DESIGN.md`](../M10-DESIGN.md).

## Owns

- `Sources/Play/Local/` — `LocalPlay.swift` and the pane files it
  already hosts. Tabs go away. Center becomes mailbox contents + a
  reading pane. Double-click / Return / summary Edit →
  `openWindow(id: CompanionID.editor)`. Problems jump writes mailbox
  `pages` **and** `noun.sourcePath`. Graph reload rewrites the noun
  (or clears it).
- `Sources/Play/Local/ReadingPane.swift` / `ReadingWebView.swift` (new)
- Named recut — session sharing **without** a second watch:
  - `Sources/App/AppRuntime.swift` — `let previewSession = PreviewSession()`
  - `Sources/Chrome/PlayHost.swift` — bind session to
    `store.selection.sourceID` even when the companion is closed
    (retarget if serving; stop if no source; **do not auto-start**
    from idle)
  - `Sources/Companions/Preview/PreviewSession.swift` — expose
    `boundRootPath` / `isBound(to:)`
  - `Sources/Companions/Preview/PreviewWindow.swift` — use
    `runtime.previewSession`; drop `onDisappear { session.stop() }`
  - `Sources/Companions/Preview/PreviewURL.swift` — `siteOrigin` /
    `pageURL(helper:pageID:)` using **`GraphNode.id`**, not swapped
    `sourcePath`

## Do not touch

- `Sources/Chrome/SourceSidebar.swift` / `WorkspaceSelection` shape
  (M10-2)
- `Sources/Chrome/MainWindow.swift` (#100)
- `Sources/Engine/**` (no new `Process`; do not change `WatchServer` argv)
- `Sources/Inspector/**`
- A second `PreviewSession`
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
   - If preview watch is up **and** `previewSession.isBound` to this
     source, load `PreviewURL.pageURL(helper:pageID:)` in a
     `WKWebView` (`pageID` is `GraphNode.id` / `PlayPage.id` — **not**
     `sourcePath` with the extension swapped). Do not invent a
     permalink. Reuse the existing session; do not start a second
     watch. Foreign-root `phase == .serving` is idle (summary).
     `WKNavigationDelegate` detects 404 / load failure → in-pane
     summary. Retry on `serveURL` change or row re-select, not SSE.
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
the summary (and the served page if Preview is already running **for
this source**). Switch source with Preview closed while watch was
up → letter is this source or summary, never the previous folder.
Select Outputs → the outputs pane, no tab bar. No `file://`. No
Swift Markdown. If a cook / id≠stem corpus is available, confirm
`GET /{id}.html` vs stem. `SKIP_EMBED_BORIS=1 make build` +
`make test` green.
