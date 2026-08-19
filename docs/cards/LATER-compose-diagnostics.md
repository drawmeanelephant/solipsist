# Card LATER-3.1 — Compose depth: Oliver span diagnostics

**Tracker:** [#167](https://github.com/drawmeanelephant/solipsist/issues/167)
· **Lane:** compose (`Sources/Compose/**` is single-owner — one worktree,
one PR, one slice at a time). **Slice order:** first.

## Owns

- `Sources/Compose/ComposeEditorView.swift` — the `ComposeDiagnostic` seam
  and `ComposeDiagnosticsPane` already exist and render **empty** by
  design; this slice wires them up.
- `Sources/Compose/OliverRenderService.swift` — mapping Oliver's
  structured diagnostics (exact source spans) into `ComposeDiagnostic`.
- `Sources/Engine/OliverRenderer.swift` — **additive only**: expose
  diagnostics from the render result (the Engine boundary stays single-owner).

## Do

1. Oliver diagnostics carry **exact spans** (per the M10 review: "the
   problems seam is a span-based model, not a line list"). Map them into
   `ComposeDiagnostic` (severity / line / message) with source spans.
2. **Click-to-line**: clicking a diagnostic moves the `NSTextView`
   selection to the span.
3. Surface render-time diagnostics on save/preview, never swallowed.

## Do not

- Parse in Swift — Oliver owns the grammar (D11); the highlighter is
  heuristic paint, not a parse.
- Touch the other compose slices' seams ahead of them.
- Grow `Sources/Chrome/MainWindow.swift`.

## Gate

A broken buffer shows the diagnostic in the compose problems pane with
click-to-line. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
