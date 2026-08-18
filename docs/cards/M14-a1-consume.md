# Card M14-1 — Consume A1 `--watch-json`

**Milestone:** M14 · **Issue:**
[#147](https://github.com/drawmeanelephant/solipsist/issues/147)
(parent [#143](https://github.com/drawmeanelephant/solipsist/issues/143))
· **Lane:** Engine + Preview. One worktree, one PR against `main`;
branch suggestion `feat/m14-a1-consume`.

## Owns

- `Sources/Engine/WatchServer.swift` — argv + how `onServe` fires
- Engine watch start if the flag is assembled outside `WatchServer`
- `Sources/Companions/Preview/` only as far as it reads `serveURL`
  / the helper URL (do not restyle the window)
- Decode of the A1 event line (Engine or Models — additive
  Codable only; do not rewrite IR types)

## Do not touch

- Reading pane / Play list internals (M14-2)
- `WatchServer` as a second session
- `MainWindow.swift`
- Settings / M13 sidebar
- `Project.yml`

## Why

`WatchServer` today parses:

```
preview: http://127.0.0.1:PORT/  (auto-reload helper: http://127.0.0.1:PORT/__boris/)
```

A1 replaced that contract. The pin has the flag. We still sniff
prose.

## Do

1. Pass `--watch-json` on `watch --serve`. Keep `--port 0` and
   `--input`. stderr is NDJSON; do not expect the old preview
   line when the flag is on.
2. Fire `onServe` from a `serve-started` event (`helper` URL,
   same helper the web view already loads). Handshake
   `hello.watch_events_schema` — unknown version degrades (D8),
   no crash.
3. Port regex becomes fallback for a binary that rejects the
   flag, then **dies in this PR** if the pinned kit is honest.
   Do not leave two parsers “just in case” after you have
   probed the pin.
4. Surface `build-failed` / unexpected `watch-stopped` the way
   we already surface a non-zero watch exit. Do not swallow.
5. Tests: fixture NDJSON lines decode; a `serve-started` helper
   URL is accepted; unknown `watch_events_schema` does not
   crash. No live `watch` in CI.

## Do not

- Subscribe the letter to SSE (M14-2).
- Change `WatchServer` into two processes.
- Reimplement the SSE browser channel. That stays served.
- File a new boris issue unless the pin’s `--watch-json` does
  not match `docs/issues/boris-A1-watch-events.md` — then draft,
  do not patch boris.

## Gate

Preview ▶ starts with `--watch-json`. The helper URL comes from
`serve-started`. Stop still SIGTERMs. `SKIP_EMBED_BORIS=1 make
build` + `make test` green.
