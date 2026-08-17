# Agent Kit Review — `boris-agent-kit`

**Date:** 2026-08-17 · **Status:** verified against the kit binaries, hands-on

The `boris-agent-kit/` folder (sibling of `boris/` and `solipsist/`) is a
**prebuilt binary transport** from the boris repo: 10 native Darwin-arm64
executables, built from commit `b82e9e2eace74d9ca61df23dffc1329d2a2fe628` on
branch `freebuff/agent-pack` with Zig 0.16.0, `dirty: false`. This is the
canonical "work against binaries" reference for Solipsist — everything below
was verified by running the kit's own executables, not by reading source.

> **⚠️ The kit folder is temporary and may not exist in future
> environments.** Its provenance pin (MANIFEST.json + SHA256SUMS, verbatim)
> is archived in [`../vendor/boris-agent-kit/`](../vendor/boris-agent-kit/),
> with a rebuild recipe from the pinned commit. The verification below is
> the durable record; the folder is not a dependency of any future work.

## Integrity (all green)

- `SHA256SUMS` verified for **all 10 binaries** (`shasum -a 256 -c` → all OK).
- `MANIFEST.json` consistent with the payload (commit, branch, platform,
  zig version, per-binary sha256).
- The engine's commit **is our pinned commit** (`b82e9e2`, the afterparty
  line, `boris/0.8.1`) — the kit is the binary form of exactly what our
  docs pin in D7. The kit `bin/boris` differs in hash from our local
  `zig-out` build (build-config difference), but the local checkout's HEAD
  is the same commit and the behavior matches on every probe below.

## The engine (`bin/boris`) — contract conformance (all pass)

Every contract we documented and probed in earlier sessions holds against
the kit binary:

| Probe | Result |
|-------|--------|
| `--version` / `-V` | `boris/0.8.1`, exit 0 |
| IR build (`build --out ir`) | 4 artifacts, exit 0 |
| `manifest.json` | `"compiler": "boris/0.8.1"` |
| `completion.json` | `"compiler_id": "boris/0.8.1"` |
| IR `build-report.json` | **no compiler field** — A3 / [boris#638](https://github.com/drawmeanelephant/boris/issues/638) confirmed live |
| `--help` `--report` text | still says "instead of stdout" — A4 / [boris#639](https://github.com/drawmeanelephant/boris/issues/639) confirmed live |
| `check --report` | report written to the file; stdout stays clean; exit 0 |
| **M1 spike** | `SOLIPSIST_BORIS_BIN=<kit>/bin/boris make run-spike` → **SPIKE OK**, all contracts decoded |

Takeaway: the app can consume the kit binary today with zero decoder
changes. It is a drop-in for `SOLIPSIST_BORIS_BIN` and for the bundled
engine in the app.

## The 9 tool binaries — what they are (verified via `--help` + runs)

All of them exist in the boris source checkout (`tools/` / `src/package.zig`)
at the same commit — the kit is just the prebuilt set.

| Binary | What it is | App relevance |
|--------|-----------|---------------|
| `boris-package` | Deterministic IR (+ optional RAG) **review archive** — the "Proof Pack". Verified: emits `boris-package.tar` containing `ir/`, `rag/`, `MACHINE-READABLE-VERSION.json`, `SHA256SUMS`; HTML never included. Version file carries `compiler_id`, `ir_schema_version`, `rag_schema_version`. | **High** — the evidence chain our MISSION's publishing story wants; a shareable/verifiable artifact for export flows. |
| `boris-search-index` | Indexes rendered HTML into a versioned search index. Verified: `indexed 4 rendered pages → search-index.json`, `format: boris-rendered-search-index`, `schema_version: 1`, documents with `sections[]` (level/heading/fragment/text/code). | **High** — native app search without reimplementing anything; schema-versioned. |
| `boris-source-rag` | Packs project **source** files for LLM upload (explicitly *not* the product RAG). Profiles, bundles, size caps, pack-by-tool. | Medium — AI-assist/context export features. |
| `boris-content-audit` | Standalone deterministic **editorial audit** (poetry mode initially; policy files, delta reports, markdown/json/html output). Never mutates `--root`. | Medium — editorial QA surface (M6+); policy-driven, JSON out. |
| `boris-testdata` | Deterministic **fixture generator + evidence runner**. Verified end-to-end: `generate --pages 8 --seed 42` → `validate` (JSON, `ok:true`) → `run` against the kit `boris` (exit 0). | **High for CI** — our spike can run against generated fixtures, not just boris's checked-in content; scale smoke and regression gates. |
| `boris-migration-lab` | Astro / WordPress / Instagram / Obsidian / Notion / Starlight → Boris migration lab. | Low (v1) — import flows later. |
| `boris-scale-smoke` | Opt-in synthetic HTML scale smoke. | Low (v1) — perf testing. |
| `boris-docs-maintenance` | Docs maintenance tool. | None for the app — maintainer-side. |
| `boris-github-pages-audit` | Audits GH Pages deployment against plan + proof inventory. | Medium (M8) — post-publish verification for the publishing console. |

## What this changes for Solipsist

1. **D7 (pin note) is now practically answered.** The kit is a hashed,
   pinned binary of our exact commit. Two viable paths:
   - **Vendor the kit binary**: `scripts/embed-boris.sh` copies `bin/boris`
     from the kit (or a path from `BORIS_AGENT_KIT` env) into the app
     bundle — no Zig toolchain needed at build time, hash-checkable.
   - Keep building from source but assert the output hash against the kit's
     `SHA256SUMS` in CI, so a drifted build fails loudly.
   Recommend: vendor-from-kit as the default path, with the source build as
   the fallback when the kit is absent — mirrors the existing
   `SOLIPSIST_BORIS_BIN → bundle → ../boris` ordering.
2. **The tool set belongs in the capability map.** `BORIS-CAPABILITIES.md`
   lists the compiler surface; the kit shows boris ships a real binary
   toolchain (Proof Pack, search index, audits, fixtures). Add a section so
   nobody re-invents app search or fixture generation.
3. **Contract surface for the app expands** (each is JSON/versioned):
   `boris-package` (MACHINE-READABLE-VERSION), `boris-search-index`
   (`boris-rendered-search-index` v1), `boris-content-audit` (report.json),
   `boris-testdata` (fixture + validate JSON). These slot into the
   M2–M4 contract table in `ENGINE-CONTRACTS.md` when a milestone needs
   them; no re-probing needed — verified shapes are above.
4. **Spike/CI improvement:** `boris-testdata` gives deterministic,
   reproducible workloads (seed-driven) — better than depending on the
   boris checkout's fixture content for `make run-spike`.
5. **Noted, no action:** `boris-docs-maintenance` and the scale/migration
   labs are agent-side or later-milestone; `boris-github-pages-audit`
   matters only when the publishing console (M8) is real.

## Resolved: the pin is archived, not the binaries

The temporary kit folder is going away; future work happens off the branch.
Resolution: **archive the kit's pin, not the ~10 MB of binaries.**
`vendor/boris-agent-kit/` now carries the verbatim MANIFEST.json +
SHA256SUMS and a rebuild recipe from the pinned commit, so a fresh agent
can either locate the kit if it exists or rebuild `bin/boris` at
`b82e9e2` and point the app at it (`SOLIPSIST_BORIS_BIN` or the
`../boris/zig-out` fallback). Behavior is pinned and verified; exact binary
hashes are kit-specific and documented.
