# Editor: Preview Companion — Pinch-to-Zoom + Zoom Controls

**Track:** Preview companion / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#234](https://github.com/drawmeanelephant/solipsist/issues/234)
**Lane:** `Sources/Companions/Preview/`

## Problem

The Preview companion's `WKWebView` does not support pinch-to-zoom or ⌘+/⌘-/
⌘0 controls. Authors reviewing their published site cannot zoom in to inspect
detail or zoom out to see the full layout.

## Verified current state

`PreviewWebModel` (`Sources/Companions/Preview/PreviewWindow.swift`) creates
`let webView = WKWebView()` with default configuration — no
`allowsMagnification`, no zoom methods, no zoom toolbar. The Reading pane's
`ReadingWebModel` (`Sources/Play/Local/ReadingWebView.swift`) does set
`webView.allowsMagnification = true`. The Preview toolbar has only a URL field,
Reload, and Open-in-Browser.

## Scope

### Must land

- **Pinch-to-zoom**: `webView.allowsMagnification = true`.
- **⌘+ / ⌘- / ⌘0** shortcuts for zoom in / out / reset.
- A **zoom percentage** readout in the Preview toolbar (e.g. `100%`).
- A **zoom reset** control in the toolbar.
- The zoom level **persists per source** (app plist / `UserDefaults` keyed by
  source id) and is restored on the next session.

### Nice-to-have (not gate)

- **Zoom to Fit** (⌘9) — scale to window width.
- A zoom slider in the toolbar.

### Must not land

- A custom zoom implementation that fights `WKWebView`'s built-in
  magnification.
- Zoom that persists across different sources (zoom is source-scoped).
- Zoom in the Compose preview pane (a different surface).

## Implementation sketch

1. In `PreviewWebModel`, enable magnification and clamp it:
   ```swift
   webView.allowsMagnification = true
   webView.minMagnification = 0.25
   webView.maxMagnification = 4.0
   ```
2. Add zoom methods that read/write `webView.magnification`:
   ```swift
   func zoomIn()  { webView.magnification = min(webView.magnification * 1.25, 4.0) }
   func zoomOut() { webView.magnification = max(webView.magnification / 1.25, 0.25) }
   func zoomReset() { webView.magnification = 1.0 }
   ```
3. Publish `zoomLevel` (a `CGFloat`) so the toolbar label updates. Preferred:
   KVO on `webView.magnification` (it is a plain property and is observable in
   practice). If KVO proves unreliable, fall back to updating the model's own
   value whenever the code changes it and reading `webView.magnification`
   after pinch/scroll events — pick one path and verify it tracks both the
   toolbar buttons and the trackpad pinch.
4. Add the toolbar controls (`minus.magnifyingglass`, the `%` text, `plus`,
   `1.magnifyingglass`) and the ⌘+/⌘-/⌘0 keyboard shortcuts.
5. Persist per source: `UserDefaults` keyed by `source.id` (string). Load on
   `startPreview`, apply `webView.magnification` after the first load; save on
   change.
6. **Reload / SSE reload already preserve zoom** — `magnification` is a
   `WKWebView` property, not per-page, so `webView.reload()` keeps it. Verify,
   do not add reload hooks.

## Gate

Open Preview → pinch on the trackpad zooms the page → ⌘+ / ⌘- / ⌘0 change and
reset zoom (clamped 0.25–4.0) → the toolbar shows the live percentage → switch
sources and back → each source restores its own zoom → a save-triggered reload
keeps the zoom level. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testZoomInOutReset` — the model's zoom methods change magnification and
  reset to 1.0.
- `testZoomClampsToMinMax` — zooming past 4.0 / below 0.25 clamps.
- `testZoomPersistsPerSource` — setting 150% and recreating the model for the
  same source id restores 150%; a different source id restores its own.
- Manual: pinch and buttons stay in sync; reload keeps the zoom.

## Edge cases

- Pinch and toolbar must share the same magnification value (no double-zoom).
- Switching sources must not leak one source's zoom into another.
- A save-triggered / SSE reload must preserve the zoom level (WebKit keeps
  magnification across `reload()` — verify).
