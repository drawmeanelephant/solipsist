# Editor: Go to Line Dialog (⌘L)

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#238](https://github.com/drawmeanelephant/solipsist/issues/238)
**Lane:** `Sources/Compose/`

## Problem

The Compose editor has no "Go to Line". Authors working from diagnostics (with
line numbers) can jump via click-to-line, but there is no ⌘L dialog for a
manual jump.

## Verified current state

`ComposeTextView` (`Sources/Compose/ComposeTextView.swift`) already has
`jumpToCharacter` (a `var` on the representable) and the `Coordinator.jump(to:in:)`
method that clamps, selects, and scrolls. `ComposeEditorView` computes a
character offset from a diagnostic's `line` in `characterIndex(for:in:)`. There
is no ⌘L shortcut, no line-number input, and no manual jump wiring.

## Scope

### Must land

- **⌘L** opens a small **"Go to Line"** sheet over the editor.
- The sheet has a **single text field** accepting a 1-based line number.
- **Enter** / **Go** jumps the cursor to the start of that line and scrolls it
  into view; **Escape** dismisses without jumping.
- The field is **pre-filled with the current line number**.
- **Validation**: non-integer input is rejected; a number beyond the buffer is
  clamped to the last line.
- The jump uses the existing `jumpToCharacter` seam — do not add a second
  jump path.
- The sheet must not appear when there is no document (empty state) or the
  window is not key.

### Nice-to-have (not gate)

- Show the total line count: `Go to line (of 123):`.
- Accept `line:column` (`12:45`).
- A menu item Edit → Go to Line… (menus-first rule; only if cheap).

### Must not land

- A separate window or full-screen overlay.
- A third-party library.
- **"Undoable" jump.** Cursor moves are not part of `NSTextView`'s undo stack;
  do not try to make a selection change undoable. (The draft asked for this —
  it is not how AppKit undo works.)

## Implementation sketch

1. Add `@State private var showGoToLine = false` to `ComposeEditorView`; wire
   ⌘L (`.keyboardShortcut("l", modifiers: .command)`) to set it true. Verify ⌘L
   is not already taken in the Compose window (the Boris menu uses ⌘⇧L for
   Plan, not ⌘L).
2. Present the sheet (`.sheet(isPresented: $showGoToLine)`) with a small view:
   a `TextField` pre-filled with the current line, Cancel / Go buttons, and
   `onSubmit` → jump.
3. `onJump(line:)` computes the character offset of that line via
   `NSString.lineRange` (handle CRLF/CR/BOM the same way the diagnostics
   click-to-line does) and sets the existing `jumpToCharacter` state.
4. The `Coordinator.jump(to:in:)` already clamps, selects, and scrolls — no
   new code there.

## Gate

Open a page in Compose → ⌘L opens the sheet pre-filled with the current line →
entering `5` jumps to line 5 and scrolls it into view → entering `99999`
clamps to the last line → entering `abc` does nothing → Escape dismisses
without jumping → no sheet on the empty state. `SKIP_EMBED_BORIS=1 make build` +
`make test` green.

## Tests

- `testGoToLineJumpsToLine` — line 5 maps to the correct character offset.
- `testGoToLineClampsToLastLine` — an out-of-range line clamps to the last.
- `testGoToLineRejectsNonInteger` — non-integer input does not jump.
- `testGoToLinePreFillsCurrentLine` — the field shows the current line.

## Edge cases

- Empty state (no document) → no sheet.
- Window not key → no keyboard input, no sheet.
- CR / CRLF / CR and a leading BOM → line→offset mapping stays correct.
