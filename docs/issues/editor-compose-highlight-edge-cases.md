# Editor: Compose Highlighting Edge Cases

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#235](https://github.com/drawmeanelephant/solipsist/issues/235)
**Lane:** `Sources/Compose/`

## Problem

The heuristic highlighter (`ComposeHighlighter`) has edge cases where the
paint layer produces inconsistent results. These are not parser bugs (the
grammar lives in Oliver) but visual regressions that make the editor feel
unpolished.

## Verified current state

`ComposeHighlighter` (`Sources/Compose/ComposeHighlighter.swift`) applies
ordered regex rules over the whole buffer; later rules repaint over earlier
ones; front matter is painted last. Incremental repaint
(`repaintChanged` in `ComposeTextView`) restyles only the changed line(s).
Relevant rules today:

- Inline code: `#"`[^`\n]+`"#` (single-line only).
- Emphasis family: `***`/`___` first, then `**`/`__` with `(?<![*_])` /
  `(?![*_])` guards, then single `*`/`_`.
- Autolink: `#"<[^<>\s]+>"#` (paints the brackets too).
- HTML comments: **no rule**.
- Cooklang notes: `#"^>[ \t]?[^\n]*"#` (per-line).
- Markdown fenced code already uses `dotMatchesLineSeparators`.

## Method — test first, then fix

For **each** item below: write the failing test in `ComposeHighlighterTests`
first, confirm it fails on the current rules (proving the bug is real), then
fix. Some items listed in the draft may already be handled by the existing
lookbehind guards — a failing test is the only honest way to know, and it
prevents "fixing" a non-bug.

## Scope — must land (each gated on a failing test)

1. **Bold/italic inside code spans** — `**bold**` inside backticks should stay
   code-green. The inline-code rule paints first (it is earlier in the array)
   but the strong rule repaints over it. Verify the ordering actually loses;
   the region fenced-code rule already wins because it paints later.
2. **Multi-line / unclosed backtick runs** — the `[^\n]` code rule stops at a
   newline, so a backtick run that wraps lines paints inconsistently. Per
   CommonMark, backtick code spans do **not** span lines — so the correct
   outcome may be "leave the wrapped run unpainted / paint only the valid
   single-line span," not "match across lines." Pin the decision with a test
   and the rule comment.
3. **Nested emphasis** — `***bold and italic***` should paint uniformly.
   Verify whether the `(?<![*_])` / `(?![*_])` guards already prevent the
   inner `**` rule from repainting (they likely do). If the test passes
   already, drop the item and say so in the PR — do not churn the rules.
4. **Autolink brackets** — `<https://x.dev>` paints the angle brackets
   link-blue; the URL is the link, the brackets are not. Fix the rule to paint
   only the inner URL (or add a follow-up rule that re-paints the brackets
   plain).
5. **HTML comments** — `<!-- comment -->` is unpainted. Add a comment rule
   (`.secondaryLabelColor`, italic) placed **before** the inline rules so
   inner markup does not repaint it.
6. **Cooklang multi-line notes** — consecutive `> note` lines paint the
   marker but not the whole block. Extend the note rule to match a run of
   consecutive `>` lines (anchored), or accept per-line paint if that is the
   intended shape — pin with a test.
7. **Front matter with YAML block scalars** — `title: |` + indented lines
   inside `---` must stay gray (front matter is painted last, so verify the
   last-paint already wins; the draft claims a `#` inside the block repaints
   as a heading — confirm with a failing test).

### Nice-to-have (not gate)

8. Diff highlighting (added/removed gutter marks on load).
9. Bracket matching (highlight the matching `(`/`[`/`{`).
10. Current-line highlight (subtle background tint).

### Must not land

- A full AST parser (the grammar lives in Oliver).
- A tree-sitter integration (separate project scope).
- A third-party highlighting library.

## Implementation sketch

- **Code-span priority**: the cleanest fix for #1/#2 is a two-pass order where
  code spans are found and painted, then inline rules are blocked inside them
  (the existing region rules already do this by painting last). Prefer that
  over adding `dotMatchesLineSeparators` to the inline code rule (which would
  violate CommonMark).
- **HTML comments**: `rule(#"<!--[\s\S]*?-->", comment, dotMatches: true)`
  placed before the inline family.
- **Cooklang notes**: `rule(#"(?:^>[^\n]*\n?)+", note, anchors: true,
  dotMatches: true)` — or keep per-line paint if the test says that is fine.
- **Incremental repaint**: multi-line fixes interact with `repaintChanged`,
  which only repaints the changed line(s). A multi-line rule that crosses the
  edited line needs the repaint range expanded to the full rule match (or a
  full repaint on that edit). Keep the incremental path honest — do not
  silently fall back to full repaints that regress LATER-3.2.

## Gate

Each must-land item has a **failing test that starts passing** after the fix
(`make test` green, no regressions in `ComposeHighlighterTests`). A painted
`Stunts/happy` file shows consistent code-span, emphasis, autolink, comment,
and front-matter paint. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testCodeSpanSuppressesBold` — `**bold**` inside backticks stays code.
- `testWrappedBacktickRunPaintedConsistently` — the pinned behavior for a
  wrapped run (likely: only the valid single-line span is code).
- `testNestedEmphasisPaintedConsistently` — `***bold italic***` uniform (may
  pass already — confirm).
- `testAutolinkBracketsNotPainted` — `<https://x.dev>` paints only the URL.
- `testHTMLCommentPaintedAsComment` — `<!-- c -->` is `.secondaryLabelColor`.
- `testCooklangMultiLineNotePainted` — consecutive `>` lines paint as notes.
- `testFrontMatterBlockScalarNotPaintedAsHeading` — `#` inside a block scalar
  stays gray.

## Edge cases

- The code-span fix must not break the incremental repaint (multi-line regions
  need the repaint range expanded, not a full repaint).
- The HTML comment rule must not match `--` inside fenced code blocks (region
  rules paint last and win — verify).
- The Cooklang note rule must not swallow `>` in Markdown blockquotes — the
  language is Cooklang, not Markdown, so this is not a conflict, but verify.
