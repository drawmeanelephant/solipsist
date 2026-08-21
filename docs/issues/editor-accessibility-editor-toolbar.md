# Editor: Accessibility — Editor Toolbar

**Track:** macOS native polish / accessibility
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#242](https://github.com/drawmeanelephant/solipsist/issues/242)
**Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236) (tracker)
**Lane:** Editor companion — `Sources/Companions/Editor/`

## Problem

The Editor companion's toolbar controls are unlabeled for VoiceOver.

## Verified current state

`Sources/Companions/Editor/EditorWindow.swift` — `toolbar` renders nav buttons
(Back / Forward / Reload), a phase indicator, Restart Host, Open-in-Browser, a
URL `TextField`, and Connect. The nav buttons have `.help()` tooltips; none
has an `accessibilityLabel` / `accessibilityHint`.

## Scope

### Must land

- URL field: "Editor URL. Paste a BORIS_EDITOR_URL line to connect manually."
- Connect: "Connect to the editor host."
- Restart: "Restart the boris-editor host."
- Back: "Back. Navigate to the previous page."
- Forward: "Forward. Navigate to the next page."
- Reload: "Reload the editor page."
- The phase indicator announces as a single value (idle / starting /
  connected / failed).

### Must not land

- Touching `Sources/Companions/Preview/`, `Sources/Compose/`, or
  `Sources/Chrome/`.
- A separate accessibility mode.

## Gate

VoiceOver on the Editor window: every toolbar control announces its label; the
phase indicator announces connected / failed state. `SKIP_EMBED_BORIS=1 make
build` + `make test` green.

## Implementation sketch

1. Add `.accessibilityLabel(_:)` / `.accessibilityHint(_:)` to the nav
   buttons, Restart, Open-in-Browser, the URL field, and Connect.
2. Ensure the phase `Text` (which renders `phaseLabel`) is
   accessibility-relevant.

## Tests

- `testEditorToolbarLabels` — the toolbar controls expose non-empty labels.
- Manual: VoiceOver walk-through of the Editor window.

## Edge cases

- Disabled states (nav buttons with no history) still announce their labels.
- Failure phase → the phase indicator announces the error message.
