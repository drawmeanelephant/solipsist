# Card M14-2 — Letter reloads on existing SSE

**Milestone:** M14 · **Issue:**
[#148](https://github.com/drawmeanelephant/solipsist/issues/148)
(parent [#143](https://github.com/drawmeanelephant/solipsist/issues/143))
· **Lane:** Reading. One worktree, one PR against `main`;
branch suggestion `feat/m14-letter-sse`.

Merges **after** M14-1. Needs a trustworthy `serveURL`.

## Owns

- The reading pane (Pages letter) in `Sources/Play/Local/`
- An EventSource client **against the existing watch helper**,
  or a WK reload triggered by that channel — one session,
  already started by PlayHost / Preview

## Do not touch

- `WatchServer` argv / Engine start line (M14-1)
- `MainWindow.swift`
- Sidebar / M13
- A second `boris watch`

## Why

M10 D-S11: the letter does not subscribe to SSE. It reloads when
`serveURL` changes or the user re-selects the row. After a save
the companion helper reloads and the letter stays stale until you
click again. Users will feel that gap. This card is the named
add-on.

## Do

1. When watch is up and the letter is showing the served page,
   reload that WKWebView on `event: reload` from the existing
   helper (`/__boris/events` or whatever A1 + `--serve` already
   publish). Probe the pin; do not invent a second channel.
2. Root mismatch (`isBound(to:)`) still means idle — do not
   reload a foreign helper.
3. 404 / load failure stays in-pane summary. No `file://`. No
   Swift Markdown.
4. Preview companion keeps its own WKWebView. Two views, one
   server.
5. Tests: a fixture event triggers the reload hook; a bound-root
   mismatch does not. No live watch in CI.

## Do not

- Spawn a second watch.
- Parse `--watch-json` NDJSON in Play (Engine already did that).
- Subscribe when watch is down.
- Change how Preview starts or stops the session.

## Gate

With watch up, save a page (or inject `event: reload`) → the
letter reloads without re-selecting the row. Source switch still
treats a foreign helper as idle. `SKIP_EMBED_BORIS=1 make build`
+ `make test` green.
