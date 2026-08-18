# Card M13-2 — Filter letters by trunk mailbox

**Milestone:** M13 · **Issue:**
[#146](https://github.com/drawmeanelephant/solipsist/issues/146)
(parent [#142](https://github.com/drawmeanelephant/solipsist/issues/142))
· **Lane:** Reading. One worktree, one PR against `main`;
branch suggestion `feat/m13-filter-letters`.

Merges **after** M13-1. Reads `mailbox`. Does not edit the sidebar.

## Owns

- `Sources/Play/Local/` — list contents for a trunk mailbox
- `LocalPlayGraph` filter helper if one does not exist yet

## Do not touch

- `SourceSidebar.swift` (M13-1)
- `Sources/Engine/**`
- `MainWindow.swift`
- Settings / `Workspace/Git/`

## Why

Selecting a trunk folder that still shows every page is a lie.
Pages means all. A trunk id means that parent and its satellites.

## Do

1. When `selection.mailbox` is `pages` (or nil treated as Pages),
   show the full `LocalPlayGraph.pages` list — today’s behavior.
2. When `mailbox` is a known M10 token (`outputs` / `publish` /
   `plan` / `activity`), do not change those surfaces.
3. When `mailbox` is anything else, treat it as a trunk id: show
   the trunk row plus descendants whose `parent` chain reaches
   that id. Empty folder → empty list, not a fall-through to all
   pages.
4. Selecting a row still writes `noun` the way Reading does today
   (`sourcePath` included).
5. Tests: a three-node fixture (trunk + child + unrelated trunk)
   filters to two rows; `pages` still returns three.

## Do not

- Rebuild the sidebar.
- Walk the disk.
- Fall back to the full list when the id is missing from the
  current graph — empty is honest; the graph reloaded.

## Gate

Select a dogfood trunk folder → the letter list is that trunk and
its satellites only. Select Pages → all 45. A stale trunk id
(graph no longer contains it) shows empty, not everything.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
