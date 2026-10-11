# Boris Capabilities — the full list

**What boris does, sourced from `docs/STATUS.md`, `docs/contracts/`, the
`--help` surface, and live probes against the pinned engine.** This is the
authoritative capability map the Solipsist app is built against. If a
capability isn't here, it isn't in the harnessed engine.

**Pin:** `3ab19ad` on `main` (`vendor/boris-agent-kit/`). The `afterparty`
line landed via boris PR #790; `main` is the integration line.

**Identity (boris's own words):** *graph-native publication compiler with
multiple targets. Markdown in → validated Trunk/Satellite graph → contracted
projections. HTML `dist/` is the default target, not the whole product.*
One Zig binary, closed frontmatter, Oliver renderer in-process, fail-loud
graph. Version `boris/0.8.2`; base IR `schemaVersion 0.2.0`; semantic
relations `0.3.0`; Cooklang recipe IR `0.4.0` (conditional — only emitted
when the corpus has recipes). Build baseline: Zig 0.17 + Oliver pinned in
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
| Layouts & themes | Closed layout slots (10 markers, single-use), `{{asset-url}}` (repeatable, max 16), `{{relations}}`/`{{backlinks}}`, layout **rules** (`id:`/`glob:`/`role:` selectors, fixed precedence, order-independent), per-target layouts, `--target-profile html\|xhtml\|html4-strict` (Oliver serialization profiles) |
| Static files | Per-target `static.dir` (#804) or `--static-dir`: a project-relative input directory copied byte-identically into the target root; may not nest with the output or content root |
| Head metadata | Closed opt-in `head` declaration per target — canonical URL + OGP/Twitter-card fields with a fixed precedence ladder and exact-page overrides (`head-metadata.md`); `html_profile` selects `html`/`xhtml`/`html4_strict`. Either negotiates plan **schema 3** |
| Theme catalog | 20+ first-class themes under `themes/` (`boris`, `reference`, `press`, `showcase`, `archive`, `field-notes`, `compact`, `cards`, `cozy`, `journal`, `ledger`, `reading`, `semantic`, `columns`, `service`, `engineering`, `civic`, `tokens`, `corporate`, `minimal`, `gallery`, `html4-strict`, …); sample sites under `examples/` |
| Determinism | Byte-deterministic outputs; no timestamps/absolute paths/random ids in artifacts; parallel-safe with identical bytes across `--jobs` counts |
| Scale | Near-linear incremental (content-addressed `NodeLookup`, no quadratic dirty scans); `--jobs 1–64` |

## 2. CLI (command-based)

```
boris build                 HTML site (default command)
boris validate              Artifact-free HTML preflight + in-memory link audit
boris watch [--serve]       Build, watch, rebuild; optional loopback preview server
boris check                 Read-only graph-health report (findings don't fail by default)
boris impact <ID>           Read-only transitive impact report
boris plan --profile        Normalized publication plan (stdout-only, no network)
boris recipe-scale          Derived Cooklang scale view (no rewrite of .cook/graph.json)
boris graph                 Frozen graph → Mermaid (default) or Graphviz DOT
boris proof verify          Apply publication-check severity policy to a committed checks.json
boris init [DIR] [--type]   Starter site archetypes: docs, garden, cookbook, blog, textile, …
boris standard-site …       AT Protocol publication family (8 subcommands)
boris nostr plan|sign|publish  NIP-23 long-form publication (offline-first)
```

Flags of note: `--input`, `--profile`, `--textile`, `--cooklang`, `--quiet`,
`--timings`, `--format human|json`, `--report PATH`, `--fail-on-unreferenced`
/ `--fail-on-unlinked` / `--fail-on-flat-graph` / `--fail-on-zero-includes` /
`--fail-on-zero-relations`, `--build-info`, `--version`/`-V`, `--site-url`,
`--static-dir`, `--target-profile`, `--pages-base-*`, `-h/--help`. Exit codes:
**0** success · **1** content · **2** usage · **3** I/O, plus Standard.site
classes **4–9** (denial, timeout, compatibility, partial-publication,
verification, session-layer).

### Profile-driven execution (the big 0.8.2 surface)

`boris build --profile PATH`, `boris watch --profile PATH [--serve]`, and
`boris validate --profile PATH` execute the *declared* HTML configuration —
input, targets, fallback theme/layout, layout rules, static dir, sitemap,
site URL — with no CLI selectors. Refusals are typed exit-2 before any
output: profile editions (`ir`/`rag`/`context`), target RSS/llms, multi-target
sitemap/static/publication metadata, sitemap without `site.url`, and (watch
only) Standard.site verification. Watch uses a startup snapshot of the
profile. With explicit HTML selectors, `build --profile` instead runs a
consistency check against the CLI flags and refuses unselected declarations —
the old "selectors augment the profile" behavior is gone.

## 3. Output projections

| Projection | Artifacts |
|---|---|
| **HTML** | `<target-dir>/**/*.html` (+ sitemap.xml, rendered-search index, head-link surfaces); `.boris-cache/manifest.json` + `heading-harvest.json` (incremental/watch); staged atomic publish; **multi-target isolation** (each target its own `_boris/` + `assets/`) |
| **IR** | `manifest.json`, `graph.json` (nodes/edges/reverseIndex/nav), **`completion.json`** (editor completion surface), `build-report.json` (written on success *and* failure); **Draft 2020-12 JSON Schemas** for all of them |
| **RAG** | Default: bounded **working-context packs** (`working-N.md`, sidecar manifest, scope/counts/hashes) — model-facing, site-only; `--rag --complete` for the full corpus; `--scope`, `--split-size`, `--bundles-only` |
| **Context** | `bundle.md`, `manifest.json`, `graph.json`, `pages/<id>.md`, `parts/part-N.md` (with `--split-size`) |
| **llms.txt** | Deterministic export, UTF-8-boundary-safe truncation, location-aware URLs |
| **RSS 2.0** | Strict UTC metadata, safe deployed URLs, atomic single-file publish; needs `--site-url` + `--rss-title` + `--rss-description` |
| **Sitemap** | Deterministic XML, strict public-URL validation, obsolete-output cleanup; needs `--site-url`; composes with HTML targets and profile `sitemap` declarations |
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
- `boris watch --watch-json` — stderr becomes an exclusive NDJSON event
  stream: `hello` (**`watch_events_schema: 1`** — unchanged at this pin),
  `watcher-started`, `serve-started` (`url`/`helper`/`port`), `build-*`,
  `watch-error`, `watch-stopped`.
- `boris validate --watch --watch-json` — same protocol in validate mode:
  a zero-write diagnostics daemon.
- The server never modifies the output directory (responses generated in
  memory).

## 5. Machine surface (for tooling like Solipsist)

| Surface | What it gives |
|---|---|
| `--version` / `-V` | `boris/0.8.2` on stdout, exit 0, no content scan |
| `--build-info` | One-line `boris-build-info` document (#776): `{format, schemaVersion, version, vcsRevision}` — the exact revision a binary was compiled from |
| `--timings` | `boris-timings` JSON on **stdout**: `format`/`schemaVersion`/`mode`, `phases`, `counters`, `totalNs` |
| `build`/`validate --report PATH` | **`html-build-report-0.2.0`** JSON on success *and* failure — diagnostics plus additive `vcsRevision` and a `proofPack` verdicts mirror (single-output builds) |
| `check`/`impact --report` | `boris-documentation-intelligence` schema 0.2.0 report — summary now carries **`edgeCounts`** (incoming/outgoing × pages/sources × parent/include/reference) |
| JSON Schemas | IR artifacts, frontmatter, completion, plan — consumers never hand-roll parsers |
| Diagnostics | **Closed code set** — `E*` errors incl. `EFRONTMATTER`, `EFRAGMENTMISSING`, `EHTML4STRICT`, `EHEAD`, `ELAYOUT*`, `EROUTE*`, `EPUBLICATIONLOCATION`; `W*` warnings incl. `WHEADOGP`; `I*` info like `ILAYOUTSELECTED`; `--quiet` suppresses progress but never errors |
| Containment | **All output trees** (HTML/IR/RAG/context) confined to the process cwd — or the profile's parent dir under `--profile` (`WorkspaceEscape`, exit 2); `--report` single-file paths stay free |
| Atomicity | Staged publish per target; build-report written even on failure; cache manifest replaced only on success; evidence chain committed last |

## 6. Publication targets

| Target | Status | Surface |
|---|---|---|
| **GitHub Pages** | ✅ verified | `.nojekyll` policy, artifact packaging, retained evidence, official Actions workflow; `github-pages-audit` observer tool |
| **Standard.site / AT Protocol** | ✅ verified | `standard-site` family: `publish` (reconciliation, CAS, prune authority), `plan`/`records` (offline), `verify`, `login`/`sessions`/`logout` (DPoP OAuth **and** opt-in app-password), `smoke` (live, opt-in); exit classes 4–9. **Profile prerequisite:** the profile must declare a `publication` target |
| **Nostr NIP-23** | 🚢 shipped (not a verified target) | `plan` (offline, closed `nostr` plan object — pubkey/articles/relays normalized), `sign` (`--key-stdin`, BIP-340/secp256k1, never from argv/env), `publish` (in-repo RFC-6455 WebSocket client, per-relay evidence). **Profile prerequisite:** a `nostr` section |
| **Cloudflare Containers** | ⏸ parked | `boris-job-runner` builds from the root build; not a `publication.target` |
| **Wasm embed** | ⏸ parked | `compileBundle` ABI + render/embed wasm artifacts in `zig-out` |

## 7. Evidence chain / Proof Pack (per publication)

`_boris/proof/` — `artifacts.json` (exact bytes, sizes, SHA-256, pixel dims,
semantics) → `checks.json` (verification checks) → `claims.json`
(mechanical claims + declared limitations) → `touches.json` →
`proof-pack.json` + `index.html`. **`boris proof verify --html-dir dist`
re-applies the check severity policy to the committed `checks.json`** — the
CI enforcement surface; a failing check never fails the committed target.

The standalone **`boris-package`** archive: `--input`, `--packages-dir`,
`--archive`, `--with-rag` / `--no-rag`; produces `ir/`, optional `rag/`,
`MACHINE-READABLE-VERSION.json`, `SHA256SUMS`. **HTML is never included.**

## 8. Editor (boris ships one)

`boris-editor`: loopback Zig host + Svelte 5 shell, contract-normative under
`docs/contracts/editor-host.md`. Launch line unchanged:
`boris-editor [DIR] [--boris PATH] [--ui-dir DIR] [--port PORT]` →
`BORIS_EDITOR_URL=http://127.0.0.1:<port>/#token=<hex>` on stderr. What the
host owns at this pin:

- **Managed daemons**: a `validate --watch` daemon (lazy, writes
  `.boris/html-build-report.json`) and an explicitly started
  `watch --input content --html-dir dist --watch-json` daemon with a schema
  handshake, bounded event ring (`/api/watch/events?after=`), and crash
  supervision.
- **A dist-writer seat**: once the watch daemon starts it owns `dist/`;
  preview rebuilds refuse `409 watch_daemon_active` rather than race it.
- **A token-gated preview origin** serving the committed `dist/` behind
  the shell's CSP.
- **A nine-mode command allowlist** (`/api/commands/run`): `validate`,
  `ir_build`, `html_build`, `check`, `impact`, `plan`, `recipe_scale`,
  `graph_export`, `proof_verify` — fixed argv, 120s timeout, output caps.
- File editing with undo/redo, crash recovery snapshots, external-change
  conflicts; `open=<project-relative>` fragment consumed by the shipped
  shell (`boris.json`, `content/`, `themes/` roots only).

## 9. Standalone tools (in-repo and adjacent)

`tools/` in-repo: `source-rag` (pack-by-tool), `docs-maintenance`,
`testdata-generator`, `search-index`, `github-pages-audit`, `scale-smoke`,
`agent-pack` (binary kits), `job-runner` (hosted container runner). Each is
a standalone Zig binary with its own lane.

**Graduated to their own repositories:** `boris-content-audit`
(`drawmeanelephant/boris-content-audit`, boris#834) and
`boris-migration-lab` — Solipsist still locates the audit binary via env
override, kit bins, or a `../boris-content-audit` sibling.

## 10. Security posture (part of the product)

Unicode ingest policy (`EUNICODE`) · shared output-encoding layer
(`structured_out.Sink`) with a build-time emitter-regression gate · YAML /
JSON / XML / markdown injection prevention · line-terminator class handled
everywhere · symlink refusal at every boundary · output containment (all
trees) · hostile-output fixture corpus · data-URI media-type whitelist ·
active-SVG refusal · secret hygiene (keys only via stdin; never
argv/env/profile/logs) · DID-document backlink verification before OAuth
authority discovery.

---

## What this means for Solipsist (the short version)

- **Preview is engine-owned**: `watch --serve` + SSE reload; the app's
  WKWebView points at `127.0.0.1:PORT`. While the **editor companion is
  connected to a project, its host owns the dist-writer seat** — the app's
  watch parks (reasoned suspend) rather than run a second writer.
- **Profiles now execute**: `build`/`watch`/`validate --profile` run the
  declared config, so Boris owns theme/layout/static/sitemap fidelity —
  but the refusal boundary (editions, multi-target metadata, watch +
  Standard.site verification) means Solipsist's per-target fan-out stays
  the general path for build verbs. The site/docs pipeline at `site/` is
  fully profile-declared.
- **Diagnostics are artifact-owned**: `html-build-report-0.2.0` +
  `build-report.json` + `--timings` + `edgeCounts` cover the machine
  surface — render reports, not stderr.
- **Provenance is a first-class surface**: `--build-info` →
  `engine-provenance.json` in the bundle → Settings → Engine.
- **The app can be a publishing console**: GitHub Pages, Standard.site,
  Nostr are CLI surfaces begging for native flows; `proof verify` and
  `boris graph` are the next cheap verbs.
