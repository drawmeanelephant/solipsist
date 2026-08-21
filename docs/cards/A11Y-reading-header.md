# Card A11Y-2 — Reading pane header accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#240](https://github.com/drawmeanelephant/solipsist/issues/240)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Reading. One worktree, one PR against `main`; branch
suggestion `feat/a11y-reading-header`.

Spec: [`docs/issues/editor-accessibility-reading-header.md`](../issues/editor-accessibility-reading-header.md).

**Status: ⬜ not covered.** The header still announces as two separate
elements; only the served badge has a11y work (polish batch — keep it).

## Owns

- `Sources/Play/Local/ReadingPane.swift` — combine title + caption into one
  announcement

## Do not touch

- `Sources/Compose/` (A11Y-1)
- `Sources/Companions/` (A11Y-3 / A11Y-4)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The reading-pane header (title + caption "Served · 3 pages · edited 2m ago")
reads as two separate stops to VoiceOver; the caption fragment is orphaned.
The served badge already has its label + traits — keep them.

## Do

1. Combine the header's title and caption into one element
   (`.accessibilityElement(children: .combine)` or an explicit label) so it
   announces "My Boris Site, Served · 3 pages · edited 2m ago" in one stop,
   title first.
2. Keep the served/draft badge's existing label + traits; make the
   announcement order deterministic regardless of visual layout.
3. Tests: no honest unit seam exists (views are not in the test target) — do
   not invent a helper. Verify manually per the Gate.

## Do not

- Re-do the served-badge label/traits (already on main).
- Fold the action buttons into the combined element.
- Build a separate accessibility mode.
- Touch the other lanes' files (above).

## Gate

VoiceOver on the reading pane announces title + caption as one element, in
order; the served/draft badge still announces its label. `SKIP_EMBED_BORIS=1
make build` + `make test` green.
