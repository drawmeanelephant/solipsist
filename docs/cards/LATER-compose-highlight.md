# Card LATER-3.2 — Compose depth: incremental highlight

**Tracker:** [#167](https://github.com/drawmeanelephant/solipsist/issues/167)
· **Lane:** compose (`Sources/Compose/**` single-owner). **Slice order:**
after 3.1 (diagnostics) — both touch the same repaint path.

## Owns

- `Sources/Compose/ComposeHighlighter.swift` — the heuristic rule engine
  (regex rules, region rules painted last).
- `Sources/Compose/ComposeEditorView.swift` — the repaint path
  (`NSTextView` host, repaint-on-edit).

## Do

1. Repaint only the **visible range** (and the changed region) instead of
   the whole buffer on every keystroke.
2. Keep the existing rule tables and the not-a-parse contract in the file
   header — this is a performance slice, not a grammar change.

## Do not

- Rewrite the highlight rules or add grammar semantics.
- Touch `Sources/Engine/**`.

## Gate

Editing a large buffer no longer repaints text off-screen; highlight
paint contract tests stay green. `SKIP_EMBED_BORIS=1 make build` +
`make test` green.
