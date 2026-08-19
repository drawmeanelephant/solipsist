# Card LATER-3.3 — Compose depth: front-matter form

**Tracker:** [#167](https://github.com/drawmeanelephant/solipsist/issues/167)
· **Lane:** compose (`Sources/Compose/**` single-owner). **Slice order:**
after 3.2.

## Owns

- `Sources/Compose/ComposeEditorView.swift` (or a new
  `ComposeFrontmatterForm.swift` in `Sources/Compose/`) — the form section.
- `Sources/Compose/ComposeDocument.swift` — read/write of the front-matter
  block on **explicit save only**.

## Do

1. A form over the **closed 8-key grammar** (`id`, `parent`, `title`,
   `role`, `status`, `tags`, `relations`, Cooklang `servings`) —
   `boris-frontmatter-1.schema.json` is the authority; every other key is
   `EFRONTMATTER` and is not offered.
2. Write-back overlays the existing front matter (never destroys unknown
   keys the form doesn't edit).
3. The compose window's save seam is the only writer (boundary 4).

## Do not

- Invent keys or a second vocabulary.
- Parse frontmatter in Swift beyond the existing boundary scanner —
  Oliver owns the pre-pass.
- Touch `Sources/Models/**` contracts.

## Gate

Editing the form and saving updates the buffer's front matter; unknown
keys survive. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
