# Engine Contracts — probed hands-on against afterparty (M2–M8 design input)

**Date:** 2026-08-17 · **Engine:** afterparty, `boris/0.8.1` (kit pin
was `b82e9e2` when these tables were probed; current pin is `6b930b7`,
which contains A1/A14/A7 + A3/A4/A13 — record only, tables not re-probed)
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
