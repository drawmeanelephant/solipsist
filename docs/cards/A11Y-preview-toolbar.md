# Card A11Y-3 — Preview toolbar accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#241](https://github.com/drawmeanelephant/solipsist/issues/241)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Preview companion. One worktree, one PR against `main`;
branch suggestion `feat/a11y-preview-toolbar`.

Spec: [`docs/issues/editor-accessibility-preview-toolbar.md`](../issues/editor-accessibility-preview-toolbar.md).

## Owns

- `Sources/Companions/Preview/PreviewWindow.swift` — toolbar labels

## Do not touch

- `Sources/Companions/Editor/` (A11Y-4)
- `Sources/Compose/` (A11Y-1)
- `Sources/Play/Local/` (A11Y-2)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The Preview toolbar's URL field, Reload, and Open-in-Browser buttons have no
VoiceOver labels.

## Do

1. Label the URL field ("Preview URL. …"), Reload ("Reload the preview
   page."), and Open in Browser ("Open in Safari.").
2. Make the session status line (`session.statusText`) announce
   connected / failure state.
3. Use `String(localized:)` for every user-facing string.
4. Tests: the toolbar controls expose non-empty labels.

## Do not

- Build a separate accessibility mode.
- Add a third-party accessibility library.
- Touch the other lanes' files (above).

## Gate

VoiceOver on the Preview window announces the URL field, Reload, and
Open-in-Browser, plus the status line. `SKIP_EMBED_BORIS=1 make build` +
`make test` green.
