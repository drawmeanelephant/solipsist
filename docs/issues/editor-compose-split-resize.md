# Editor: Compose Split Pane Resize Handle + Auto-Save

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#227](https://github.com/drawmeanelephant/solipsist/issues/227)
**Lane:** `Sources/Compose/`

## Problem

The Compose editor's split has no visible resize handle and no persistence.
The ratio resets on every window open, and dragging a divider can push a pane
below its minimum.

## Verified current state

`ComposeEditorView` (`Sources/Compose/ComposeEditorView.swift`) uses a raw
`HSplitView` with three children: `ComposeFrontmatterForm` (min 230),
`ComposeTextView` (min 280), `ComposePreviewView` (min 240, conditional).
`frame(minWidth:)` sets layout minimums but there is no `dividerStyle`, no
`autosaveName`, and no delegate — the ratio is whatever the view computes on
open and the dividers are thin by default with no persistence.

## Scope

### Must land

- A **visible, draggable divider** between panes (`HSplitView` divider or
  `NSSplitView` `.thin` style).
- The split ratio **persists across sessions**, scoped per document type
  (e.g. Markdown vs Cooklang) so each frontend keeps its own layout.
- **Minimum pane widths enforced on drag**: editor ≥ 280, preview ≥ 240,
  frontmatter ≥ 230. The `frame(minWidth:)` values must be the real clamp, not
  just a layout hint.
- Toggling the frontmatter form off expands the editor into the freed space
  (no gap); toggling it on never collapses editor or preview below their
  minimums.

### Nice-to-have (not gate)

- A toolbar button to reset the split to the default.
- Double-click a divider to distribute panes evenly.
- **Keyboard resize of the divider** — note: `NSSplitView` dividers are not
  keyboard-resizable natively; this is real custom work. Keep it out of the
  gate unless it falls out cheaply.

### Must not land

- A custom drag handle that fights `NSSplitView`'s built-in behavior.
- A third-party split library.
- A divider inside the preview pane (a WKWebView surface).

## Implementation sketch

1. **Autosave + clamping need `NSSplitView`.** SwiftUI's `HSplitView` does not
   expose `autosaveName` or the delegate. Two workable options:
   - **Preferred:** wrap the split in an `NSViewRepresentable` around an
     `NSSplitView` (three subviews, `isVertical = true`, `dividerStyle = .thin`)
     and set `autosaveName = "ComposeSplit-<language>"` plus
     `NSSplitViewDelegate.splitView(_:constrainMinCoordinate:ofSubviewAt:)`
     returning the min widths. This gives autosave and clamping in one place.
   - Simpler if you want to stay in SwiftUI: keep `HSplitView`, persist the
     divider positions to `UserDefaults` keyed by `"ComposeSplit-<language>"`
     on change (track via the divider drag or the pane frames), and restore on
     appear. Clamping still needs the `NSSplitView` delegate, so the
     representable is the honest path for the minimum-width guarantee.
2. Scope the autosave/persistence key by `document.language.rawValue` so the
   Markdown ratio and the Cooklang ratio are independent.
3. When the frontmatter pane is hidden, remove it from the split (today the
   `if showFrontmatter` already removes the child) — the remaining panes
   reflow; verify no gap.
4. Keep the window's `minWidth: 640` (`ComposeWindow`) consistent with the
   sum of the pane minimums.

## Gate

Open a page in Compose → drag the divider → panes clamp at their minimums
(editor 280 / preview 240 / frontmatter 230) → close and reopen the window →
the ratio is restored → toggle Front Matter → the editor expands without a
gap and nothing collapses below its minimum. `SKIP_EMBED_BORIS=1 make build` +
`make test` green.

## Tests

- `testSplitAutosavePersists` — two document types keep independent ratios
  across window recreation (assert on the persisted positions).
- `testSplitMinimumWidths` — dragging past the minimum clamps at the minimum
  (assert via the delegate's `constrainMinCoordinate`).
- Manual: frontmatter toggle never collapses editor/preview below minimums.

## Edge cases

- Only one pane visible (editor only, no preview) → no divider to drag;
  verify the split handles a single child cleanly.
- The autosave name must not collide with the Editor companion window's
  split (different window, different key namespace).
- Restoring a saved ratio must not fight the window's `minWidth: 640`.
