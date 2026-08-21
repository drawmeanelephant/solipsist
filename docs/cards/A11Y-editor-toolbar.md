# Card A11Y-4 — Editor toolbar accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#242](https://github.com/drawmeanelephant/solipsist/issues/242)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Editor companion. One worktree, one PR against `main`;
branch suggestion `feat/a11y-editor-toolbar`.

Spec: [`docs/issues/editor-accessibility-editor-toolbar.md`](../issues/editor-accessibility-editor-toolbar.md).

## Owns

- `Sources/Companions/Editor/EditorWindow.swift` — toolbar labels

## Do not touch

- `Sources/Companions/Preview/` (A11Y-3)
- `Sources/Compose/` (A11Y-1)
- `Sources/Play/Local/` (A11Y-2)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The Editor toolbar's nav buttons, Restart, Open-in-Browser, URL field, and
Connect have `.help()` tooltips but no VoiceOver labels.

## Do

1. Label the URL field ("Editor URL. Paste a BORIS_EDITOR_URL line to connect
   manually."), Connect, Restart, Back, Forward, and Reload (copy in the
   spec).
2. Make the phase indicator (`phaseLabel`) announce idle / starting /
   connected / failed state.
3. Use `String(localized:)` for every user-facing string.
4. Tests: the toolbar controls expose non-empty labels.

## Do not

- Build a separate accessibility mode.
- Add a third-party accessibility library.
- Touch the other lanes' files (above).

## Gate

VoiceOver on the Editor window announces every toolbar control and the phase
indicator. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
