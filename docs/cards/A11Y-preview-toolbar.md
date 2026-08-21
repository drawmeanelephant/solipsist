# Card A11Y-3 — Preview toolbar accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#241](https://github.com/drawmeanelephant/solipsist/issues/241)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Preview companion. One worktree, one PR against `main`;
branch suggestion `feat/a11y-preview-toolbar`.

Spec: [`docs/issues/editor-accessibility-preview-toolbar.md`](../issues/editor-accessibility-preview-toolbar.md).

**Status: ✅ merged (PR #251).** Kept as the record; do not reopen.

## Owns

- `Sources/Companions/Preview/` — toolbar labels (URL field, Reload,
  Open in Browser)

## Do not touch

- `Sources/Companions/Editor/` (A11Y-4)
- `Sources/Compose/` (A11Y-1)
- `Sources/Play/Local/` (A11Y-2)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The Preview toolbar's URL field, Reload, and Open-in-Browser controls carry
only `.help()` tooltips (or nothing) — VoiceOver reads three anonymous
buttons.

## Do

1. Label the URL field ("Preview URL"), Reload ("Reload"), and Open in Browser
   ("Open in Browser"); add `.isButton` to the two buttons.
2. Keep the existing `.help()` tooltips for hover text.
3. Strings: plain strings matching the file's existing style — do not
   introduce `String(localized:)`.
4. Tests: no honest unit seam (views are not in the test target) — verify
   manually per the Gate.

## Do not

- Change layout, icons, or behavior.
- Build a separate accessibility mode.
- Add a third-party accessibility library.
- Touch the other lanes' files (above).

## Gate

VoiceOver on the Preview window announces "Preview URL", "Reload, button", and
"Open in Browser, button"; tooltips still appear on hover. `SKIP_EMBED_BORIS=1
make build` + `make test` green.
