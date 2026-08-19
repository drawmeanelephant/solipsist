# Engine Contracts — probed hands-on against afterparty (M2–M8 design input)

**Date:** 2026-08-17 · **Engine:** afterparty, `boris/0.8.1` (kit pin
was `b82e9e2` when these tables were probed; current pin is `bf464a0`,
which contains A1/A14/A7 + A3/A4/A13 + A15 `open=` + A5
`validate --watch` — record only, tables not re-probed)
· **Content:** the afterparty dogfood site (25 pages, /tmp/apws)
for §1–§4; the in-repo `Stunts/happy` corpus for §5–§7.

Everything here was verified by running the binary and reading the real
responses/artifacts. It is the concrete contract surface the app's M3
(editor completion), M4 (live preview), M5 (problems panel), M7 (outputs
fan-out), and M8 (publish) are built against. Authoritative schema twins
live in the boris repo under `docs/contracts/schemas/` — consume those,
don't hand-roll.

---

## 1. `watch --serve` — the preview surface (M4)

### Invocation & discovery

```
boris watch --serve --watch-json [--port N] --input <content-root>
```

- Default port **8090**; `--port 0` = ephemeral.
- **Port discovery (A1, M14):** with `--watch-json` stderr is exclusively
  NDJSON; the app learns the port from the `serve-started` event, not a
  prose regex:
  ```
  {"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}
  {"event":"serve-started","url":"http://127.0.0.1:18090/","helper":"http://127.0.0.1:18090/__boris/","port":18090}
  ```
  The app fires `onServe` with the `helper` URL after a `hello` handshake
  at `watch_events_schema: 1` (unknown versions degrade — D8). `build-failed`
  / `watch-error` / `watch-stopped` are surfaced, never swallowed.
- Run with `cwd = project folder` (containment: `--input` may be absolute,
  but outputs — including `dist/` — are workspace-relative; see
  A7).
- Multi-target builds serve the **first canonical-order target** only.

### Endpoints (verified)

| Endpoint | Behavior |
|----------|----------|
| `GET /` | `index.html` — `200`, `content-type: text/html; charset=utf-8`, `cache-control: no-store`, `connection: close` |
| `GET /<page>.html` | Static pages — `200`, same headers |
| `GET /__boris/` | Helper page ("Boris preview", ~1 KB): dark status bar + iframe + EventSource to `/__boris/events`; auto-reloads on every event. Server-generated — **never written to `dist/`** |
| `GET /__boris/events` | **SSE stream** (text/event-stream): |
| anything else | `404` |

### SSE protocol (verified)

```
event: reload
data: 0
```
then, after each successful rebuild:
```
event: reload
data: 1
```
- `event: reload`, `data: <generation>` — an **integer counter**, bumped per
  successful rebuild.
- The **first event fires immediately on connect** (`data: 0`) — a client
  that connects gets the current state, then updates.
- The stream stays open (true SSE); rebuilds are debounced (100ms) and
  coalesced (2s burst cap) by the watch coordinator.
- **No diagnostics travel over SSE** — only the reload counter. Subprocess
  diagnostics are a separate channel (see §3 and the A1/A5 gap).
- Loopback-only, static serving only, no HMR/script injection.

### App implications (M4)

- Point a `WKWebView` at `http://127.0.0.1:PORT/__boris/` for a free
  auto-reloading preview — the helper page owns the iframe + EventSource.
  (Or embed an iframe + your own `EventSource('/__boris/events')`.)
- Requires the **`com.apple.security.network.server`** entitlement (listen
  on loopback only; outbound needs `network.client` only if themes load
  remote fonts/CDNs).
- Prefer `--port 0` + stderr-line discovery over fixed ports (no collisions).
- Graceful teardown: SIGTERM → exit 0, cleanup message (A12).

### `validate --watch` (A5) — live problems daemon (design for #161)

