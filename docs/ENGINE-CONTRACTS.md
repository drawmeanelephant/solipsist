# Engine Contracts — probed hands-on against afterparty (M2–M4 design input)

**Date:** 2026-08-17 · **Engine:** afterparty, `boris/0.8.1` · **Content:**
the afterparty dogfood site (25 pages, /tmp/apws)

Everything here was verified by running the binary and reading the real
responses/artifacts. It is the concrete contract surface the app's M3
(editor completion), M4 (live preview), and M5 (problems panel) are built
against. Authoritative schema twins live in the boris repo under
`docs/contracts/schemas/` — consume those, don't hand-roll.

---

## 1. `watch --serve` — the preview surface (M4)

### Invocation & discovery

```
boris watch --serve [--port N] --input <content-root>
```

- Default port **8090**; `--port 0` = ephemeral.
- **Port discovery:** stderr prints one parseable line on startup:
  ```
  preview: http://127.0.0.1:18090/  (auto-reload helper: http://127.0.0.1:18090/__boris/)
  ```
  For `--port 0`, parse this line (regex `127\.0\.0\.1:[0-9]+`) to find the
  ephemeral port. This is the only stderr line the app needs to parse.
- Run with `cwd = project folder` (containment: `--input` may be absolute,
  but outputs — including `dist/` — are workspace-relative; see
  A7/ENGINE-WORK-AND-DESIGN).
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
