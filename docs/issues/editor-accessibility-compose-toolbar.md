# Editor: Accessibility — Compose Toolbar + Diagnostics Pane

**Track:** macOS native polish / accessibility
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#239](https://github.com/drawmeanelephant/solipsist/issues/239)
**Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236) (tracker)
**Lane:** Compose — `Sources/Compose/`

## Problem

Compose's toolbar and diagnostics pane are only partly VoiceOver-accessible.
The polish batch (#209/#210 a11y) already labeled four toolbar controls; this
issue closes the remaining gaps: the Language picker is unlabeled, three
controls have no hint, and diagnostics rows still read as a bare `HStack`.

## What main already has (do not redo)

`Sources/Compose/ComposeEditorView.swift` (`toolbar`) today:

| Control | Label | Hint | Traits |
|---------|-------|------|--------|
| Language picker | none (label text "Language" only) | none | — |
| Preview toggle | `"Preview"` | `"Toggle the Oliver preview pane"` | `.isSelected` when on |
| Front Matter toggle | `"Front Matter"` | **none** | `.isSelected` when on |
| Render Options menu | `"Render Options"` | **none** | — |
| Save button | `"Save"` | **none** | — |

`ComposeDiagnosticsPane`: rows are `HStack`s (icon, line number, message) with
only `.help("Jump to this diagnostic")` — **no** `.accessibilityElement` and
no combined label.

## Scope — must land (the delta)

1. **Language picker** — label that includes the **current** language
   ("Language, currently Markdown") so VoiceOver announces state, plus
   `.accessibilityHint("Select the authoring frontend")`. The label is
   dynamic — bind it to `document.language.displayName`.
2. **Hints on the three label-less controls**, for parity with the Preview
   toggle:
   - Front Matter: "Show or hide the front matter editor."
   - Render Options: "Configure Oliver's parse extensions."
   - Save: "Write the buffer to disk (⌘S)."
3. **Diagnostics rows** — one announcement per row:
   "Error on line 12: unexpected token" / "Warning: missing closing fence".
   - Extract the label as a pure helper on `ComposeDiagnostic` (see Tests) so
     it is unit-testable; the row applies `.accessibilityElement(children:
     .combine)` + `.accessibilityLabel(helper)`.

### Must not land

- Re-adding the four existing labels (already on main).
- A separate accessibility mode, or a third-party library.
- Touching `Sources/Companions/`, `Sources/Play/Local/`, `Sources/Chrome/`
  (other children), or `Project.yml` (the test target already compiles
  `ComposeDiagnostic.swift`).

## Implementation sketch

1. In `toolbar`, on the Language `Picker`:
   ```swift
   .accessibilityLabel("Language, currently \(document.language.displayName)")
   .accessibilityHint("Select the authoring frontend")
   ```
   (SwiftUI `Picker` already surfaces its label text; you may need to set the
   label explicitly to control the wording.)
2. Add `.accessibilityHint(...)` to Front Matter, Render Options, Save.
3. In `ComposeDiagnostic.swift`, add:
   ```swift
   extension ComposeDiagnostic {
       /// "Error on line 12: message" / "Warning: message" (no line → no count).
       var accessibilityLabel: String { ... }
   }
   ```
   and use it in `ComposeDiagnosticsPane` with `.accessibilityElement(children:
   .combine)`.
4. Strings: match the file's existing plain-string style. The repo has not
   adopted `String(localized:)`; do not introduce it here (tracker marks
   localization as a later nice-to-have).

## Gate

Manual VoiceOver (⌘F5) on the Compose window: the Language picker announces
the current language, each toolbar control announces a hint, and a diagnostics
row announces "Error on line 12: …". `SKIP_EMBED_BORIS=1 make build` +
`make test` green (including the new `ComposeDiagnostic` label test).

## Tests

- `ComposeDiagnosticAccessibilityTests` (in `Tests/ContractTests/`, compiled
  against `ComposeDiagnostic.swift`): label contains severity + line + message;
  a no-line diagnostic reads "Error: message".
  This is the only honest unit test — the view wiring is manual.
- Manual: VoiceOver walk-through of the toolbar + a diagnostics list.

## Edge cases

- No line on a diagnostic → "Error: message" (no "on line").
- Language changes → the picker label updates (verify VoiceOver re-reads).
- Diagnostics list re-renders when the render changes → labels follow (SwiftUI
  recomputes).