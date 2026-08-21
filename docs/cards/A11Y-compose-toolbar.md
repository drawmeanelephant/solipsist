# Card A11Y-1 — Compose toolbar + diagnostics accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#239](https://github.com/drawmeanelephant/solipsist/issues/239)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Compose. One worktree, one PR against `main`; branch
suggestion `feat/a11y-compose-toolbar`.

Spec: [`docs/issues/editor-accessibility-compose-toolbar.md`](../issues/editor-accessibility-compose-toolbar.md).

## Owns

- `Sources/Compose/ComposeEditorView.swift` — toolbar control labels +
  diagnostics-row announcements

## Do not touch

- `Sources/Companions/` (A11Y-3 / A11Y-4)
- `Sources/Play/Local/ReadingPane.swift` (A11Y-2)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The Compose toolbar controls have `.help()` tooltips but no
`accessibilityLabel`, and each diagnostics row reads as a bare `HStack`.
VoiceOver users cannot act on the editor or read its problems.

## Do

1. Add `accessibilityLabel` + `accessibilityHint` to the Language picker,
   Preview toggle, Front Matter toggle, Render Options menu, and Save button
   (copy in the spec). Keep the existing `.help()` tooltips.
2. In `ComposeDiagnosticsPane`, combine each row:
   `.accessibilityElement(children: .combine)` with a label built from
   severity + optional line + message ("Error on line 12: …").
3. Use `String(localized:)` for every user-facing string.
4. Tests: a diagnostic row's combined label contains severity, line, and
   message; toolbar controls expose non-empty labels.

## Do not

- Build a separate accessibility mode.
- Add a third-party accessibility library.
- Touch the other lanes' files (above).

## Gate

VoiceOver (⌘F5) on the Compose window announces every toolbar control and a
diagnostics row ("Error on line 12: …"). `SKIP_EMBED_BORIS=1 make build` +
`make test` green.
