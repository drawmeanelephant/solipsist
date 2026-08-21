# Editor: Accessibility — Preview Toolbar

**Track:** macOS native polish / accessibility
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#241](https://github.com/drawmeanelephant/solipsist/issues/241)
**Parent:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236) (tracker)
**Lane:** Preview companion — `Sources/Companions/Preview/`

## Problem

The Preview companion's toolbar controls are unlabeled for VoiceOver.

## Verified current state

`Sources/Companions/Preview/PreviewWindow.swift` — `toolbar` renders a URL
`TextField`, Reload, and Open-in-Browser buttons (plus a rejection line and
the session status line). None has an `accessibilityLabel` /
`accessibilityHint`.

## Scope

### Must land

- URL field: "Preview URL. http://127.0.0.1:8080/__boris/"
- Reload: "Reload the preview page."
- Open in Browser: "Open in Safari."
- The session status line announces as a single value (serve URL or failure).

### Must not land

- Touching `Sources/Companions/Editor/`, `Sources/Compose/`, or
  `Sources/Chrome/`.
- A separate accessibility mode.

## Gate

VoiceOver on the Preview window: the URL field, Reload, and Open-in-Browser
announce their labels; the status line announces. `SKIP_EMBED_BORIS=1 make
build` + `make test` green.

## Implementation sketch

1. Add `.accessibilityLabel(_:)` / `.accessibilityHint(_:)` to the text field
   and both buttons.
2. Mark the status `Text` (which renders `session.statusText`) as
   accessibility-relevant so it announces connected / failure state.

## Tests

- `testPreviewToolbarLabels` — the toolbar controls expose non-empty labels.
- Manual: VoiceOver walk-through of the Preview window.

## Edge cases

- The preview URL is loopback — safe to expose to VoiceOver.
- Failure state → the status line announces the failure message.
