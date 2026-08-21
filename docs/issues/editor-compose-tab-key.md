# Editor: Tab Key — Indent with 2 Spaces

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#229](https://github.com/drawmeanelephant/solipsist/issues/229)
**Lane:** `Sources/Compose/`

## Problem

The Compose editor does not handle Tab intentionally. `NSTextView`'s default
inserts a tab character (or moves focus), but authors expect Tab to **indent**
the current or selected lines and Shift+Tab to **outdent** — like Xcode and
TextEdit.

## Verified current state

`ComposeTextView` (`Sources/Compose/ComposeTextView.swift`) wraps an
`NSTextView` with `isRichText = false`, `allowsUndo = true`. The `Coordinator`
implements `NSTextViewDelegate` for `textDidChange` and completion
(`maybeOpenCompletion` → `textView.complete(nil)` for Cooklang markers) but
does **not** implement `textView(_:doCommandBy:)`, so Tab falls through to
AppKit's default.

## Scope

### Must land

- **Tab** inserts **2 spaces** (Boris's indentation convention for Markdown,
  Textile, and Cooklang).
- With **multiple lines selected**, Tab indents **every selected line** (it
  must not replace the selection with spaces).
- **Shift+Tab** outdents the current or every selected line — removes one
  level of leading whitespace (2 spaces, or 1 tab if that is what is present).
- Indent/outdent is **one undo group** (indenting 10 lines = one ⌘Z).
- **Cooklang completion**: when the completion popup is open at a Cooklang
  marker, Tab must **accept the selected suggestion**, not indent. The popup
  is opened by `maybeOpenCompletion`; respect it.

### Nice-to-have (not gate)

- Tab mid-line inserts indentation; Tab mid-word inserts a literal tab
  (Xcode's "Insert Tab" nuance).
- A preference for 2 vs 4 spaces (app plist).

### Must not land

- Tab inserting a literal `\t` character (Boris content is space-indented).
- Tab replacing the selection with a tab character.
- A third-party key-binding library.

## Implementation sketch

1. In `ComposeTextView.Coordinator`, implement
   `textView(_:doCommandBy:)`:
   ```swift
   func textView(_ textView: NSTextView, doCommandBy command: Selector) -> Bool {
       if command == #selector(NSResponder.insertTab(_:)) {
           // Cooklang completion open → let the default insert the
           // selected suggestion instead of indenting.
           if textView.rangeForUserCompletion != nil { return false }
           indentSelection(textView, direction: .in)
           return true
       }
       if command == #selector(NSResponder.insertBacktab(_:)) {
           indentSelection(textView, direction: .out)
           return true
       }
       return false
   }
   ```
   Returning `true` consumes the key; `false` lets the default run.
2. `indentSelection` operates on the selected line range(s) (expand the
   selection to full lines via `NSString.lineRange`), prepending or removing
   2 leading spaces per line, wrapped in a single undo group
   (`textView.shouldChangeText(in:replacementString:)` + undo manager, or
   `undoManager` grouping).
3. Verify the Cooklang case: when the completion popup is up, `insertTab:` may
   not even reach `doCommandBy` (the completion window consumes it). If it
   does, the `rangeForUserCompletion != nil` check above handles it.

## Gate

Open a Markdown page → Tab indents the line with 2 spaces → select 3 lines +
Tab indents all 3 → Shift+Tab outdents → ⌘Z reverts the whole indent in one
step → Tab on an empty line inserts 2 spaces (focus does not move). In a
Cooklang buffer with a completion open, Tab inserts the selected suggestion,
not spaces. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testTabInsertsTwoSpaces` — Tab at line start inserts 2 spaces.
- `testTabIndentsMultipleLines` — 3 selected lines all get indented.
- `testShiftTabOutdents` — removes 2 leading spaces; a leading tab is removed
  as one level.
- `testTabUndoable` — indenting 5 lines then ⌘Z reverts all 5 (one undo
  group).
- `testTabDoesNotReplaceSelection` — selecting "hello" and pressing Tab
  indents the line, does not replace the selection.

## Edge cases

- Empty line → Tab inserts 2 spaces, does not move focus.
- End of a long line → Tab indents the line, not the caret position.
- Mixed spaces+tabs in a line → outdent removes whichever leading whitespace
  is present (2 spaces or 1 tab), never both.
- Find bar open → Tab focuses the find field; the editor's `doCommandBy` must
  not fire (it is a different responder — verify).
