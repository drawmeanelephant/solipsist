# A11Y-2: Reading Pane Header — one Announcement

- **Issue:** [#240](https://github.com/drawmeanelephant/solipsist/issues/240)
- **Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236)
- **Lane:** Reading
- **Owns:** `Sources/Play/Local/ReadingPane.swift`

## Problem

The Reading pane header announces its title and its status caption as **two
separate accessibility elements**. A VoiceOver user swiping through the header
hears "My Boris Site" then, a separate stop later, "Served · 3 pages". The
title is the only thing that tells them which page they're reading; the
caption (`Served`/`Draft`, page count, edit time) gives the page's state. Split
across two elements the state reads as an orphaned fragment, and nothing marks
the header as a single unit.

## Verified current state (main `6ddffd7`)

`Sources/Play/Local/ReadingPane.swift`:

- The header is `HStack { Text(title) …; Text(headerCaption) }` — two plain
  `Text` views, no `.accessibilityElement(children: .combine)`, no label, no
  traits.
- `headerCaption` is built from the served/draft state, page count, and edit
  time (e.g. `"Served · 3 pages · edited 2m ago"`).
- The **served badge** (`Served`/`Draft` pill) already gained accessibility
  work in the polish batch (#209/#210): it has `.accessibilityLabel("Served")`
  / `"Draft"` plus `.accessibilityAddTraits(.isStaticText)`. That part is
  **done** — do not redo it.
- The header's `Text` views are not in the test target (views are not compiled
  into ContractTests); the seam for any test lives in `LocalPlayGraph`
  (`pages(in:trunkID:)`, already tested).

## Scope

1. Make the header announce as **one element**: title + caption combined in
   order, e.g. `"My Boris Site, Served · 3 pages · edited 2m ago"`.
2. Keep the existing served-badge label/traits (already landed) — do not
   regress them.
3. The badge's **visual** appearance is unchanged; this is announcement-only.

Out of scope (already covered elsewhere, do not duplicate):

- The sidebar row counts (#243, merged) — `Sources/Chrome/SourceSidebar.swift`.
- Preview toolbar (#241) and Editor toolbar (#242) — separate child issues.

## Gate

With VoiceOver on and focus in the Reading pane header of a page in a trunk:

- Header announces **title and caption in a single stop**, in order (title
  first, then the status caption).
- The served/draft badge still announces its label (`Served` / `Draft`).
- No other Reading-pane element changed.

## Implementation sketch

```swift
// ReadingPane header
HStack {
    Text(title)
    Text(headerCaption)
    // …
}
.accessibilityElement(children: .combine)
// order = title then caption; the served badge keeps its own label/traits
```

`.combine` merges the children in layout order; if the badge sits between the
title and caption in the `HStack`, either reorder it after the caption or use
`.accessibilityLabel` with an explicit string so the announcement order is
deterministic regardless of visual layout.

## Tests

- No new seam exists to test: the announcement is a SwiftUI attribute on views
  that are not in the test target. If a pure helper is extracted for the
  caption string (e.g. `ReadingHeader.caption(state:count:edited:)`), add a
  ContractTests case for it — but the repo's current pattern has no such
  helper, so **do not invent one** unless the implementation naturally needs
  it.
- Verify by build + manual VoiceOver check (or AX probe) per the Gate.

## Edge cases

- **Served vs Draft** — both states must read sensibly inside the combined
  string ("Served · …" / "Draft · …").
- **Zero pages** — caption must not emit "0 pages" as a confusing fragment;
  match whatever the visual caption does.
- **Long titles** — combined string is announced as one unit; no truncation
  requirement beyond what the visual layout already does.

## Do not land

- Re-adding the served-badge label/traits work (already on main).
- Touching any file outside `Sources/Play/Local/ReadingPane.swift`.
