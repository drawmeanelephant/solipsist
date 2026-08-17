# Boris Capabilities — the full list

**What boris does, sourced from the afterparty changelog (v0.8.1 candidate —
278 fragments under `boris/docs/changelog.d/`), the `--help` surface, and
`STATUS.md`.** This is the authoritative capability map the Solipsist app is
built against. If a capability isn't here, it isn't in the harnessed engine.

**Identity (boris's own words):** *graph-native publication compiler with
multiple targets. Markdown in → validated Trunk/Satellite graph → contracted
projections. HTML `dist/` is the default target, not the whole product.*
One Zig binary, closed frontmatter, Oliver renderer in-process, fail-loud
graph. Version `boris/0.8.1`; base IR `schemaVersion 0.2.0`; semantic
relations `0.3.0`; Cooklang recipe IR `0.4.0` (conditional — only emitted
when the corpus has recipes). Build baseline: Zig 0.16 + Oliver pinned in
`build.zig.zon` (pure Zig, no CMake).

---

## 1. Compiler core

| Capability | Detail |
|---|---|
| Input formats | Markdown (default), Textile (`--textile`, bounded subset), Cooklang recipes (`--cooklang`, `.cook`-only trees) |
| Frontmatter | **Closed 8-key grammar** (`id`, `parent`, `title`, `role`, `status`, `tags`, `relations`, Cooklang `servings`); machine-readable twin `boris-frontmatter-1.schema.json`; every other key is `EFRONTMATTER` |
| Content graph | Trunk/Satellite hierarchy, **arbitrary-depth** parent chains (roots = Trunks, every direct child = Satellite, recursive nav/RAG follows validated chains); source endpoints; semantic relations (`{{relations}}`/`{{backlinks}}` slots); wiki-links (`[[id]]` + `#fragment`) as validated graph edges; `{{include}}` transclusion with cycle detection |
| Rendering | **Oliver** (CommonMark 0.31.2, 652/652 conformance + GFM tables + heading attributes, footnotes, definition lists, strikethrough); `<Aside>`/`<Details>` components; inline-code spans kept literal; deterministic link resolution |
| Content-local assets | `.assets/` trees, published-path collision checks, symlink refusal, image data-URI media-type whitelist, **active-SVG refusal** (`EASSET`), 8 MiB file / 50k file bounds |
| Layouts & themes | Closed layout slots (10 markers, single-use), `{{asset-url}}` (repeatable, max 16), `{{relations}}`/`{{backlinks}}`, layout **rules** (`id:`/`glob:`/`role:` selectors, fixed precedence, order-independent), per-target layouts, `--target-profile html\|xhtml` (Oliver XHTML serialization) |
| Theme catalog | 18+ first-class themes under `themes/`: `boris`, `reference`, `press`, `showcase`, `archive`, `field-notes`, `compact`, `cards`, `cozy`, `journal`, `ledger`, `reading`, `semantic`, `columns`, `service`, `engineering`, `civic`, `tokens`, `corporate`, `minimal`; sample sites under `examples/` |
| Determinism | Byte-deterministic outputs; no timestamps/absolute paths/random ids in artifacts; parallel-safe with identical bytes across `--jobs` counts |
| Scale | Near-linear incremental (content-addressed `NodeLookup`, no quadratic dirty scans); `--jobs 1–64`; 2000-page checks phase ~231s → ~9s |

## 2. CLI (command-based)

```
boris build                 HTML site (default command)
boris validate              Artifact-free HTML preflight + in-memory link audit
boris watch [--serve]       Build, watch, rebuild; optional loopback preview server
boris check                 Read-only graph-health report (findings don't fail by default;
                            --fail-on-unreferenced opt-in for CI)
boris impact <ID>           Read-only transitive impact report
boris plan --profile        Normalized publication plan (stdout-only, no network)
boris recipe-scale          Derived Cooklang scale view (no rewrite of .cook/graph.json)
boris init [DIR]            Starter site: 3 pages, starter theme, publication profile
boris standard-site …       AT Protocol publication family (8 subcommands)
boris nostr plan|sign|publish  NIP-23 long-form publication (offline-first)
```

Flags of note: `--input`, `--textile`, `--cooklang`, `--quiet`,
`--timings`, `--format human|json`, `--report PATH`, `--fail-on-unreferenced`,
`--version`/`-V`, `--site-url`, `--pages-base-*`, `-h/--help`. Exit codes:
**0** success · **1** content · **2** usage · **3** I/O, plus Standard.site
classes **4–9** (denial, timeout, compatibility, partial-publication,
verification, session-layer).

## 3. Output projections

| Projection | Artifacts |
|---|---|
| **HTML** | `<target-dir>/**/*.html` (+ sitemap.xml, rendered-search index, head-link surfaces); `.boris-cache/manifest.json` + `heading-harvest.json` (incremental/watch); staged atomic publish |
| **IR** | `manifest.json`, `graph.json` (nodes/edges/reverseIndex/nav), **`completion.json`** (editor completion surface), `build-report.json` (written on success *and* failure); **Draft 2020-12 JSON Schemas** for all of them |
| **RAG** | Default: bounded **working-context packs** (`working-N.md`, sidecar manifest, scope/counts/hashes) — model-facing, site-only; `--rag --complete` for the full corpus (INDEX, UPLOAD-GUIDE, `catalog.jsonl`, `catalog_meta.json`, `system/**`, `content/pages/**`, graph tables); `--scope`, `--split-size`, `--bundles-only` |
| **Context** | `bundle.md`, `manifest.json`, `graph.json`, `pages/<id>.md`, `parts/part-N.md` (with `--split-size`) |
| **llms.txt** | Deterministic export, UTF-8-boundary-safe truncation, location-aware URLs |
| **RSS 2.0** | Strict UTC metadata, safe deployed URLs, atomic single-file publish |
| **Sitemap** | Deterministic XML, strict public-URL validation, obsolete-output cleanup |
| **Search** | Compiler-owned rendered-search index (`search-index.json`) published by a normal build; layout markers `data-boris-search-root` / `-exclude` / `-noindex`; no-JS UI |

## 4. Watch & preview (the app's live surface)

- `boris watch` — debounced (100ms) + coalesced (2s burst cap) rebuilds,
  graceful SIGINT/SIGTERM shutdown, recoverable content failures keep the
  watcher alive with last-good output preserved.
- `boris watch --serve [--port N]` — **loopback HTTP server** on
  `127.0.0.1` (default 8090, `0` = ephemeral) serving the built tree;
  `/__boris/` helper page (iframe + EventSource) and `/__boris/events`
  **SSE stream with `event: reload` + generation counter**. Static only, no
  HMR/script injection; multi-target serves first canonical target.
- The server never modifies the output directory (responses generated in
  memory).

## 5. Machine surface (for tooling like Solipsist)

| Surface | What it gives |
|---|---|
| `--version` / `-V` | `boris/0.8.1` on stdout, exit 0, no content scan (pinned by `test-version-pin`) |
| `--timings` | `boris-timings` JSON on **stdout**: per-phase durations + counters (scan/parse/graph/dependency; full HTML pipeline) |
| `build --report PATH` | **`html-build-report-0.1.0`** JSON on success *and* failure — every HTML diagnostic class (`E*`, new `ELAYOUT*`, `EROUTE*`, `EPUBLICATIONLOCATION`), stable codes, content-root-relative paths, line/column, `compilerId`; rejected on watch/non-HTML |
| `check`/`impact --report` | Analysis report to file (default render: stderr) |
| JSON Schemas | IR artifacts, frontmatter, completion — consumers never hand-roll parsers |
| Diagnostics | **Closed code set** (`E*` errors, `I*` info like `ILAYOUTSELECTED`), full-source-line locations, `EUNICODE`, `ECOOKLANG`; `--quiet` suppresses progress but never errors |
| Containment | **All output trees** (HTML/IR/RAG/context) confined to the process cwd (`WorkspaceEscape`, exit 2); `--report` single-file paths stay free; root-path boundary fixed for container cwd `/` |
| Atomicity | Staged publish per target; build-report written even on failure; cache manifest replaced only on success; evidence chain committed last |

## 6. Publication targets

| Target | Status | Surface |
|---|---|---|
| **GitHub Pages** | ✅ verified | `.nojekyll` policy, artifact packaging, retained evidence, official Actions workflow; `github-pages-audit` observer |
| **Standard.site / AT Protocol** | ✅ verified | `standard-site` family: `publish` (reconciliation, CAS, prune authority), `plan`/`records` (offline), `verify`, `login`/`sessions`/`logout` (DPoP OAuth **and** opt-in app-password), `smoke` (live, opt-in); DPoP/ES256, XRPC client, DID/PDS discovery with SSRF checks; exit classes 4–9 |
| **Nostr NIP-23** | 🚢 shipped (not a verified target) | `plan` (offline), `sign` (`--key-stdin`, BIP-340/secp256k1, never from argv/env), `publish` (in-repo RFC-6455 WebSocket client, per-relay evidence, verdicts `complete`/`partial`/`failed`/`incomplete`) |
| **Cloudflare Containers** | ⏸ parked | `boris-job-runner` example Worker; not a `publication.target` |
| **Wasm embed** | ⏸ parked | `compileBundle` ABI (`wasm32-wasi` exports files-in → diagnostics/IR/HTML-out), source-provider + artifact-sink seams, official Worker host example |

## 7. Evidence chain / Proof Pack (per publication)

`_boris/proof/` — `artifacts.json` (exact bytes, sizes, SHA-256, pixel dims,
semantics) → `checks.json` (verification checks) → `claims.json`
(mechanical claims + declared limitations) → `touches.json` (relationship
index over the committed bytes) → `proof-pack.json` + `index.html` (final
presentation layer with embedded model digest). Everything atomic,
deterministic, bound to exact committed bytes.

## 8. Editor (boris ships one — important for our D4 decision)

`boris-editor`: loopback Zig host + semantic Svelte shell. Compiler-backed:
problems panel consuming only boris-owned reports (with a documented stderr
fallback), completion **sourced exclusively from `completion.json`**,
graph-aware inspector (parent/children/backlinks/references/includes),
recipe pane (`recipe-scale`), live preview via `watch --serve` (build-on-
save, last-good preservation), publication-profile management (plan +
Proof Pack), safe file ops (undo/redo, crash recovery, external-change
conflicts), keyboard-first (command palette, a11y-conformance-tested).
A browser surface in the compiler repo — the app's complementary edge is
native macOS (see MISSION.md).

## 9. Labs & standalone tools (in-repo, not runtime deps)

`tools/`: `migration-lab` (WordPress, Starlight/Astro import plan+apply,
Instagram, Facebook, Google Takeout, Filed.fyi — all deterministic,
review-first, source-confined), `source-rag` (pack-by-tool), `content-audit`
(poetry/parent-alignment auditing), `docs-maintenance`, `testdata-generator`,
`search-index`, `github-pages-audit`, `agent-pack` (binary kits for agent
handoff), `job-runner` (hosted container runner). Standalone Zig binaries,
each with its own test lane.

**The agent kit makes them consumable as binaries.** `boris-agent-kit/`
(sibling folder) ships 10 SHA256-verified Darwin-arm64 binaries of our
pinned commit — the engine plus `boris-package` (Proof Pack archive),
`boris-search-index` (`boris-rendered-search-index` v1), `boris-content-audit`,
`boris-source-rag`, `boris-testdata` (deterministic fixtures + evidence
runner), and the migration/scale/docs/gh-pages tools. All probed live;
results in `vendor/boris-agent-kit/`.

## 10. Security posture (part of the product)

Unicode ingest policy (`EUNICODE`: controls, bidi overrides, tag chars —
never smuggled into outputs) · shared output-encoding layer
(`structured_out.Sink`) with a build-time emitter-regression gate · YAML /
JSON / XML / markdown injection prevention (page-controlled values can't
escape their containers) · line-terminator class handled everywhere ·
symlink refusal at every boundary · output containment (all trees) ·
hostile-output fixture corpus · data-URI media-type whitelist · active-SVG
refusal · secret hygiene (keys only via stdin; never argv/env/profile/logs) ·
DID-document backlink verification before OAuth authority discovery.

---

## What this means for Solipsist (the short version)

- **Preview is engine-owned now**: `watch --serve` + SSE reload replaces the
  planned app-side HTTP server (D5 changes). The app's WKWebView points at
  `127.0.0.1:PORT`.
- **Diagnostics are artifact-owned**: `build --report` + IR
  `build-report.json` + `--timings` cover the machine surface — the app
  should render reports, not parse stderr (D10 shrinks to a corner case).
- **Editor scope shrinks**: `completion.json` + the engine's own editor
  answer the "what does the editor do" question; Solipsist's D4 becomes
  native-editing ergonomics + the problems panel, not a from-scratch
  markdown IDE.
- **The app can be a publishing console**: GitHub Pages, Standard.site,
  Nostr are CLI surfaces begging for native flows.
- **Contracts are complete**: JSON Schemas + closed diagnostics + version
  query — the "process ABI" the issues batch was pushing for is largely
  *already built* on afterparty. Re-baseline the issue list before filing.
