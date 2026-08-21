# Editor: Accessibility — Compose Toolbar + Diagnostics Pane

**Track:** macOS native polish / accessibility
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#239](https://github.com/drawmeanelephant/solipsist/issues/239)
**Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236) (tracker)
**Lane:** Compose — `Sources/Compose/`

## Problem

The Compose window's toolbar controls and diagnostics rows are not
VoiceOver-accessible: the toolbar buttons have `.help()` tooltips but no
`accessibilityLabel`, and each diagnostics row reads as a bare `HStack` with
no severity / line / message announcement.

## Verified current state

`Sources/Compose/ComposeEditorView.swift`:
- `toolbar` — Language picker, Preview toggle, Front Matter toggle, Render
  Options menu, Save button. All have `.help()` tooltips; **none** has an
  `accessibilityLabel` / `accessibilityHint`.
- `ComposeDiagnosticsPane` — rows are `HStack`s (icon, line number, message)
  with `.help("Jump to this diagnostic")`; no `.accessibilityElement(children:
  .combine)` and no combined label.

## Scope

### Must land

1. **Toolbar** — label + hint on every control:
   - Language picker: "Language, currently Markdown. Select the authoring
     frontend."
   - Preview toggle: "Toggle Preview. Show or hide the rendered preview pane."
   - Front Matter toggle: "Toggle Front Matter. Show or hide the front matter
     editor."
   - Render Options: "Render Options. Configure Oliver's parse extensions."
   - Save: "Save. Write the buffer to disk. Command-S."
2. **Diagnostics rows** — combine into a single announcement:
   "Error on line 12: unexpected token" / "Warning: missing closing fence".
   Use `.accessibilityElement(children: .combine)` and build the label from
   severity + optional line + message.

### Must not land

- A separate accessibility mode.
- A third-party accessibility library.
- Touching `Sources/Companions/`, `Sources/Play/Local/`, or `Sources/Chrome/`
  (other children own those).

## Gate

VoiceOver (⌘F5) on the Compose window: every toolbar control announces its
label/hint, and a diagnostics row announces "Error on line 12: …".
`SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Implementation sketch

1. Add `.accessibilityLabel(_:)` / `.accessibilityHint(_:)` to each toolbar
   control. Keep the existing `.help()` tooltips.
2. In `ComposeDiagnosticsPane`, per row:
   ```swift
   .accessibilityElement(children: .combine)
   .accessibilityLabel(
       (diagnostic.severity == .error ? "Error" : "Warning")
       + (diagnostic.line.map { " on line \($0)" } ?? "")
       + ": \(diagnostic.message)"
   )
   ```
3. Use `String(localized:)` for every user-facing string.

## Tests

- `testDiagnosticsRowAccessibilityLabel` — a row's combined label contains
  severity, line, and message (drive `ComposeDiagnostic` → label).
- `testToolbarControlsHaveLabels` — the toolbar's buttons/picker expose
  non-empty `accessibilityLabel` (via the label builder or the representable's
  view hierarchy).
- Manual: VoiceOver walk-through of the Compose toolbar + a diagnostics list.

## Edge cases

- A diagnostic with no line → the label reads "Error: message" (no "on line").
- Labels update when the diagnostics list changes (rows re-render).
- All labels use `String(localized:)`; no hardcoded English.
