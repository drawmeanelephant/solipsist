# Editor: Find & Replace in Compose

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#225](https://github.com/drawmeanelephant/solipsist/issues/225)
**Lane:** `Sources/Compose/`

## Problem

The Compose editor has no Find & Replace. Authors editing large Markdown /
Textile / Cooklang files cannot search the buffer, step through matches, or
replace text. This is a basic macOS text-editing expectation (⌘F / ⌘G /
⌘⇧G / replace).

## Verified current state

`ComposeTextView` (`Sources/Compose/ComposeTextView.swift`) creates a plain
`NSTextView` in `makeNSView` with `isRichText = false` and
`allowsUndo = true`. The view has no find-bar wiring: `usesFindBar` is never
set, there is no `NSSearchToolbarItem`, and nothing calls
`performTextFinderAction`. ⌘F does nothing today.

## Scope

### Must land

- **⌘F** presents the **system** find bar over the text view
  (`usesFindBar = true`; macOS handles the key equivalent).
- **⌘G / ⌘⇧G** step next / previous through matches (the find bar's own
  next/previous actions).
- **Replace** is the find bar's built-in Replace tab (⌘⌥F focuses it, or the
  segment in the bar). One / all replacement mutates `ComposeDocument.text`
  and marks it dirty.
- Match highlight must be visually distinct from the heuristic paint layer —
  the system find bar draws its own selection highlight independent of the
  attributed-string colors, so no conflict is expected; verify on a file with
  headings/code/links painted.
- Wrap-around at the end of the buffer (system default; verify).
- Case-sensitive default with a case-insensitive toggle, and regex support —
  both come from the system find bar's popover; do not build them.
- The find bar is scoped to the current buffer, never the preview or the file
  system.

### Must not land

- A custom find bar UI. Use the system `usesFindBar` path.
- Find in the preview pane (that is a WKWebView surface, not our buffer).
- Multi-file search (a content-tree feature, not Compose).
- A third-party library. The NSTextView find bar is the path.

## Gate

Open a page in Compose (⌘⇧C) with a multi-line buffer → ⌘F shows the system
find bar → typing a query highlights matches and ⌘G / ⌘⇧G walk them with
wrap-around → Replace tab replaces one and all and marks the buffer dirty →
the find bar is absent on the Compose empty state and does not survive a page
switch. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Implementation sketch

1. In `ComposeTextView.makeNSView`, enable the find bar:
   ```swift
   textView.usesFindBar = true
   ```
   The ⌘F / ⌘G / ⌘⇧G key equivalents are handled by the text view once this
   is set. If they do not fire inside the SwiftUI window, wire them explicitly
   in the Coordinator:
   ```swift
   textView.performTextFinderAction(NSSelectorFromString("showFindInterface:")) // ⌘F
   textView.performTextFinderAction(NSSelectorFromString("showNextMatch:"))     // ⌘G
   textView.performTextFinderAction(NSSelectorFromString("showPreviousMatch:")) // ⌘⇧G
   ```
2. `ComposeTextView` is an `NSViewRepresentable`; the find bar renders inside
   the scroll view SwiftUI creates around the text view. If it does not appear,
   build an explicit `NSScrollView` in `makeNSView` (the same change the
   line-number gutter needs — see #226) and set `usesFindBar` on the text view
   inside it.
3. Replace writes through `ComposeDocument.text` (the buffer is the single
   source of truth). The find bar edits the text storage; the Coordinator's
   existing `textDidChange` already syncs storage → `document.text`, so no new
   sync is needed — verify it fires for find-bar edits.
4. No highlighter change is expected: the find bar's selection highlight is a
   separate layer. Confirm visually with a painted buffer.

## Tests

- `testFindBarEnabled` — the text view reports `usesFindBar == true` after
  `makeNSView` (unit-testable through the representable's view).
- `testFindBarReplaceOne` — replacing one through the find bar updates
  `ComposeDocument.text` and sets `isDirty`.
- `testFindBarReplaceAll` — replace-all updates the buffer and marks dirty.
- Manual (UI): ⌘F shows the bar; ⌘G wraps; case-insensitive and regex toggles
  work; highlight does not fight the paint layer.

## Edge cases

- No document loaded → no find bar (the empty state has no `ComposeTextView`).
- Page switch → the buffer changes; the view is recreated per document, so the
  find bar closes naturally. Verify no stale find state persists.
- Find-bar edits must not repaint the whole buffer — the existing incremental
  `repaintChanged` path should handle them; verify.
