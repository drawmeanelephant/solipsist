# A11Y-4: Editor Toolbar — label the controls

- **Issue:** [#242](https://github.com/drawmeanelephant/solipsist/issues/242)
- **Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236)
- **Lane:** Editor companion
- **Owns:** `Sources/Companions/Editor/`

**Status: ✅ merged (PR #252).** Kept as the record; do not reopen. The
merged implementation matches this spec: plain strings, .help() tooltips
kept, all controls labeled, phase indicator enumerates all four cases.

## Problem

The Editor window's toolbar controls are **unlabeled** to assistive
technology. They carry only `.help()` tooltips (which VoiceOver does not read
as a name) or nothing at all. A VoiceOver user tabbing through the toolbar
hears anonymous buttons and cannot tell the URL field from Connect, Restart,
or the back/forward navigation, and the connection-phase indicator reads as an
unlabeled graphic.

## Verified current state (main `6ddffd7`)

`Sources/Companions/Editor/EditorWindow.swift` (and the refactored subviews it
uses):

- **URL field** — no `.accessibilityLabel`.
- **Connect button** — bare `.help()`; no label, no traits.
- **Restart button** — bare `.help()`; no label, no traits.
- **Navigation (back/forward)** — refactored into `EditorNavButtons` (a
  separate view) in the polish batch; still no labels, no traits.
- **Phase indicator** — `EditorPhaseIndicator` (separate view, also from the
  polish batch) is unlabeled; it renders the engine phase (e.g. `idle`,
  `running`, `error`) with no accessibility identity.
- `EditorURL` and `LocalPlayGraph` are in the test target; the toolbar views
  are not.

## Scope

Give each toolbar control a real accessibility identity:

1. **URL field** — label it (e.g. `"Editor URL"`) so it reads as a labeled
   text field.
2. **Connect** — `.accessibilityLabel("Connect")`, plus `.isButton` trait.
3. **Restart** — `.accessibilityLabel("Restart")`, plus `.isButton` trait.
4. **Back / Forward** (in `EditorNavButtons`) — `.accessibilityLabel("Back")`
   / `"Forward"`, plus `.isButton` trait.
5. **Phase indicator** (`EditorPhaseIndicator`) — give it an
   `.accessibilityLabel` describing the current phase (e.g. `"Engine idle"` /
   `"Engine running"` / `"Engine error"`), plus `.isStaticText`.

Keep existing `.help()` tooltips. Do not change any visual appearance, layout,
or behavior.

## Gate

With VoiceOver on in the Editor window toolbar:

- URL field announces "Editor URL".
- Connect / Restart announce "Connect, button" / "Restart, button".
- Back / Forward announce "Back, button" / "Forward, button".
- Phase indicator announces the current phase (e.g. "Engine running").
- Tooltips (`.help`) still appear on hover.

## Implementation sketch

```swift
TextField("", text: $url)
    .accessibilityLabel("Editor URL")

Button(action: connect) { … }
    .accessibilityLabel("Connect")
    .accessibilityAddTraits(.isButton)
    .help("Connect")

// EditorNavButtons:
Button(action: back) { … }
    .accessibilityLabel("Back")
    .accessibilityAddTraits(.isButton)

// EditorPhaseIndicator:
Text(phase.rawValue)
    .accessibilityLabel("Engine \(phase.rawValue)")
    .accessibilityAddTraits(.isStaticText)
```

## Tests

- The controls live in views that are not in the test target, so there is no
  honest unit test seam here. Verify by build + manual VoiceOver check (or AX
  probe) per the Gate.
- Do not add UI-automation tests the project does not run.

## Edge cases

- **Phase strings** — the label must read sensibly for every phase value the
  indicator can render (idle, running, error, and any others in the enum);
  enumerate them in the implementation.
- **Icon-only buttons** — labels must not fall back to symbol names; the
  explicit label is the source of truth.
- **Keyboard focus** — labels must not break the existing focus/tab order.

## Do not land

- Changing the toolbar's layout, icons, or behavior.
- Touching any file outside `Sources/Companions/Editor/`.
- Accessibility work on the Reading pane header (#240) or Preview toolbar
  (#241) — separate child issues.
