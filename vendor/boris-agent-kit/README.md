# Boris Agent Kit — archived pin (metadata only)

The original `boris-agent-kit/` folder (a sibling of this repo) was a
**temporary transport artifact** — a set of 10 prebuilt Darwin-arm64
binaries handed off for agent work. It may not exist in future
environments. **The binaries are not committed here**; what this folder
preserves is the *pin* — the exact provenance and SHA-256 fingerprints of
that kit — so work off the branch never depends on a folder that could
vanish.

## What's here

- `MANIFEST.json` — commit `6b930b7bd35a1803b365a073c226df22631dc3f7`,
  branch `afterparty`, platform `Darwin-arm64`, Zig 0.16.0, `dirty: false`,
  per-binary sha256. Engine sha256 is a local `zig build` of that commit;
  the other nine fingerprints remain the archived `b82e9e2` kit (those
  tools were not rebuilt for this pin — the app and release workflow
  consume the engine only).
- `SHA256SUMS` — engine line updated with the rebuilt `bin/boris`; the
  rest is the archived kit.

## The pinned engine

| Field | Value |
|-------|-------|
| Commit | `6b930b7` (`boris/0.8.1`, afterparty; contains A1/A14/A7 + A3/A4/A13) |
| Engine binary sha256 | `2ced4d5fa87be7bdc258670ca90821e60f20db4b232403e27098ed0b78909551` |
| Behavior | local spike decodes IR via `SOLIPSIST_BORIS_BIN` |

## Reproducing the binaries (if the kit is gone)

The kit was built from the pinned commit. The engine and the toolchain
binaries rebuild from the boris source checkout at that commit:

```bash
cd <boris-repo>          # checkout at 6b930b7
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
`AGENTS.md` covers both.

Full review and probe results: [`docs/AGENT-KIT-REVIEW.md`](../docs/AGENT-KIT-REVIEW.md).
