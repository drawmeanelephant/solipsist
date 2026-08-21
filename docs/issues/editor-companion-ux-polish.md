# Editor: Companion Window UX Polish

**Track:** Editor companion / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#237](https://github.com/drawmeanelephant/solipsist/issues/237)
**Lane:** `Sources/Companions/Editor/`

## Problem

The Editor companion window has UX rough edges: the URL field shows the raw
`BORIS_EDITOR_URL=…` launch line (confusing, leaks internals), the toolbar is
cluttered, error states give no guidance, and there is no menu-bar
"Open in Browser" item.

## Verified current state

`EditorWindow` (`Sources/Companions/Editor/EditorWindow.swift`):
- The URL `TextField` is bound to `urlText`, which is set to the **full**
  tokenized URL (`EditorURL.opening(...).absoluteString`) — raw, on display.
- The toolbar always shows nav buttons, phase indicator, Restart, Open-in-
  Browser, **and** the URL field + Connect.
- `headerTitle(for:)` **already falls back to `source.title`** when no page is
  selected — the draft's "header fallback" item is **already implemented**;
  do not rebuild it.
- Failed phases render the raw message (`phase = .failed("Editor host exited
  (N)…")`) with no guidance.
- `Commands.swift` has no "Open Editor in Browser" menu item (the window
  toolbar's Open-in-Browser button exists).

## Scope — must land

1. **Redacted URL field.** Show only `host:port`
   (`127.0.0.1:49152`), with the full URL on hover tooltip and on double-click
   (or a small reveal toggle). The field is **read-only** in normal use; it
   becomes editable only in a "Manual Connect" mode (below). Handle IPv6
   (`[::1]:9000`) and `localhost`.
2. **Toolbar collapse.** Hide the URL field + Connect behind a **"Manual
   Connect"** disclosure / menu item. The default toolbar shows: nav buttons,
   phase indicator, Restart, Open-in-Browser. The URL field appears when the
   user opens Manual Connect or when the phase is `.idle` / `.failed`.
3. **Error guidance.** Map known failures to actionable copy:
   - "boris-editor binary not found" → "Install boris-editor or set
     SOLIPSIST_BORIS_EDITOR_BIN."
   - "did not report a token URL within 15s" → "The host may be slow to start.
     Try again or check its logs."
   - "Editor host exited (N)" → "The editor host crashed. Check its logs."
   - Unknown messages → show the raw message with no invented guidance.
   - Add a "Copy Error" button on the error state.
4. **Menu-bar item.** Add **"Open Editor in Browser"** to the View menu
   (`Commands.swift`, `CommandGroup(after: .sidebar)` next to Preview/Editor/
   Compose), enabled only when a loopback editor URL is current — same action
   as the toolbar's Open-in-Browser.

### Nice-to-have (not gate)

5. Window title shows the page title ("Editor — Getting Started").
6. Drag-and-drop a `BORIS_EDITOR_URL=` line from Terminal into the URL field.

### Must not land

- A full browser chrome (address bar, back/forward, bookmarks).
- A custom URL parser — `EditorURL` is sufficient.
- Rebuilding the header fallback (already implemented — see above).

## Implementation sketch

1. `reducedURL`: parse `session.editorURL` (or `urlText`) with `URLComponents`,
   render `host:port`; `help()` shows the full string; a tap toggles a
   full/reduced display.
2. Wrap the URL field + Connect in a conditional `if showManualConnect ||
   session.phase == .idle || session.phase == .failed { … }` with a
   "Manual Connect" button toggling `showManualConnect`.
3. In the idle/failed states, render a `VStack` of headline + guidance caption
   + "Copy Error" button (copies the raw message to the pasteboard).
4. In `Commands.swift`, add the View-menu item gated on
   `session.editorURL != nil` (reach the session from the shared
   `AppRuntime`/window state; if the session is window-local, expose the
   current loopback URL through a small shared observable so the menu can
   enable/disable).

## Gate

Open the Editor companion → the toolbar shows nav, phase, Restart, and
Open-in-Browser only; the URL field shows `127.0.0.1:49152` (full URL on
hover), and the raw launch line is not visible → "Manual Connect" reveals the
editable field → a failed host shows actionable guidance + a Copy Error button
→ View → Open Editor in Browser is enabled when connected and opens the URL in
the default browser. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testReducedURLShowsHostPort` — `host:port` rendered, not the full URL.
- `testReducedURLHandlesIPv6` — `[::1]:9000` renders correctly.
- `testManualConnectHiddenByDefault` — URL field hidden when connected.
- `testErrorGuidanceShown` — a known failure maps to guidance; unknown shows
  the raw message.
- `testMenuOpenInBrowserEnabledWhenConnected` — the View item enables only
  with a loopback URL.

## Edge cases

- IPv6 and `localhost` host rendering (see tests).
- Very long source titles → `lineLimit(1)` truncation (already present).
- Unknown error messages → raw message, no invented guidance.
