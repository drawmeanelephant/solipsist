# A11Y-3: Preview Toolbar — label the controls

- **Issue:** [#241](https://github.com/drawmeanelephant/solipsist/issues/241)
- **Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236)
- **Lane:** Preview companion
- **Owns:** `Sources/Companions/Preview/`

## Problem

The Preview window's toolbar controls are **unlabeled** to assistive
technology. They carry only `.help()` tooltips, which VoiceOver does not read
as a name. A VoiceOver user tabbing through the toolbar hears three unlabeled
buttons ("button", "button", "button") and has no way to tell which is the URL
field, Reload, or Open-in-Browser.

## Verified current state (main `6ddffd7`)

`Sources/Companions/Preview/` (toolbar in the Preview window):

- **URL field** — no `.accessibilityLabel`.
- **Reload button** — `.help("Reload")` only; no label, no traits.
- **Open in Browser button** — `.help("Open in Browser")` only; no label, no
  traits.
- No accessibility attributes on any of the three controls.
- `PreviewURL` (the URL value type) is in the test target; the toolbar views
  are not.

## Scope

Give each toolbar control a real accessibility identity:

1. **URL field** — label it (e.g. `"Preview URL"`) so it reads as a labeled
   text field, not an anonymous editable area.
2. **Reload** — `.accessibilityLabel("Reload")`, plus `.isButton` trait.
3. **Open in Browser** — `.accessibilityLabel("Open in Browser")`, plus
   `.isButton` trait.

Keep the existing `.help()` tooltips where they add hover text; the label is
what VoiceOver reads. Do not change any visual appearance, layout, or
behavior.

## Gate

With VoiceOver on in the Preview window toolbar:

- URL field announces "Preview URL".
- Reload announces "Reload, button".
- Open in Browser announces "Open in Browser, button".
- Tooltips (`.help`) still appear on hover.

## Implementation sketch

```swift
TextField("", text: $url)
    .accessibilityLabel("Preview URL")

Button(action: reload) { Image(systemName: "arrow.clockwise") }
    .accessibilityLabel("Reload")
    .accessibilityAddTraits(.isButton)
    .help("Reload")

Button(action: openInBrowser) { Image(systemName: "safari") }
    .accessibilityLabel("Open in Browser")
    .accessibilityAddTraits(.isButton)
    .help("Open in Browser")
```

## Tests

- The controls live in views that are not in the test target, so there is no
  honest unit test seam here. Verify by build + manual VoiceOver check (or AX
  probe) per the Gate.
- Do not add UI-automation tests the project does not run.

## Edge cases

- **Icon-only buttons** — the label must not be empty or fall back to the
  symbol name; the explicit label is the source of truth.
- **Keyboard focus** — labels must not break the existing focus/tab order.

## Do not land

- Changing the toolbar's layout, icons, or behavior.
- Touching any file outside `Sources/Companions/Preview/`.
- Accessiblity work on the Reading pane header (#240) or Editor toolbar
  (#242) — separate child issues.