**Status: carried + probed (2026-08-19)** — [boris#647](https://github.com/drawmeanelephant/boris/issues/647)
(`docs/issues/boris-A5-check-watch-rfc.md`) merged upstream (boris#651),
present in the pinned kit (`bf464a0`), and every claim below verified
live against that binary (initial + rebuild cycles, error cycle,
graceful SIGTERM). Implemented as [#161](https://github.com/drawmeanelephant/solipsist/issues/161)
(`ValidateWatch` + decoder + coordinator + save-gate retirement).

**The contract (probed at `bf464a0`).** `boris validate --watch [--input
DIR] [--report PATH]` joins the artifact-free preflight with the watch
daemon: same debounce / coalescing / ignore rules / signal handlers as
HTML watch, but the rebuild action is `validate` instead of the HTML
publish. Writes nothing but the optional report file (replaced every
cycle, never appended). Output flags are rejected (exit 2).
SIGTERM/SIGINT → graceful exit 0, `watch-stopped reason:"signal"` (A12).
Consumes the same NDJSON protocol with `mode: "validate"` (events on
**stderr**, same `hello` handshake at `watch_events_schema: 1`):

```
{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}
{"event":"build-started","phase":"initial","mode":"validate","targets":["default"]}
{"event":"build-succeeded","phase":"initial","mode":"validate","targets":["default"],"pages_written":null,"duration_ms":22}
{"event":"build-failed","phase":"rebuild","mode":"validate","changed":["guides.md"],"errors":2,"diagnostics":[{"severity":"error","code":"EROUTEMISSING","message":"does not resolve to a published output [fix the path, or publish the file it names]","remediation":"Fix the path, or publish the file it names","sourcePath":"guides.html","line":133,"column":null,"id":null}],"recoverable":true,"duration_ms":23}
{"event":"watcher-started","mode":"validate","targets":["default"]}
{"event":"watch-stopped","reason":"signal"}
```

Probe corrections vs the RFC draft: `build-succeeded` carries
`pages_written: null` (validate writes nothing) and **no** `errors`
key; rebuild cycles carry `changed`; `build-failed` diagnostics are
the `html-build-report-0.1.0` shape with `recoverable`; the daemon
keeps watching after a failed build. The consumption design below
holds as written.

**Consumption design (pickable when the pin carries A5).**

- **Engine** — a `ValidateWatch` long-lived process mirroring
  `WatchServer`'s argv discipline: `validate --watch --watch-json
  --input <contentRoot>`, `cwd = project folder` (D1), stderr →
  NDJSON, no `--serve` (no helper URL), no output flags, no
  `--report` (stream-only — the app already has the A1 parser).
  One `Process` per surface: HTML watch (Preview/letter) and
  validate watch (problems) are siblings, both Engine-owned; never
  a third watch.
- **Decoder** — `WatchEvent` / `WatchStreamParser` (M14-1) consume
  the stream unchanged: same `hello` handshake at
  `watch_events_schema: 1`, `mode` is informational, unknown
  versions degrade (D8). Additive addition only: a
  `buildSucceeded` case (currently `.unknown`-skipped for the HTML
  watch) so the pane can clear on success. The `build-failed`
  `diagnostics` array is byte-identical to
  `html-build-report-0.1.0`, so it decodes straight into
  `[Diagnostic]` and maps with the existing
  `CoordinatorProblems.from(diagnostic:)` — no new problem shape.
- **Coordinator** — register the validate watch like the preview
  watch (`activeWatch`-style, single-owner per selected source);
  bound-root rule identical: a foreign root is idle, never
  consume. Start when a source is selected; stop on source switch
  (SIGTERM, A12). `build-failed` → replace the pane's problems
  with the event's diagnostics; `build-succeeded` → clear;
  `watch-error` / unexpected `watch-stopped` → surface, never
  swallow (same rule as M14).
- **SaveValidateGate** — the save-triggered one-shot validate side
  retires while the daemon is live: boris owns the debounce, `changed`
  gives per-save attribution, and a keystroke never costs a render.
  The manual Validate menu verb and `check` stay unchanged.
- **Gate for #161** — save a page → problems update from the A5
  stream within debounce, no second HTML watch, no one-shot validate
  subprocess; fixture NDJSON (`mode: "validate"`) decodes with the
  existing parser; `SKIP_EMBED_BORIS=1 make build` + `make test`
  green. No live `validate --watch` in CI.

---

## 2. `completion.json` — the editor completion surface (M3)

### Where it comes from

Every successful IR build (`boris --out <dir>` / `--no-rag`) publishes
`.boris/completion.json` alongside `manifest.json` / `graph.json` /
`build-report.json`.

### Shape (verified, real sample)

```json
{
  "format": "boris-completion-index",
  "schema_version": 1,
  "compiler_id": "boris/0.8.1",
  "frozen": true,
  "entities": [
    {
      "id": "guides/asides",
      "title": "Asides & Admonitions",
      "parent": "guides/overview",
      "role": "satellite",
      "status": "published",
      "tags": ["guides", "asides", "components"],
      "relations": []
    }
  ],
  "relation_kinds": ["depends_on", "implements", "relates_to", "supersedes"],
  "parent_targets": ["getting-started", "guides", "guides/overview", "index", "reference"],
  "layout_slots": ["backlinks", "breadcrumb", "children", "content", "footer",
                   "metadata", "nav", "relations", "title", "toc"]
}
```

- `schema_version` is an **integer (1)** — unlike the string
  `schemaVersion` ("0.2.0") on the IR artifacts. Gate on both forms.
- `entities[]` — every page's `id`, `title`, `parent`, `role`
  (`trunk`/`satellite`), `status`, `tags`, `relations`. This is the
  wiki-link / frontmatter completion data.
- `relation_kinds` — the closed relation vocabulary (for `relations:`).
- `parent_targets` — the distinct valid parents (for `parent:`).
- `layout_slots` — the **closed layout-slot set** (for a theme inspector).
- Schema twin: `docs/contracts/schemas/boris-completion-1.schema.json`.

### App implications (M3)

- `[[…]]` wiki-link completion: entity `id`s (the fragment/heading ids are
  Oliver-rendered on the HTML path and out of scope for this index).
- Frontmatter inspector: `parent:` from `parent_targets`, `relations:` from
  `relation_kinds`, `status:`/`tags:` closed sets.
- Refresh strategy: completion.json changes only on successful builds —
  re-decode after each `buildIR` that reports `ok: true`.

---

## 3. `build --report` — the machine diagnostics surface (M5)

### Invocation

```
boris build --html-dir <dir> --report <path> --input <root>
# also: boris validate --report <path>  (no publication at all)
```

- **Written on success AND failure** (verified: exit 0 and exit 1 both
  produce the report). `--report` is **rejected on `watch`** (exit 2).
- `--report` is a single-file path — **absolute paths are fine** (not
  workspace-constrained; only output *trees* are).

### Shape — success (verified)

```json
{
  "schemaVersion": "html-build-report-0.1.0",
  "compilerId": "boris/0.8.1",
  "ok": true,
  "contentRoot": "content",
  "outDir": "dist",
  "errorCount": 0,
  "diagnostics": []
}
```

Note: **no `pageCount`** — unlike the IR `build-report.json`, the HTML
report carries only errors/diagnostics.

### Shape — failure (verified, duplicate-id error)

```json
{
  "schemaVersion": "html-build-report-0.1.0",
  "compilerId": "boris/0.8.1",
  "ok": false,
  "contentRoot": "content",
  "outDir": "dist",
  "errorCount": 2,
  "diagnostics": [
    { "severity": "error", "code": "EIO", "message": "GraphValidationFailed",
      "remediation": "", "sourcePath": null, "line": null, "column": null, "id": null },
    { "severity": "error", "code": "EDUPLICATEID", "message": "duplicate id \"zzdup\" (also zzdup.md)",
      "remediation": "", "sourcePath": "zzdup2.md", "line": 1, "column": 1, "id": null }
  ]
}
```

- Diagnostic objects share the IR shape: `severity, code, message,
  remediation, sourcePath, line, column, id` — and **`sourcePath`/`line`/
  `column` may be `null`** (graph-level failures surface as `EIO` with no
  location; the located diagnostic is usually right behind it). The
  problems panel must tolerate nulls.
- Codes are the closed set (`EFRONTMATTER`, `EDUPLICATEID`, `ELAYOUT*`,
  `EROUTE*`, `EUNICODE`, `ECOOKLANG`, `EIO`, …) plus `I*` info findings.
- Exit mapping: 0 success, 1 content, 2 usage, 3 I/O — unchanged.
- Schema twins: `docs/contracts/schemas/html-build-report-0.1.0.schema.json`
  (HTML) and `docs/contracts/schemas/ir-build-report-0.2.0.schema.json` (IR).

### App implications (M5)

- Problems panel = decode `html-build-report-0.1.0` after each save-triggered
  one-shot `build` (or `validate`), plus the IR `build-report.json` for
  graph-level diagnostics. `ok` + `errorCount` + sorted, located
  diagnostics render directly.
- **Watch-mode diagnostics remain a gap**: `--report` is rejected on watch,
  and SSE carries only the reload counter — so live-while-editing
  diagnostics need the A1 (`--watch-json`) / A5 (`validate --watch`) work
  or a save-triggered one-shot loop.

---

## 4. Quick reference — files to consume directly

| Surface | Artifact / URL | Schema twin (boris repo) |
|---------|----------------|--------------------------|
| Preview | `watch --serve` → `/`, `/__boris/`, `/__boris/events` | `docs/contracts/cli.md` |
| Completion | `.boris/completion.json` | `docs/contracts/schemas/boris-completion-1.schema.json` |
| HTML diagnostics | `--report` → `html-build-report-0.1.0` | `docs/contracts/schemas/html-build-report-0.1.0.schema.json` |
| IR diagnostics | `.boris/build-report.json` | `docs/contracts/schemas/ir-build-report-0.2.0.schema.json` |
| Frontmatter | `boris-frontmatter-1.schema.json` | `docs/contracts/schemas/boris-frontmatter-1.schema.json` |

All probes ran against a fresh afterparty build with the dogfood content;
exact commands are preserved in the session history if re-verification is
needed.

---

## 5. M7 — outputs fan-out: targets, editions, projections (probed 2026-08-17)

All of §5–§7 were re-probed against the **pinned kit `b82e9e2`
(`boris/0.8.1`)** on the in-repo `Stunts/happy` corpus (3 pages), not the
older apws corpus. Every row below is a real invocation + observed
artifact/exit code.

### 5.1 Multi-target HTML — isolated targets, one invocation

```
boris build --target public=dist/public --target preview=dist/preview
```

- ✅ exit 0; **two isolated target roots**, each with its own `index.html`,
  `_boris/` (proof + search), and `assets/`.
- Target names are CLI-side (`public=`, `preview=`); the profile's single
  public target is synthesized as `default` (verified in the site deploy:
  `boris build --profile boris.json` reports `target default`).
- Per-target layout/theme: `--target-layout NAME=PATH`;
  `--target-profile NAME=html|xhtml` (Oliver serialization).
- Per-target theme: `--theme ROOT` (sugar for `ROOT/layouts/main.html` +
  managed `assets/`); layout **rules**:
  `--layout-rule TARGET SELECTOR LAYOUT` with selectors `id:<entity-id>`
  (byte-exact), `glob:<segment-pattern>` (`*` = one full segment), and
  `role:trunk` / `role:satellite`. Precedence: id → glob → role →
  target fallback → global fallback → product default
  `themes/boris/layouts/main.html`. Max 256 rules/target.

### 5.2 Editions — each is its own invocation in this pin

| Edition | Invocation (verified) | Artifacts |
|---|---|---|
| **IR** | `boris build --out .boris` | `manifest.json`, `graph.json`, `completion.json`, `build-report.json` (all four; exit 0) |
| **RAG** | `boris build --rag` | `rag/` — `working-N.md` working packs + `manifest.json` non-upload sidecar (counts/hashes). `--complete`/`--scope`/`--split-size`/`--bundles-only` accepted |
| **Context** | `boris build --context` | `context/` — `bundle.md`, `manifest.json`, `graph.json`, `pages/<id>.md` (3 pages in the probe) |
| **llms.txt** | `boris build --llms` | `llms.txt` (exit 0; UTF-8-safe truncation) |
| **RSS** | `boris build --rss --rss-title T --rss-description D --site-url URL` | `rss.xml` (exit 0) |

**Conflict matrix (verified — important for M7):**

- `--sitemap` is an **HTML-target add-on**: `boris build --html-dir dist
  --sitemap --site-url URL` → `sitemap.xml` in the target root. Requires
  `--site-url`.
- `--rss` and `--llms` **conflict with HTML mode** in this pin: `boris
  build --html-dir dist --rss …` and `… --llms` both exit **2**
  (`conflicting options`). They are **standalone projections** — run them
  as separate invocations (or IR-mode). `--rss` alone needs `--site-url` +
  `--rss-title` + `--rss-description`; `--llms` alone needs nothing extra.
- M7's "Build all" must therefore fan out per projection, not assume one
  invocation emits everything.

### 5.3 `plan --profile` — the declaration surface (M4/M8)

```
boris plan --profile boris.json
```

✅ exit 0, stdout-only `boris-publication-plan` v1. Verified shape:

```json
{
  "format": "boris-publication-plan",
  "schema_version": 1,
  "input": "content",
  "input_format": "markdown",
  "site": { "url": null, "title": "My Boris Site", "description": null },
  "targets": [
    {
      "name": "public", "output": "dist", "public": true,
      "theme": "themes/boris", "layout": null, "layout_rules": [],
      "projections": { "html": true, "sitemap": null, "rss": null, "llms": null }
    }
  ]
}
```

- `targets[].theme` reflects the profile/default theme; `projections`
  carries the per-target html/sitemap/rss/llms switches.
- Profile schema v1 (`boris-publication-profile`) is closed: `format`,
  `schema_version` (exact `1`), `input`, `input_format`, `site`,
  `publication`, `targets`, `editions`. See
  `docs/contracts/publication-profile.md`.

### 5.4 `--timings` (verified shape)

```
boris build --out .boris --timings
```

stdout JSON:

```json
{
  "format": "boris-timings", "schemaVersion": "1", "mode": "ir",
  "phases": { "scan": …, "parse": …, "graph_validate": …, "dependency_resolve": … },
  "counters": { "page_reads": 3, "include_reads": 0, "hash_bytes": 0,
                 "link_resolutions": 0, "fast_path_hits": 0 },
  "totalNs": …
}
```

- `mode` is `ir` for IR builds, `html` for HTML builds; phase/counter keys
  differ accordingly. Parse it as JSON (not stderr prose).

---

## 6. M7 — search & theme catalog (probed 2026-08-17)

### 6.1 Rendered search index

A normal HTML build emits `_boris/search/search-index.json`
(`boris-rendered-search-index` v1) **automatically** — verified in the site
build and the multi-target probe (each target's `_boris/` carries it). The
first-party consumer is an inline script using the
`data-boris-search-root` / `-exclude` / `-noindex` markers; there is no
vendored JS. The standalone `boris-search-index` tool exists for indexing
already-built HTML (`tools/search-index`), but the compiler-owned index is
what a normal build produces.

### 6.2 Theme catalog

`themes/` at the pinned commit ships **20 first-class themes**: `boris`
(default), `reference`, `press`, `showcase`, `archive`, `field-notes`,
`compact`, `cards`, `cozy`, `journal`, `ledger`, `reading`, `semantic`,
`columns`, `service`, `engineering`, `civic`, `tokens`, `corporate`,
`minimal` (verified `ls`). A theme = `layouts/*.html` + optional
`footer.html` + `assets/`; the catalog README documents each theme's
voice and the selection flag (`--theme themes/<name>`).

---

## 7. M8 — publish family (probed 2026-08-17, offline surface)

### 7.1 Standard.site / AT Protocol

- Family (verified `--help`): `plan`, `records`, `publish`, `verify`,
  `login`, `sessions`, `logout`, `smoke`. `plan`/`records` are **offline**;
  `login`/`logout`/`sessions` manage a persisted DPoP OAuth session
  (app-password opt-in); `smoke` is a live opt-in interop test.
- **Profile prerequisite (verified):** `boris standard-site plan --profile
  boris.json` on a plain profile exits **2** `invalid publication profile:
  InvalidPublication`. The profile must declare a `publication` target
  (`github-pages` or `standard-site`) with `base_url`/`origin`/`base_path`
  (and for standard-site: `did`, `name`, `description`,
  `show_in_discover`, `include`/`exclude`, `prune`, optional `pds`).
  M8 must validate the profile before offering publish.
- Exit classes **4–9** (denial, timeout, compatibility,
  partial-publication, verification, session-layer) — surface them, don't
  collapse to 1/2/3.

### 7.2 Nostr NIP-23

- Family (verified): `plan` (offline), `sign` (`--key-stdin`, BIP-340;
  never argv/env/profile/logs), `publish` (in-repo WebSocket client,
  per-relay evidence, verdicts `complete`/`partial`/`failed`/
  `incomplete`).
- **Profile prerequisite (verified):** `boris nostr plan --profile
  boris.json` on a plain profile exits **2** `profile declares no nostr
  section`.

### 7.3 Proof Pack — `boris-package` (verified `--help`)

```
boris-package [--input DIR] [--packages-dir DIR] [--archive NAME]
              [--with-rag | --no-rag] [--quiet]
```

Produces `packages/<archive>` (default `boris-package.tar`) containing
`ir/`, optional `rag/`, `MACHINE-READABLE-VERSION.json`, and
`SHA256SUMS`. **HTML is never included.** The per-publication evidence
chain (`_boris/proof/`) is separate and emitted by the compiler build
(`artifacts.json` → `checks.json` → `claims.json` → `touches.json` →
`proof-pack.json` + `index.html`).

---

## 8. `boris-content-audit` — the audit mailbox surface (probed 2026-08-19)

Standalone kit binary (**not** the embedded `boris`). App surface: #165
(content-audit mailbox). Probe corpora: `Stunts/happy` and
`Stunts/dogfood` (in-repo).

**Provenance:** probed against the agent-kit build present at probe time,
which reports `tool_version "0.1.0"` (sha256 `730b8c45…`).
`vendor/boris-agent-kit/MANIFEST.json` records the archived fingerprint
(`1dab7767…`) — the vendor README notes a rebuilt kit hashes differently
and behavior is what's pinned.

### Invocation

```
boris-content-audit --mode=poetry --root=DIR --content-root=REL --out=DIR [options]
```

| Flag | Behavior |
|---|---|
| `--mode=poetry` | Audit-mode registry; poetry is the initial (only) mode |
| `--root=DIR` | Project root (default `.`). **Never mutated** |
| `--content-root=REL` | Content root relative to `--root` (default `content`) |
| `--out=DIR` | Output directory (required). Tool-owned, atomic, never inside the content root |
| `--policy=FILE` | Versioned JSON policy: eligible/poetry collections, placeholder signatures, density bands, exact mappings |
| `--previous-report=FILE` | Earlier `report.json` for delta comparison |
| `--collection=NAME` | Repeatable coverage/records filter |
| `--format=json\|markdown\|html\|all` | Report formats to emit (default `all`) |
| `--fail-on=none\|structural\|policy` | Class that makes exit 1 (default `structural`) |
| `--revision=STRING` | Explicit source revision (never host-derived) |
| `--quiet` | Suppress the summary line |

### Exit codes (verified)

| Code | Meaning | Probed |
|---|---|---|
| 0 | completed, no selected failure class | `--fail-on=none` on `Stunts/happy` (3 exceptions, exit 0) |
| 1 | findings selected by `--fail-on` | default run on `Stunts/happy` (3 exceptions) and `Stunts/dogfood` (45) |
| 2 | usage error | `--mode=bogus`; missing `--out` (usage printed) |
| 3 | I/O or output-ownership error | `--out=/tmp/…` — macOS `/tmp` is a symlink → `refused: output path contains a symlink component` |
| 4 | malformed source / policy / previous-report contract | non-JSON `--policy` → `malformed policy '…': InvalidJson` |

### Outputs

Default (`--format=all`): `report.json` + `REPORT.md` + `site/`
(`index/density/coverage/alignment/changes/exceptions.html` + `audit.css`),
plus a `.boris-content-audit-output` marker. `--format=json` →
`report.json` only.

### `report.json` shape (verified, `Stunts/happy`)

```json
{
  "format_id": "boris-content-audit",
  "schema_version": 1,
  "tool_version": "0.1.0",
  "mode": "poetry",
  "source_root_label": "content",
  "source_revision": null,
  "policy_digest": "<sha256>",
  "collection_filter": [],
  "scope": {"type": "all", "totals": "global"},
  "totals": {"records_discovered": 3, "source_records": 0, "poetry_records": 0,
    "other_records": 3, "excluded_records": 0, "mapped_poetry": 0,
    "orphan_poetry": 0, "ambiguous_poetry": 0, "malformed_records": 3,
    "dead_references": 0},
  "coverage_overall": {}, "coverage_by_collection": [], "coverage_by_type": [],
  "density": [],
  "alignment": {"counts": {}, "records": []},
  "exceptions": [
    {"kind": "malformed_record", "severity": "structural",
     "record_id": "guides/getting-started.md",
     "detail": "malformed record: missing_id"}
  ],
  "records": [
    {"id": null, "kind": "other", "collection": "guides",
     "source_path": "guides/getting-started.md", "status": null,
     "poetry_type": null, "alignment": null, "owner": null, "evidence": [],
     "verse_units": 0, "placeholder_units": 0, "substantive_units": 0,
     "malformed_units": 0, "density_in_band": false, "coverage": null}
  ],
  "delta": null
}
```

### Findings semantics (probed)

A page without a frontmatter `id` is `malformed_record: missing_id`
(severity `structural`) — `Stunts/happy` pages carry no `id`, so the
whole corpus is structural. The mailbox should render `exceptions[]`
(never swallow) and use `--fail-on` to choose the class the app surfaces
as a problem.

### App implications (#165)

- `--out` must be a **real path** — `/tmp` on macOS is a symlink and is
  refused (exit 3). Use a path under the app's container, never the content tree.
- Separate binary: locate/embed it alongside the engine and run through
  the coordinator's single `Process?` slot (no second subprocess).
- Read-only over the source (`--root` never mutated); atomic tool-owned output.

## 9. `boris-source-rag` — the pack-by-tool surface (probed 2026-08-19)

Standalone kit binary (**not** the embedded `boris`) and **not** the
product `--rag` build projection (that is the M7 edition row). App
surface: #166. Probe: `Stunts/dogfood` → 48 source files, 50 catalog
entries.

**Provenance:** same kit build as §8, `tool_version "0.1.0"` (sha256
`abbd12df…`; MANIFEST archives `d16048c4…`).

### Invocation

```
boris-source-rag [--root=DIR] [--out=DIR] [--profile=all|core|docs|tools]
                 [--pack-by=none|tool] [--max-bytes=N] [--split-size=N]
                 [--no-bundles | --bundles-only] [--quiet]
```

Default scan under `--root`: dirs `src docs content layouts scripts tools
 test SUPPORT`; files `AGENTS.md README.md CHANGELOG.md LICENSE build.zig
 build.zig.zon`. `--no-bundles` and `--bundles-only` are mutually
exclusive (exit 2).

### Exit codes (verified)

| Code | Meaning | Probed |
|---|---|---|
| 0 | success | default run on `Stunts/dogfood` → `Done: 48 source files, 50 catalog entries, 0 skipped` |
| 2 | usage | `--no-bundles --bundles-only` together (help printed) |
| 3 | I/O error | — |

### Output tree (default, verified)

`INDEX.md` · `UPLOAD-GUIDE.md` · `catalog.jsonl` · `catalog_meta.json` ·
`profile_manifest.json` · `part_manifest.json` · bundles
`boris-source-N.md` / `boris-docs[-N].md` / `boris-content[-N].md` ·
`files/**` (one markdown document per source path; omitted with
`--bundles-only`).

With `--pack-by=tool`: the same tree is emitted once per pack under
`packs/<name>/` (core, docs, content, and one per `tools/<name>/`); the
root keeps only `INDEX.md` (a router over the packs) and
`pack_manifest.json`.

### Manifest shapes (verified)

`catalog.jsonl` (one line per entry):

```json
{"rag_id":"meta/index","rag_path":"INDEX.md","category":"meta","title":"Source RAG corpus — INDEX","source_path":"","lang":"markdown","bytes":0}
```

`catalog_meta.json`:

```json
{"format":"boris-source-rag","schema_version":1,"tool_version":"0.1.0","profile":"all","split_size":524288}
```

`profile_manifest.json`: `{"profile", "source_files", "catalog_entries",
"skipped", "paths": [...]}`.

`part_manifest.json`: `{"profile", "split_size", "bundles": true,
"parts": [{"order", "profile", "file", "bundle", "part", "parts",
"bytes", "sources": [{"order", "source_path", "bytes"}]}]}`.

`pack_manifest.json` (`--pack-by=tool`): `{"format":
"boris-source-rag-packs", "schema_version": 1, "profile", "pack_by":
"tool", "packs_dir": "packs", "token_estimate_method": "bytes/4",
"total_bytes", "total_source_files", "packs": [{"name", "path",
"source_files", "bytes", "tokens_approx", "purpose", "answers"}]}`.

### App implications (#166)

- Never mutates `--root`; all output goes to `--out`.
- Default `--max-bytes=524288` and `--split-size=524288` bound bundle sizes.
- A "Source RAG export" verb can run the default profile, then reveal
  `--out` in Finder (or open `INDEX.md`). Same single-`Process?`-slot
  rule as §8.
