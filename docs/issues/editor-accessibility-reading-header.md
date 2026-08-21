# Editor: Accessibility — Reading Pane Header

**Track:** macOS native polish / accessibility
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#240](https://github.com/drawmeanelephant/solipsist/issues/240)
**Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236) (tracker)
**Lane:** Reading — `Sources/Play/Local/`

## Problem

The reading-pane header (page title, status, role) is not a single VoiceOver
announcement; VoiceOver reads the pieces separately with no context.

## Verified current state

`Sources/Play/Local/ReadingPane.swift` — `header(for:)` renders an icon, a
title stack (`page.title` + `headerCaption(for:)`, which already contains
path · status · role), a served badge, and Preview / Edit / Compose buttons.
There is no `.accessibilityElement(children: .combine)` on the title stack, so
the title, caption, and badge announce separately. The "No Page Selected"
empty state already has a label + hint.

## Scope

### Must land

- Combine the title + caption into one announcement: "Getting Started,
  published, Trunk" (title, status, role).
- The served badge and the Preview / Edit / Compose buttons keep their own
  labels (do not fold the action buttons into the combined element).
- The "No Page Selected" empty state keeps its existing label/hint.

### Must not land

- Touching `Sources/Compose/`, `Sources/Companions/`, or `Sources/Chrome/`.
- A separate accessibility mode.

## Gate

VoiceOver on the reading pane: selecting a page announces "Getting Started,
published, Trunk" as one element; the action buttons still announce
individually. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Implementation sketch

1. Wrap the title `VStack` in `.accessibilityElement(children: .combine)` and
   set:
   ```swift
   .accessibilityLabel(
       "\(page.title), \(display(page.status)), \(page.role == .trunk ? "Trunk" : "Satellite")"
   )
   ```
2. Leave the action buttons outside the combined element.

## Tests

- `testReadingHeaderAccessibilityLabel` — the header combines title, status,
  role into one label.
- Manual: VoiceOver announces the header as one element.

## Edge cases

- Empty status → the label reads "Title, —, Trunk" (reuse the existing
  `display(_:)`).
- Long titles → `lineLimit(1)` truncation stays; the label can use the full
  title.
