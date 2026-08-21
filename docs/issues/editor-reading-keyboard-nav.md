# Editor: Keyboard Navigation in Pages List + Reading Pane

**Track:** Mail body / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#233](https://github.com/drawmeanelephant/solipsist/issues/233)
**Lane:** `Sources/Play/Local/`

## Problem

The Pages list and Reading pane do not fully support keyboard navigation.
Authors cannot ⌘Return into the editor, Escape to deselect, or page through
the list with Home/End/PageUp/PageDown.

## Verified current state

`LocalPlay.pageList` (`Sources/Play/Local/LocalPlay.swift`) renders a
`List(filtered, selection: selectedPageID)` with a
`.simultaneousGesture(TapGesture(count: 2))` that opens Compose, and an
`.onKeyPress(.return)` that opens the Compose window. **Up/Down arrows already
work** — SwiftUI `List` moves the selection through the `selection` binding;
do not add arrow handlers. Return already opens Compose. What is missing:
⌘Return → Editor, Escape → deselect, Home/End, Page Up/Down.

## Scope

### Must land

- **⌘Return** opens the **Editor** companion for the selected page.
- **Escape** deselects the current page (clears the Reading pane and resets
  the drawer) when the list is focused.
- **Page Up / Page Down** scroll the list by one visible page.
- **Home / End** jump to the first / last page in the list.
- **Up/Down arrows** keep working (List default — verify, add no handler).
- **Return** keeps opening **Compose** (existing behavior — verify).

### Nice-to-have (not gate)

- **⌘↑ / ⌘↓** move to the previous / next page.
- **Space** toggles the Reading pane's scroll position (Mail's "scroll
  message").
- **⌘/** focuses the Pages search field.

### Must not land

- A custom key-binding system (use SwiftUI's native `onKeyPress`).
- A third-party keyboard library.
- **Arrow-key handlers that return `.handled`** — that would block the
  `List`'s built-in selection movement. This was the trap in the draft; the
  arrows need no handler at all.

## Implementation sketch

1. Add to the `List` (alongside the existing `.onKeyPress(.return)`):
   ```swift
   .onKeyPress(.return, modifiers: .command) {
       guard store.selection.canEditPage else { return .ignored }
       openWindow(id: CompanionID.editor)
       return .handled
   }
   .onKeyPress(.escape) {
       if !searchText.isEmpty {
           searchText = ""        // search focused? clear it, do not deselect
           return .handled
       }
       store.select(noun: nil)
       return .handled
   }
   .onKeyPress(.home) { selectFirst(); return .handled }
   .onKeyPress(.end) { selectLast(); return .handled }
   .onKeyPress(.pageUp) { scrollByPage(-1); return .handled }
   .onKeyPress(.pageDown) { scrollByPage(1); return .handled }
   ```
   `onKeyPress` is macOS 14+; the deployment target is 26.0, so `.home`,
   `.end`, `.pageUp`, `.pageDown` are all available.
2. `selectFirst` / `selectLast` call `selectPage(pages.first/last)` through
   the same `selectPage(_:)` the click path uses.
3. Page Up/Down: scroll the list's scroll view by one visible page height
   (via the list's enclosing `NSScrollView` or an `@State` offset). If the
   native key equivalents already scroll the list, verify and skip the custom
   code.
4. **Focus discipline**: the handlers live on the list. When the search field
   is focused, its own key handling wins (arrow keys edit text, Escape clears
   the query) — the edge cases below pin this.

## Gate

With a source open in Pages: arrows move the selection; Return opens Compose;
⌘Return opens the Editor companion; Escape clears the selection and the
Reading pane; Page Up/Down scroll the list; Home/End select first/last; with
the search field focused, arrows edit the query and Escape clears it instead
of deselecting. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testCommandReturnOpensEditor` — ⌘Return opens the Editor companion.
- `testEscapeDeselects` — Escape clears the selection (list focused).
- `testEscapeClearsSearch` — Escape with a query clears it, keeps selection.
- `testHomeEndSelectFirstLast` — Home/End select first/last page.
- Manual: arrows still move the selection (no handler added); Page Up/Down
  scroll by a page.

## Edge cases

- Arrow keys must not move the selection while the search field is focused
  (the field consumes them for text editing).
- Return / ⌘Return must not open anything with no page selected
  (`canEditPage` guard).
- ⌘Return must not open the Editor when the editor binary is missing — the
  Editor window already fails gracefully; do not add a new check here.
- Escape must not deselect when the search field is focused (clears the query
  instead).
