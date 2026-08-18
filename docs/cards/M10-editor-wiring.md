# Card M10-4 — Editor from the selected page

**Milestone:** M10 · **Issue:**
[#102](https://github.com/drawmeanelephant/solipsist/issues/102) ·
**Lane:** Editor wiring. One worktree, one PR against `main`; branch
suggestion `feat/m10-editor-wiring`.

May overlap [#101](https://github.com/drawmeanelephant/solipsist/issues/101)
if it only keys off `noun.kind == "page"`.

## Owns

- `Sources/Companions/Editor/` — open against the selected page when
  the launch contract allows
- Edit verb in `Sources/App/Commands.swift` and the toolbar button
  in `Sources/Chrome/MainWindow.swift` (enable/disable only; do not
  grow the window)
- Double-click / Return on a Pages row in
  `Sources/Play/Local/LocalPlay.swift` (one action, not a new list)

## Do not touch

- `Sources/Engine/**` beyond existing `editorStart`
- `Sources/Inspector/**` (PageSection already has an open-editor
  control; leave it or point it at the same verb)
- A native `NSTextView` / SwiftUI `TextEditor` buffer
- Preview companion internals

## Why

M6 hosted `boris-editor` as a source-scoped companion. Mail's
compose is about the selected message. Edit ▶, Return, and
double-click on a page should open that page, not just the project.

A14 pinned the launch line (`BORIS_EDITOR_URL=`). There is **no**
fact-checked file-open deep link yet. Do not invent one. If the
hosted shell has no page-open contract, open the session as today
and surface the selected `sourcePath` in the companion chrome
(title / status). If you can prove an existing query/fragment the
Svelte shell already honors, use that. If Boris needs a contract,
draft `docs/issues/boris-A*-editor-open-file.md` against afterparty
and stop — do not patch boris.

## Do

1. File → Edit Page (or Edit) enabled when `noun.kind == "page"`.
   Keyboard: Return in the Pages list; double-click a row. Menu
   first.
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

Select a page in `Stunts/happy` → Edit ▶ / double-click opens the
editor companion with that page's title and `sourcePath` visible.
No source selected / no page → the verb is disabled. Link-out still
works. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
