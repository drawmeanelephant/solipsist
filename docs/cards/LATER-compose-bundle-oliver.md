# Card LATER-3.5 — Compose depth: bundle `oliver` next to `boris`

**Tracker:** [#167](https://github.com/drawmeanelephant/solipsist/issues/167)
· **Lane:** ship / build (`scripts/` + `Project.yml` only) — **parallel
with the compose slices**, different lanes, no file overlap.

## Owns

- `scripts/embed-boris.sh` — extend to also embed `oliver` into
  `Resources/oliver`.
- `Project.yml` — embed step wiring if needed.
- `Sources/Engine/OliverBinary.swift` — the locate order already checks
  `Resources/oliver`; verify, don't rewrite.

## Do

1. Embed `oliver` next to `boris` (same universal/lipo + codesign path),
   so the release app ships the compose preview renderer.
2. Keep `SKIP_EMBED_BORIS=1` honored and the existing boris embed path
   byte-identical.
3. Note: `oliver` is **not** in the boris agent kit — source it from the
   oliver repo build (`../oliver/zig-out/bin/oliver`) or a kit that
   ships it; record the provenance in the script comment.

## Do not

- Touch `Sources/Compose/**` or `Sources/Engine/**` beyond a locate-order
  verify.
- Break the B3-4 entitlements matrix (`Project.yml`).

## Gate

A built app bundle contains `Resources/boris` **and** `Resources/oliver`
when the sources are present; the compose preview renders without
`SOLIPSIST_OLIVER_BIN`. `SKIP_EMBED_BORIS=1 make build` + `make test`
green (embed-skipped path unchanged).
