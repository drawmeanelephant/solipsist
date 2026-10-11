# Boris Agent Kit — engine pin (metadata only)

This folder preserves the *pin* — the exact provenance and SHA-256
fingerprints of the engine build the app is developed and released
against. **The binaries are not committed here**; they are rebuilt from
the pinned commit or supplied by an agent kit (see "Reproducing" below).

## The pinned engine

| Field | Value |
|-------|-------|
| Commit | `3ab19adf4d57e9061d880288ec1a2774ffa46a8c` |
| Line | `main` — the integration line since `afterparty` landed via boris PR #790 |
| Compiler id | `boris/0.8.2` (`--build-info` vcsRevision `3ab19ad`) |
| Toolchain | Zig **0.17** (was 0.16 at the previous pin) |
| Engine sha256 | `bb49bc14…0d96eaef` (debug `zig build`; see `SHA256SUMS`) |

## What the pin carries (vs the previous `bf464a0` / `boris/0.8.1` pin)

- `html-build-report-0.2.0` — additive `vcsRevision` + `proofPack` mirror.
- `boris --build-info` — one-line `boris-build-info` provenance document
  (#776); embedded into the app bundle by `scripts/embed-boris.sh` as
  `engine-provenance.json`.
- Publication plan schema 3 — target `head` / `html_profile` declarations
  (head-metadata.md); `nostr` object at schema 2.
- **Profile-driven HTML execution** — `build` / `watch` / `validate
  --profile PATH` execute the declared targets, layout rules, static
  dir, sitemap, and site URL. Explicit selectors alongside `--profile`
  now run a consistency check and refuse unselected declarations.
- `--static-dir` / per-target `static.dir` (#804).
- `boris graph`, `boris proof verify`, `check --fail-on-*` classes,
  `edgeCounts` in doc-intel reports, `init --type` archetypes,
  `oliver --to html4-strict` / `--target-profile NAME=html4_strict`.
- Editor host (`boris-editor`) grew a normative contract
  (`docs/contracts/editor-host.md`): managed validate + watch daemons, a
  token-gated preview origin, a nine-mode command allowlist including
  `proof_verify`, and a dist-writer seat. `open=` (A15) is consumed by
  the shipped shell.
- `watch_events_schema` remains **1** — the hello handshake is unchanged.
- `boris-content-audit` graduated to `drawmeanelephant/boris-content-audit`
  (boris#834); `boris-migration-lab` likewise left the repo. Solipsist's
  content-audit verb still works via `SOLIPSIST_CONTENT_AUDIT_BIN`, a kit
  binary, or a `../boris-content-audit` sibling checkout.

## Reproducing the binaries

```bash
cd <boris-repo>   # checkout at 3ab19adf…
zig build                                        # boris, boris-package, boris-source-rag, boris-job-runner
zig build --build-file editor/build.zig          # boris-editor (+ contract probe)
cd editor/ui && npm ci && npm run build          # editor-ui dist (or `make editor-ui` here)
```

A rebuilt binary's sha256 differs across build configs — behavior is
what's pinned and verified. Point the app at a rebuilt engine via
`SOLIPSIST_BORIS_BIN` or the `../boris/zig-out/bin/boris` fallback.

Full contract surface: [`docs/BORIS-CAPABILITIES.md`](../../docs/BORIS-CAPABILITIES.md)
and [`docs/ENGINE-CONTRACTS.md`](../../docs/ENGINE-CONTRACTS.md).
