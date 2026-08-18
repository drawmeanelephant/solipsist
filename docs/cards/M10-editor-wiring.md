# Card M10-4 — Editor from the selected page

**Milestone:** M10 · **Issue:**
[#102](https://github.com/drawmeanelephant/solipsist/issues/102) ·
**Lane:** Editor wiring. One worktree, one PR against `main`; branch
suggestion `feat/m10-editor-wiring`.

**Merge after [#101](https://github.com/drawmeanelephant/solipsist/issues/101)
is on `main`.** Development may start after #100 (`sourcePath` is on
the type). #101 writes `noun.sourcePath` and lands list gestures.
Design: [`docs/M10-DESIGN.md`](../M10-DESIGN.md).

## Owns

- `Sources/Companions/Editor/` — header shows selected page title +
  `sourcePath`; session stays source-scoped
- File → Edit Page in `Sources/App/Commands.swift` (enable when
  `store.selection.canEditPage`)

## Do not touch

- `Sources/Play/Local/**` (double-click / Return is #101)
- `Sources/Chrome/MainWindow.swift` (Editor toolbar is #100)
- `Sources/Engine/**` beyond existing `editorStart`
- `Sources/Inspector/**` (PageSection already opens the companion)
- A native `NSTextView` / SwiftUI `TextEditor` buffer
- Preview companion internals
- `docs/issues/` (do not draft an editor-open-file issue)

## Why

M6 hosted `boris-editor` as a source-scoped companion. Mail's
compose is about the selected message. Edit ▶, Return, and
double-click on a page should open that page, not just the project.

A14 pinned the launch line (`BORIS_EDITOR_URL=`). There is **no**
fact-checked file-open deep link yet. Do not invent one. If the
hosted shell has no page-open contract, open the session as today
and surface the selected `sourcePath` in the companion chrome
(title / status). There is **no** proven query/fragment. Do not invent one. Do **not**
draft `docs/issues/boris-A*-editor-open-file.md` in this milestone.

## Do

1. File → Edit Page enabled when `store.selection.canEditPage`.
   Menu first. Return / double-click are #101. View → Editor (⌘⇧E)
   stays source-gated.
2. The verb opens the Editor `WindowGroup` and starts the existing
   `EditorSession` for the selected local source.
3. Show the selected page title + `sourcePath` in the companion
   header so the human knows which letter they opened.
4. Keep paste-`BORIS_EDITOR_URL=` and “Open in Browser” as the
   fallback. SIGTERM on close, as today.
5. Link-out remains accepted if WKWebView/CSP fails.

## Do not

- Write a native editor. That card is Later
  ([ROADMAP.md](../ROADMAP.md) §3).
- Parse frontmatter to decide what to open. `sourcePath` on the
  graph node is the path.
- Change token/CSP/loopback rules.
- Block on a Boris deep-link that does not exist.

## Gate

Select a page in `Stunts/happy` (after #101) → File → Edit Page
opens the editor companion with that page's title and `sourcePath`
visible. No source selected / no page → the verb is disabled.
Link-out still works. `SKIP_EMBED_BORIS=1 make build` + `make test`
green.
