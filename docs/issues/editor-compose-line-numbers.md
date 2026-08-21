# Editor: Line Numbers Gutter in Compose

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#226](https://github.com/drawmeanelephant/solipsist/issues/226)
**Lane:** `Sources/Compose/`

## Problem

The Compose editor has no line number gutter. Authors editing large files
cannot orient by line number, and diagnostics (which carry `line` fields)
have no visual counterpart in the buffer — click-to-jump exists but the user
cannot verify the number.

## Verified current state

`ComposeTextView` (`Sources/Compose/ComposeTextView.swift`) returns a bare
`NSTextView` from `makeNSView` (`isVerticallyResizable = true`,
`widthTracksTextView = true`). There is no scroll view, no ruler, no gutter.
`ComposeEditorView`'s diagnostics pane shows line numbers and click-to-jump
works (`characterIndex(for:in:)` → `jumpToCharacter`), but the editor itself
shows no line reference.

## Scope

### Must land

- A **line number gutter** on the left of the text view, updating live as the
  author types.
- Numbers in a **monospaced font** at the editor size (13pt), colored
  `.secondaryLabelColor`.
- The gutter **scrolls vertically with the text** and stays fixed horizontally
  (Xcode-style).
- The currently selected line's number is **highlighted** (bolder or tinted)
  so the cursor position is always visible.
- Gutter width fits 3–4 digits (~9999 lines), minimum ~36pt.
- The gutter is absent on the Compose empty state (no document).

### Nice-to-have (not gate)

- A thin separator between gutter and text.
- Clicking a line number selects that line.

### Must not land

- A hand-rolled overlay that does not track the text view's scroll (the
  number one way this card goes wrong).
- Line numbers in the preview pane.
- A third-party library.

## Implementation sketch

1. **Recommended: an `NSRulerView` subclass attached to the scroll view's
   vertical ruler.** `NSScrollView` tracks ruler views with the content for
   free — no manual scroll math. `LineNumberRulerView` overrides
   `draw(_:)`, enumerates the visible line range from the text view's
   `textContainer`, and draws numbers + the current-line highlight.
2. `ComposeTextView.makeNSView` currently returns a bare `NSTextView` that
   SwiftUI wraps. To attach a ruler you will likely need to build an explicit
   `NSScrollView` in `makeNSView` containing the text view, then set
   `scrollView.verticalRulerView = LineNumberRulerView(textView:)` and
   `scrollView.hasVerticalRuler = true`. Keep the text view's existing
   configuration (width tracking, inset, highlighting) intact.
3. Invalidate on `textDidChange` (line count changed) and on selection change
   (highlight moved). The Coordinator already receives both; forward them to
   the ruler.
4. Draw only the visible range (from `textView.bounds` + `textContainer` line
   fragments) so huge buffers stay cheap.
5. If the ruler approach fights the view (it should not — it is the standard
   path), fall back to a sibling `NSView` overlay that mirrors the scroll
   offset via `NSView.boundsDidChangeNotification` on the clip view. Prefer
   the ruler; it is less code and cannot desync.

## Gate

Open a page in Compose → the gutter shows 1..N aligned with the buffer →
typing adds/removes lines and the gutter updates → moving the cursor
highlights the current line's number → scrolling keeps the gutter aligned →
the gutter is absent on the empty state. `SKIP_EMBED_BORIS=1 make build` +
`make test` green.

## Tests

- `testLineGutterLineCount` — the ruler's line count matches the buffer's
  `NSString` line count (empty buffer → 1).
- `testLineGutterHighlightFollowsSelection` — moving the selection changes
  the highlighted line.
- Manual: gutter scrolls in lockstep; long lines do not wrap in the gutter;
  the paint layer is unaffected.

## Edge cases

- Empty buffer → show line 1.
- CR / LF / CRLF and a leading BOM → use `NSString.lineRange` /
  `lineRange(for:)` so line 1 is not offset by the BOM.
- Very long single lines (no wrap — `widthTracksTextView`) → the gutter
  counts lines, not wrapped visual rows; that is fine and expected.
- The gutter must not touch the text storage (it draws in its own view), so
  it cannot fight the highlighter.
