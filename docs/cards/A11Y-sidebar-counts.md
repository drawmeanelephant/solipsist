# Card A11Y-5 — Mailbox sidebar counts

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#243](https://github.com/drawmeanelephant/solipsist/issues/243)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Mailboxes. One worktree, one PR against `main`; branch
suggestion `feat/a11y-sidebar-counts`.

Spec: [`docs/issues/editor-accessibility-sidebar-counts.md`](../issues/editor-accessibility-sidebar-counts.md).

**Status: ✅ merged (PR #244).** Kept as the record; do not reopen.

## Owns

- `Sources/Chrome/SourceSidebar.swift` — `accessibilityValue` counts on the
  Pages and trunk rows

## Do not touch

- `Sources/Compose/` (A11Y-1)
- `Sources/Play/Local/` (A11Y-2)
- `Sources/Companions/` (A11Y-3 / A11Y-4)
- `Sources/Engine/**`
- `Project.yml`

## Why

VoiceOver announces mailbox row titles but not item counts, so users cannot
tell how many pages sit under Pages or a trunk folder. **No new plumbing is
needed**: `LocalPlay.apply` already calls `store.updateGraph(graph, for:
source.id)`, and `PagesGroup` already reads the graph via `store.graph(for:)`
+ `LocalPlayGraph.trunks(from:)`. `LocalPlayGraph.pages(in:trunkID:)` already
counts a trunk's pages.

## Do

1. Pages row: `.accessibilityValue("\(pageCount) items")` — page count from
   `store.graph(for:)` (all pages in the graph).
2. Each trunk row: `.accessibilityValue("\(count) items")` — per-trunk count
   via `LocalPlayGraph.pages(in: trunkID:)`.
3. Counts recompute when the graph rebuilds (they derive from the stored
   graph — verify on `updateGraph`).
4. Use `String(localized:)` for the "items" unit.
5. Tests: with a decoded fixture graph in the store, the Pages row's value is
   "N items" and a trunk row's value matches its page count; replacing the
   graph updates the value.

## Do not

- Add counts for Outputs / Activity / Publish / Plan (the sidebar does not
  hold that data — do not invent plumbing).
- Parse `graph.json` in Chrome (the store already holds the decoded `Graph`).
- Touch the other lanes' files (above).

## Gate

VoiceOver on the sidebar announces "Pages, 45 items" and each trunk row
"FolderName, 7 items"; counts update after a rebuild. `SKIP_EMBED_BORIS=1
make build` + `make test` green.
