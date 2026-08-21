# Card A11Y-2 — Reading pane header accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#240](https://github.com/drawmeanelephant/solipsist/issues/240)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Reading. One worktree, one PR against `main`; branch
suggestion `feat/a11y-reading-header`.

Spec: [`docs/issues/editor-accessibility-reading-header.md`](../issues/editor-accessibility-reading-header.md).

## Owns

- `Sources/Play/Local/ReadingPane.swift` — the letter header announcement

## Do not touch

- `Sources/Compose/` (A11Y-1)
- `Sources/Companions/` (A11Y-3 / A11Y-4)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The reading-pane header (title + caption with path · status · role) reads as
separate pieces to VoiceOver instead of one announcement. The empty-state
label already exists — keep it.

## Do

1. Combine the title `VStack` (title + caption) into one element announcing
   "title, status, role" (`display(page.status)` handles the empty case).
2. Leave the Preview / Edit / Compose buttons and the served badge outside the
   combined element — they keep their own labels.
3. Use `String(localized:)` for the label.
4. Tests: the header combines title, status, role into one label.

## Do not

- Fold the action buttons into the combined element.
- Build a separate accessibility mode.
- Touch the other lanes' files (above).

## Gate

VoiceOver on the reading pane announces "Getting Started, published, Trunk"
as one element; the action buttons still announce individually.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
