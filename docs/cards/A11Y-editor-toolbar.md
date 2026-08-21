# Card A11Y-4 — Editor toolbar accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#242](https://github.com/drawmeanelephant/solipsist/issues/242)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Editor companion. One worktree, one PR against `main`;
branch suggestion `feat/a11y-editor-toolbar`.

Spec: [`docs/issues/editor-accessibility-editor-toolbar.md`](../issues/editor-accessibility-editor-toolbar.md).

**Status: ⬜ not covered.** Toolbar controls carry only `.help()` or nothing;
nav + phase were refactored into subviews but stayed unlabeled.

## Owns

- `Sources/Companions/Editor/EditorWindow.swift` — URL field, Connect, Restart
- `Sources/Companions/Editor/` — `EditorNavButtons`, `EditorPhaseIndicator`
  (refactored subviews from the polish batch)

## Do not touch

- `Sources/Companions/Preview/` (A11Y-3)
- `Sources/Compose/` (A11Y-1)
- `Sources/Play/Local/` (A11Y-2)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The Editor toolbar's URL field, Connect, Restart, Back/Forward, and the phase
indicator have no VoiceOver labels. The polish batch refactored nav into
`EditorNavButtons` and the phase into `EditorPhaseIndicator` but left both
unlabeled.

## Do

1. Label the URL field ("Editor URL"), Connect, and Restart; add `.isButton`
   to the buttons.
2. In `EditorNavButtons`: label Back / Forward + `.isButton`.
3. In `EditorPhaseIndicator`: label the current phase ("Engine running") +
   `.isStaticText`; enumerate every phase value the indicator can render.
4. Keep existing `.help()` tooltips.
5. Strings: plain strings matching the file's existing style.
6. Tests: no honest unit seam — verify manually per the Gate.

## Do not

- Change layout, icons, or behavior.
- Build a separate accessibility mode.
- Add a third-party accessibility library.
- Touch the other lanes' files (above).

## Gate

VoiceOver on the Editor window announces "Editor URL", "Connect, button",
"Restart, button", "Back, button" / "Forward, button", and the current phase
("Engine running"); tooltips still appear on hover. `SKIP_EMBED_BORIS=1 make
build` + `make test` green.
