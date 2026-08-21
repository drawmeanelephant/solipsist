# Editor: Accessibility — Mailbox Sidebar Counts

**Track:** macOS native polish / accessibility
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#243](https://github.com/drawmeanelephant/solipsist/issues/243)
**Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236) (tracker)
**Lane:** Mailboxes — `Sources/Chrome/`

## Problem

The mailbox sidebar announces row titles but not item counts, so VoiceOver
users cannot tell how many pages sit under Pages or a trunk folder.

## Verified current state

`Sources/Chrome/SourceSidebar.swift`:
- `MailboxRow` has `.accessibilityLabel("\(item.title), \(displayName)")` — no
  `accessibilityValue`.
- `PagesGroup` renders the Pages row plus `TrunkRow` children from the decoded
  graph.
- `TrunkRow` has `.accessibilityLabel("\(item.title), \(trunk.title)")` — no
  count.
- **No new plumbing is needed**: `LocalPlay.apply` already calls
  `store.updateGraph(graph, for: source.id)`, and `PagesGroup` already reads
  the graph via `store.graph(for:)` + `LocalPlayGraph.trunks(from:)`.
  `LocalPlayGraph.pages(in:trunkID:)` already counts a trunk's pages.

## Scope

### Must land

- Pages row: `.accessibilityValue("\(pageCount) items")` — the page count from
  `store.graph(for:)` (all pages in the graph).
- Each trunk row: `.accessibilityValue("\(count) items")` — per-trunk count
  via `LocalPlayGraph.pages(in: trunkID:)`.
- Counts update when the graph rebuilds (they derive from the stored graph).

### Must not land

- Counts for Outputs / Activity / Publish / Plan (the sidebar does not hold
  that data — do not invent plumbing).
- Touching `Sources/Compose/`, `Sources/Play/Local/`, or
  `Sources/Companions/`.
- A separate accessibility mode.

## Gate

VoiceOver on the sidebar: the Pages row announces "Pages, 45 items" and each
trunk row announces "FolderName, 7 items"; counts update after a rebuild.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Implementation sketch

1. In `PagesGroup`, compute the page count from the stored graph and set
   `.accessibilityValue("\(pageCount) items")` on the Pages `MailboxRow`.
2. In `TrunkRow`, compute the trunk's page count via
   `LocalPlayGraph.pages(in: trunk.id, ...)` and set
   `.accessibilityValue("\(count) items")`.
3. Use `String(localized:)` for the "items" unit.

## Tests

- `testPagesRowCountAccessibilityValue` — with a decoded fixture graph in the
  store, the Pages row's value is "N items" (the fixture count).
- `testTrunkRowCountAccessibilityValue` — a trunk row's value matches its page
  count.
- `testCountsUpdateOnGraphChange` — replacing the store's graph updates the
  value.

## Edge cases

- No graph yet (source just added) → no rows, no counts; not an error.
- A trunk with zero pages → "0 items".
- Counts must recompute when `updateGraph` fires.
