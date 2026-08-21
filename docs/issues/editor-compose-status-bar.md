# Editor: Compose Status Bar — Cursor Position + Word Count

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#228](https://github.com/drawmeanelephant/solipsist/issues/228)
**Lane:** `Sources/Compose/`

## Problem

The Compose status bar shows filename / language / frontmatter / dirty state
but no **cursor position** (line:column) or **word / character count** —
standard expectations for long-form editing and word-limit matching.

## Verified current state

`ComposeWindow.statusBar` (a `.safeAreaInset(edge: .bottom)` in
`Sources/Compose/ComposeWindow.swift`) renders `document.statusText`
(filename, language, frontmatter, dirty), a `saveStatus`, and the
coordinator summary. Cursor position is not tracked; word count is not
computed. `ComposeDocument` (`Sources/Compose/ComposeDocument.swift`) is an
`@Observable` class with `text`, `language`, `isDirty`, `statusText`.

## Scope

### Must land

- **Line:Column** in the status bar, updated on every cursor movement.
  Format `Ln 12, Col 45` (Xcode-style).
- **Word count**, updated on text change. Format `1,234 words`.
- **Character count** as a secondary stat: `5,678 chars`.
- Stats are **right-aligned**, opposite the save status.
- Stats are absent on the Compose empty state (no document).

### Nice-to-have (not gate)

- **Selection character count**: with text selected, show `42 selected`
  alongside the total.
- **Reading-time estimate**: `~5 min read` at ~200 wpm.
- Clicking the line:column opens the **Go to Line** sheet — that is
  [#238](https://github.com/drawmeanelephant/solipsist/issues/238); do not
  build it here.

### Must not land

- A popover or tooltip — the stats live in the status bar (Mail / Xcode).
- A third-party word-count library. `NSString.enumerateSubstrings` with
  `.byWords` is sufficient.

## Implementation sketch

1. **Track the selection.** `ComposeDocument` is `@Observable`, so add a plain
   stored property `var selection: NSRange = NSRange(location: 0, length: 0)`
   and update it from the Coordinator's `textViewDidChangeSelection(_:)`
   (add the delegate method to `ComposeTextView.Coordinator`). `@Observable`
   publishes plain properties — do not use `@Published` (that is
   `ObservableObject`).
2. **Line:Column** is computed in the status bar from `document.selection` +
   `document.text` via `NSString.lineRange(for:)` (UTF-16 offsets; the buffer
   is `String`, convert with `as NSString`).
3. **Word count** is computed on text change, not per keystroke in the view.
   The Coordinator's `textDidChange` already runs per edit — compute
   `document.wordCount` there with `NSString.enumerateSubstrings(... .byWords)`
   and store it. If profiling shows a large buffer is slow per keystroke,
   debounce to ~100ms (out of the gate).
4. In `ComposeWindow.statusBar`, add the right-aligned stats beside/over the
   existing `saveStatus`:
   ```swift
   Spacer()
   Text("Ln \(line), Col \(col)")
   Text("\(wordCount) words")
   Text("\(charCount) chars")
   ```
   `.font(.caption.monospacedDigit()).foregroundStyle(.secondary)`.

## Gate

Open a page in Compose → the status bar shows `Ln 1, Col 1` and `0 words` →
arrow keys / clicking update Ln/Col live → typing updates the word and
character counts → the stats are right-aligned and absent on the empty state.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testWordCountUpdatesOnInsert` / `OnDelete` — inserting/deleting a word
  changes `document.wordCount`.
- `testWordCountHandlesMultipleSpaces` — consecutive spaces do not create
  words.
- `testCursorPositionUpdatesOnNavigation` — moving the selection updates
  `document.selection`; the computed Ln/Col matches.
- `testCursorPositionAtEndOfLine` — typing at a line end increments Col.

## Edge cases

- Empty buffer → `0 words`, `Ln 1, Col 1`.
- Very long lines → word count stays cheap (see debounce note).
- CR / LF / CRLF and a leading BOM → `lineRange(for:)` handles line endings;
  verify the BOM does not offset column 1.
- Stats must not render when the Compose window has no document (empty state).
