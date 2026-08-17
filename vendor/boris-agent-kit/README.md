# Boris Agent Kit — archived pin (metadata only)

The original `boris-agent-kit/` folder (a sibling of this repo) was a
**temporary transport artifact** — a set of 10 prebuilt Darwin-arm64
binaries handed off for agent work. It may not exist in future
environments. **The binaries are not committed here**; what this folder
preserves is the *pin* — the exact provenance and SHA-256 fingerprints of
that kit — so work off the branch never depends on a folder that could
vanish.

## What's here

- `MANIFEST.json` — the kit's own manifest (verbatim): commit
  `b82e9e2eace74d9ca61df23dffc1329d2a2fe628`, branch
  `freebuff/agent-pack`, platform `Darwin-arm64`, Zig 0.16.0, `dirty: false`,
  per-binary sha256.
- `SHA256SUMS` — the kit's checksum file (verbatim), verified clean on
  2026-08-17 (`shasum -a 256 -c` → all OK).

## The pinned engine

| Field | Value |
|-------|-------|
| Commit | `b82e9e2` (`boris/0.8.1`, afterparty integration line) |
| Engine binary sha256 | `12c8cd450c4fffb47b9cb92e2468071769a6d4c13a28a961231b1b69e1555abd` |
| Behavior | verified identical to the source build on every probed contract; M1 spike passes via `SOLIPSIST_BORIS_BIN` |

## Reproducing the binaries (if the kit is gone)

The kit was built from the pinned commit. The engine and the toolchain
binaries rebuild from the boris source checkout at that commit:

```bash
cd <boris-repo>          # checkout at b82e9e2
zig build               # installs: boris, boris-source-rag, boris-package, boris-job-runner
# the standalone tools each build from their own build.zig:
zig build --build-file tools/search-index/build.zig       # boris-search-index
zig build --build-file tools/content-audit/build.zig      # boris-content-audit
zig build --build-file tools/github-pages-audit/build.zig # boris-github-pages-audit
zig build --build-file tools/docs-maintenance/build.zig   # boris-docs-maintenance
zig build --build-file tools/migration-lab/build.zig      # boris-migration-lab
zig build --build-file tools/scale-smoke/build.zig        # boris-scale-smoke
zig build --build-file tools/testdata-generator/build.zig # boris-testdata
```

Note: a locally rebuilt binary will have a **different sha256 than the
kit** (build-config differences — the kit was a specific release build),
but behavior is what's pinned and verified. When you have a rebuilt
`bin/boris`, point the app at it via `SOLIPSIST_BORIS_BIN` or the
`../boris/zig-out/bin/boris` fallback — the engine location order in
`agents.md` covers both.

Full review and probe results: [`docs/AGENT-KIT-REVIEW.md`](../docs/AGENT-KIT-REVIEW.md).
