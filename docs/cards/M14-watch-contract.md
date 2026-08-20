# M14 — Watch contract (tracker)

**Milestone:** M14 · **Lane:** design (this file) + two child cards.
Does **not** own `Sources/`. Children do.

Parent issue:
[#143](https://github.com/drawmeanelephant/solipsist/issues/143).

## Why

The pin (`6b930b7`) already contains A1 (boris#648): `--watch-json`
emits NDJSON including `serve-started` with `url` / `helper` /
`port`. Preview still regexes the prose port line in
`WatchServer`. The letter (M10-3) loads a URL and reloads only
when `serveURL` changes or the row is re-selected — D-S11
rejected an EventSource client for the M10 gate.

Contracts we have and do not consume are debt.

## Children

Engine is single-owner. M14-2 starts after M14-1.

| Card | Issue | Lane | Gate (short) |
|------|-------|------|----------------|
| [M14-1 A1 consume](M14-a1-consume.md) | [#147](https://github.com/drawmeanelephant/solipsist/issues/147) | Engine + Preview | `--watch-json` / `serve-started` is how we learn the port |
| [M14-2 Letter SSE](M14-letter-sse.md) | [#148](https://github.com/drawmeanelephant/solipsist/issues/148) | Reading | letter reloads on `event: reload`; no second watch |

## Not this tracker

- A5 `validate --watch` (boris#647 → shipped as #161 / PR #199)
- A15 `open=` (app already appends it; pin-follow)
- A second `Process` or a second watch session
- M13 trunk folders
- Growing #110 / #111
- `file://` preview
