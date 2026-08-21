# Card A11Y-1 — Compose toolbar + diagnostics accessibility

**Milestone:** 10 (post-M17 polish) · **Issue:**
[#239](https://github.com/drawmeanelephant/solipsist/issues/239)
(parent [#236](https://github.com/drawmeanelephant/solipsist/issues/236))
· **Lane:** Compose. One worktree, one PR against `main`; branch
suggestion `feat/a11y-compose-toolbar`.

Spec: [`docs/issues/editor-accessibility-compose-toolbar.md`](../issues/editor-accessibility-compose-toolbar.md).

**Status: ✅ merged (PR #247).** Kept as the record; do not reopen.

## Owns

- `Sources/Compose/ComposeEditorView.swift` — Language picker label + hints
  (the delta)
- `Sources/Compose/ComposeDiagnostic.swift` — `accessibilityLabel` helper
  (already in the test target)

## Do not touch

- `Sources/Companions/` (A11Y-3 / A11Y-4)
- `Sources/Play/Local/ReadingPane.swift` (A11Y-2)
- `Sources/Chrome/SourceSidebar.swift` (A11Y-5)
- `Sources/Engine/**`
- `Project.yml`

## Why

The polish batch labeled four toolbar controls, but the Language picker is
still unlabeled, three controls lack hints, and each diagnostics row reads as
a bare `HStack`. VoiceOver users cannot reliably act on the editor or read its
problems.

## Do

1. Language picker: label including the current language ("Language, currently
   Markdown") + hint "Select the authoring frontend" (copy in the spec).
2. Add `.accessibilityHint` to Front Matter, Render Options, Save — parity
   with the Preview toggle (copy in the spec).
3. In `ComposeDiagnostic.swift`, add a pure `accessibilityLabel` helper
   ("Error on line 12: …" / "Warning: message"); apply it in
   `ComposeDiagnosticsPane` with `.accessibilityElement(children: .combine)`.
4. Strings: plain strings matching the file's existing style — do not
   introduce `String(localized:)` (tracker marks it a later nice-to-have).
5. Tests: `ComposeDiagnosticAccessibilityTests` in `Tests/ContractTests/` —
   the one honest seam, since `ComposeDiagnostic` is in the test target.

## Do not

- Re-add the four existing labels (already on main).
- Build a separate accessibility mode.
- Add a third-party accessibility library.
- Touch the other lanes' files (above).

## Gate

VoiceOver (⌘F5) on the Compose window: the Language picker announces the
current language, every toolbar control announces a hint, and a diagnostics
row announces "Error on line 12: …". `SKIP_EMBED_BORIS=1 make build` +
`make test` green (including the new `ComposeDiagnostic` label test).
