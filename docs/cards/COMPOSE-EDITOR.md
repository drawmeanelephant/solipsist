# Card COMPOSE-1 — Native compose editor element (Markdown / Textile / Cooklang)

**Milestone:** depth (post-M9) · **Lane:** compose (new) · **Reference:**
[Oliver](https://github.com/drawmeanelephant/oliver) · **Issue:**
[#106](https://github.com/drawmeanelephant/solipsist/issues/106) (filed as
off-roadmap "Later" per the M10 parent #98) · **Branch suggestion:**
`compose/editor-element`

**Status:** ✅ phase 1 (the element) landed — `Sources/Compose/` builds
into the app and `make test` covers language detection, the front-matter
boundary, per-language paint, and the render seam. ✅ **hook-in landed** —
a `Compose` window (`⌘⇧C`, `ComposeWindow.swift`) is registered, sourced
from the selected page via the published graph contract, saves under the
source's security-scoped bookmark, and flows each successful save into the
coordinator's save→validate gate (`noteSave()`). ✅ **Oliver-backed preview
landed** — `OliverRenderer` (Engine lane, reuses `BorisRunner`, so only the
Engine spawns processes) renders buffers through `oliver render --from …`
with options mirroring Oliver's `ParseOptions`; the compose preview is
debounced, cancellation-terminates the child, and surfaces render errors
(renderer not found → actionable message). End-to-end render tests run when
`SOLIPSIST_OLIVER_BIN` is set and skip in CI. Remaining phases below
(diagnostics mapping, depth) are future cards.

**One sentence:** build a full-featured Markdown / Textile / Cooklang
compose surface as a **standalone element** (`Sources/Compose/`), with
Oliver — the rendering engine behind Boris — as the language reference, and
hook it into the app in a later card. It is a big undertaking; this card is
phase 1 (the element itself) and the record of the whole shape.

## Why this card exists — and what it amends

`HARNESS.md` and `ROADMAP.md` carry the rule "if you are about to write a
Markdown editor, a graph algorithm, a frontmatter parser, or an HTTP server —
stop" and "v1 must not: a from-scratch native editor or frontmatter parser."
This card **amends both, in writing, for this lane only**:

- The compose window is **authoring chrome** — Mail's compose analog, the
  one surface Boris's hosted `boris-editor` (a browser surface) does not give
  us as a native Mac citizen. We are not reimplementing compiler semantics;
  we are authoring a buffer and previewing it.
- **Oliver pins the language contract.** Every behavior the editor touches
  (block/inline syntax, extensions, front matter boundary, diagnostics) is
  already decided, tested, and documented in Oliver. We mirror that surface;
  we never invent a grammar. Highlighting is heuristic paint, explicitly not
  a parse — the parse stays in Oliver/Boris.
- **The element is built standalone first.** Nothing in phase 1 wires it into
  `SolipsistApp`, `MainWindow`, menus, or the selection store. The "one
  window" posture is untouched until the hook-in card lands.

## Reference — Oliver's language support (reviewed 2026-08-18)

Oliver is a clean-room Zig markup library: Markdown / Textile → a normalized
typed document → deterministic HTML/XHTML; Cooklang → its own typed `Recipe`
model → an Oliver-owned HTML policy. Filesystem, templates, site graphs, and
publication do not live there — consumers (Boris) build around it.

### Frontends at a glance

| Frontend | Parses into | Oliver entry | Conformance wall |
|----------|-------------|--------------|------------------|
| Markdown | shared `document.Document` | `oliver.parse(…, .markdown, …)` | CommonMark 0.31.2 — **652/652** byte-for-byte |
| Textile | shared `document.Document` | `oliver.parse(…, .textile, …)` | Textile fixture wall fully green (`TEXTILE-PARITY.md`) |
| Cooklang | typed `Recipe` (own model) | `oliver.cooklang.parse(…)` | canonical corpus **60/60** (`docs/COOKLANG.md`) |

### Markdown — full CommonMark 0.31.2 plus Oliver's opt-in extensions

- **Blocks:** paragraphs, ATX + Setext headings, thematic breaks, fenced and
  indented code blocks (tab-stop indentation, literal content), all seven HTML
  block types, block quotes, tight/loose lists with nesting, link reference
  definitions (§4.7, full/collapsed/shortcut resolution), GFM pipe tables.
- **Inlines:** the complete emphasis/strong rule set (mod-3, openers_bottom),
  code spans (run-length matching), inline + reference links and images,
  URI/email autolinks, raw HTML, hard/soft line breaks, backslash escapes,
  full WHATWG entity table (§2.5).
- **Extensions (all off by default):** Pandoc footnotes, definition lists,
  heading attribute lists + GFM auto heading ids, strikethrough, task lists,
  Obsidian `[[wikilinks]]`, `> [!note]` callouts, smart typography.
- **Front matter:** shared pre-pass (`src/frontmatter.zig`) — YAML `---` /
  TOML `+++` sniffed at index 0, stripped before dispatch, parsed into a
  bounded subset or kept raw with a `frontmatter-parse-unsupported`
  diagnostic. An unclosed opener passes through with
  `unclosed-frontmatter` — never faked.

### Textile — the documented Textile 2 surface

- **Blocks:** `p.`/`h1.`–`h6.`/`bq.` signatures with the full block-attribute
  set (`{style}[lang](class#id)` alignment/padding), `bc.`/`pre.` code blocks,
  `*`/`#` lists with nesting, `dl.` definition lists, `|a|b|` tables with cell
  modifiers/colspan/rowspan and `table<mods>.` signatures, footnotes (`[N]` +
  `fnN.`), `clear.`, `==` escaping, `notextile.` raw passthrough, extended
  `bq..`/`bc..`/`pre..` blocks, line attributes (`|mods|.`), `bq.:URL` citations.
- **Inlines:** the phrase family (`_x_ *x* __x__ **x** -x- +x+ ^x^ ~x~ %x%
  ++x++ --x-- ??x?? ABC(def)`) with phrase attributes on every operator,
  `@code@`, links (`"text":url`, titles, the bracket trick, link aliases),
  images (`!url!` with alt/title/alignment/size modifiers), `==…==` inline
  escaping, the character replacements (curly quotes, dashes, ellipsis,
  symbols, `{...}` character macros), Unicode boundary rules.
- **Front matter:** same shared pre-pass as Markdown.

### Cooklang — a typed Recipe, not prose markup

- **Model:** ingredients (`@name`, `@multi word{quantity%unit}`, shorthand
  preparations), cookware (`#name{…}`), timers (named/unnamed, quantity+units
  kept as source text), steps with forced line breaks, `--` / `[- -]`
  comments, `> ` notes, `= ` sections, recipe references (`@./path`, parsed
  never resolved), YAML front-matter boundary (raw payload, never faked).
- **Derived operations** (Boris/Boris's consumers own these; the editor's
  future recipe-scale pane mirrors them): canonical serialize, exact-rational
  scale by factor/servings, `.menu` day/meal view, deterministic HTML policy
  (ingredients index, `<time>` timers, section-aware layout).
- **Diagnostics:** structured, exact source spans — the compose problems seam
  maps to this shape.

### What the review means for the editor

1. **Three distinct language surfaces** — the element must own three
   highlighters, not one grammar with flags (Cooklang is not Markdown with
   `@`).
2. **The front matter boundary is a first-class construct** in all three —
   sniffed at index 0, never parsed, never content.
3. **Diagnostics carry exact spans** — the problems seam is a
   span-based model, not a line list.
4. **Extensions are opt-in per profile** — the compose window can expose the
   extension surface (wikilinks/callouts/smartypants/…) the way Oliver's
   `ParseOptions` does, so authors see exactly what their profile renders.

## Owns

- `Sources/Compose/**` — new lane (language model, buffer, highlighter,
  editor element, render seam). Lane is single-owner: one worktree, one PR.
- `Project.yml` — add the lane to the app target; add the three
  Foundation-only files (`ComposeLanguage.swift`, `ComposeDocument.swift`,
  `ComposeHighlighter.swift`) to `ContractTests`.
- `Tests/ContractTests/Compose{Language,Document,Highlighter,Preview}Tests.swift`.

## Do (phase 1 — the element, standalone)

1. **`ComposeLanguage`** — markdown / textile / cooklang with extension
   detection, advisory content sniffing, and the Oliver conformance notes.
   Language is auto-detected until pinned; the picker's choice is never
   overridden mid-session.
2. **`ComposeDocument`** — observable buffer (text, language, `fileURL`,
   dirty flag), the front-matter boundary scanner (Oliver's sniff-then-strip
   rule; unclosed openers are not front matter), and an **explicit-only**
   `save()` seam (boundary 4: nothing writes to disk but an explicit save).
3. **`ComposeHighlighter`** — `NSAttributedString` token paint per language,
   rule tables derived from Oliver's documented surface (see review). Painted
   last: regions (fenced/indented code) and front matter, so data stays gray
   and code stays code. Comments paint over tokens in Cooklang. Heuristic by
   contract — documented as not-a-parse in the file header.
4. **`ComposeEditorView`** — the element: `NSTextView` host with live
   highlighting (repaint-on-edit, typing attributes restored), language
   picker, preview split, explicit Save (⌘S, disabled when clean), and a
   span-based diagnostics seam.
5. **`ComposePreview`** — the `MarkupRenderService` protocol + placeholder
   (HTML-escaped, NUL → U+FFFD, same escape policy as Oliver's text writer).
   The Oliver-backed implementation is **not** phase 1: Solipsist's Engine
   lane owns subprocesses, so it lands with the hook-in card as an Engine
   seam (`renderMarkup`) or a C-ABI embed decision.
6. **Tests** — pin detection, front-matter boundary, per-language paint, and
   render escaping, in the house contract-test style.

## Do not (phase 1)

- Wire into `SolipsistApp.swift`, `MainWindow`, `Commands.swift`, the
  selection store, or any menu (that is the hook-in card).
- Touch `Sources/Engine/**`, `Sources/Companions/**`, `Sources/Chrome/**`,
  `Sources/Play/**`, `Sources/Inspector/**`, `Sources/Workspace/**`.
- Spawn any process. The Engine lane owns `Process`.
- Implement parse semantics or a frontmatter parser — Oliver is the
  reference; we highlight and buffer, we do not compile.
- Use `WKWebView` in the element. The preview is a sandboxed HTML fragment
  view; the `watch --serve` companion posture belongs to the hook-in card.
- Touch the `boris` repo or `docs/issues/`.

## Later — hook-in phases (own cards, do not start)

1. **Hook-in** ✅ landed: `ComposeWindow` registers the window, sources the
   buffer from the selected `page` noun (file resolved via `graph.json`,
   `ComposePageResolver`), reads/writes under the local source's
   security-scoped bookmark, and calls `coordinator.noteSave()` after an
   explicit save so the debounced validate gate runs — the same posture as
   the hosted editor's save. Dirty-buffer page switches confirm before
   discarding.
2. **Oliver-backed preview** ✅ landed: `OliverRenderer` in the Engine lane
   (subprocess via `BorisRunner`, cancellation-terminates the child),
   located via `SOLIPSIST_OLIVER_BIN` → app bundle `Resources/oliver` →
   sibling of the boris binary → dev checkouts. Extension flags, `--to
   xhtml`, `--raw-html`, and `--frontmatter` mirror Oliver's `ParseOptions`;
   the compose window's Render Options menu exposes them. Bundling `oliver`
   next to `boris` (embed script) and a C-ABI embed decision remain open.
3. **Diagnostics:** map Oliver's span-based diagnostics into the problems
   seam; click-to-line.
4. **Depth:** incremental (visible-range) highlighting, selection-aware
   paint, front-matter form editor, Cooklang ingredient autocomplete /
   recipe-scale pane, find & replace, per-profile extension surface.

## Gate

`SKIP_EMBED_BORIS=1 make build` + `make test` green. The element compiles
into the app target (it is not shown anywhere yet); the tests cover language
detection, the front-matter boundary, per-language highlight paint, and the
render seam for all three frontends. Card body = this file; no silent
contradiction with HARNESS — the amendment is written here.
