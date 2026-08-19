# Card LATER-3.4 — Compose depth: Cooklang autocomplete

**Tracker:** [#167](https://github.com/drawmeanelephant/solipsist/issues/167)
· **Lane:** compose (`Sources/Compose/**` single-owner). **Slice order:**
after 3.3.

## Owns

- `Sources/Compose/ComposeEditorView.swift` / `ComposeDocument.swift` —
  the completion UI and insertion path.
- The completion **source** — from `completion.json` / recipe IR only
  (Boris-owned surface; completion is never hand-rolled).

## Do

1. In Cooklang buffers, autocomplete `@ingredient` / `#cookware` / step
   tokens from the corpus's `completion.json` (read-only over the
   selected source's `.boris/` artifacts).
2. Insert completions into the buffer; explicit save stays the only disk
   writer.

## Do not

- Reimplement Cooklang parsing or completion semantics — Boris owns them.
- Spawn a process — the Engine lane owns `Process` (and recipe-scale
  stays the inspector's verb).

## Gate

Typing `@` in a Cooklang buffer suggests corpus ingredients;
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
