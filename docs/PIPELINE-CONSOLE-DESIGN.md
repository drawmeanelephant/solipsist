# Solipsist — Pipeline Console Design (first native slice)

**Date:** 2026-08-17 (reconciled against the re-baselined docs)
**Status:** Draft — the console slice of `PLAN-MAC-APP.md`, aligned with
`MISSION.md`, `BORIS-CAPABILITIES.md`, `ENGINE-CONTRACTS.md`, and
`PLANNING-HANDOFF.md`.
**Engine baseline:** boris `afterparty` @ `b82e9e2` (v0.8.1 candidate), IR
schema `0.2.0`. Facts are from the afterparty contract docs, `src/main.zig`,
the hands-on probes in `ENGINE-CONTRACTS.md`, and — where marked
"binary-verified" — runs of the `boris` binary in the agent kit
(`SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/`, Darwin-arm64).

---

## 1. Thesis

Solipsist v1 is a native macOS **pipeline console**: the GUI that owns a
Boris project's *settings*, *validation*, *preview*, *multi-output
execution*, and *publication*, surfacing every result through Boris's
machine contracts.

It is **not** a from-scratch editor in v1. Boris ships `boris-editor`
(loopback Zig host + Svelte shell) and `completion.json`; the console's
authoring contribution is native ergonomics — a problems panel, a
completion-driven inspector, and preview — not a new Markdown IDE. (D4
decided: embed `boris-editor`, native ergonomics around it; see §4.2.)

The defining opportunity: Boris's publication profile is **declaration-first**.
`boris plan --profile` normalizes and validates it, but no shipped
coordinator executes a profile's targets and editions together. The profile
contract repeatedly defers to "a future coordinator." **Solipsist is that
coordinator** — it renders/edits the profile, validates it via `plan`, and
executes it by fanning out to Boris's discrete per-mode invocations,
aggregating the machine-readable results.

---

## 2. The Boris surface we wrap (verified)

### 2.1 Commands

| Command | Role in the console |
|---|---|
| `boris plan --profile PATH` | Read-only: normalize + validate the profile, emit the declaration JSON on stdout (exit 2 on invalid). The "settings lint". |
| `boris validate [opts] --report PATH` | Read-only, artifact-free HTML preflight + in-memory link audit. The save-triggered diagnostics lane. |
| `boris check` / `boris impact ID` | Graph health / transitive impact (advisory panel). |
| `boris build [opts]` | Execute one projection (HTML target, IR, RAG, context, llms, RSS) per invocation. |
| `boris watch --serve [--port N]` | Loopback HTTP preview + SSE `event: reload` (generation counter). HTML-only, implies incremental. |
| `boris init [DIR]` | Deterministic starter site + a starter publication profile. |
| `boris --version` | `boris/0.8.1` on stdout — engine identity before any build. |
| `boris recipe-scale` | Derived Cooklang scale view (read-only; Cook input only). |
| `boris standard-site …` / `boris nostr …` | Native publication flows (staged in §6, S4). |

### 2.2 Machine feedback (no prose parsing)

- `boris build --report PATH` and `boris validate --report PATH` →
  `html-build-report-0.1.0` JSON on **success and failure**. **No
  `pageCount`** (unlike IR `build-report.json`); `compilerId` +
  `ok`/`errorCount`/`diagnostics`. Diagnostic `sourcePath`/`line`/`column`/
  `id` may be `null` — the problems panel must tolerate nulls.
- `boris --out DIR` → `manifest.json`, `graph.json`, `completion.json`,
  `build-report.json` (IR).
- `boris check|impact --format json --report PATH` →
  `boris-documentation-intelligence` report.
- `boris … --timings` → `boris-timings` JSON on stdout (observational).
- **The only stderr line the app parses:** the `watch --serve` startup line
  — binary-verified as
  `preview: http://127.0.0.1:53202/  (auto-reload helper: http://127.0.0.1:53202/__boris/)`.
  Regex `127\.0\.0\.1:[0-9]+` yields the ephemeral port. The shutdown line
  (`watch: received shutdown signal, cleaning resources...`) is observed
  only, never parsed. Everything else is artifacts, not prose.

### 2.3 The profile (the settings source of truth)

`boris-publication-profile`, schema v1. Root fields:

```
format        = "boris-publication-profile"
schema_version= 1
input         # content root, default "content"
input_format  # "markdown" | "textile" | "cook"
site          # { url, title, description }
publication   # { target: "github-pages"|"standard-site", base_url, origin, base_path }
targets[]     # HTML targets
editions      # { ir, rag, context }
```

- A **target**: `name`, `output`, `public`, `theme` | `layout`,
  `layout_rules[]`, and per-target projections `sitemap{path}`,
  `rss{path,limit}`, `llms{path}`.
- **Editions** (machine exports): `ir{output}`,
  `rag{output, scope, split_size, bundles_only}`,
  `context{output, scope, split_size}`.
- `publication` requires exactly one `public` HTML target and the location
  triple; `base_url == origin + base_path` is enforced.

Strict JSON: unknown/duplicate keys, comments, coercion rejected.
Deterministic and offline; URLs are validated strings, never probed.

### 2.4 The execution gap (why the console exists)

- `boris plan --profile` stops before content discovery — it declares, it
  does not execute.
- `boris build --profile` does **not** run targets+editions. Verified in
  `src/main.zig`: the build path only uses `--profile` to load Standard.site
  verification surfaces and nostr alternate-links for *one* HTML compile.
- Targets and editions run through their own flags today: `--target
  NAME=DIR` (repeatable), `--out`, `--rag`/`--complete`/`--scope`/
  `--split-size`, `--context`/`--context-dir`/`--scope`/`--split-size`,
  `--llms`/`--llms-path`, `--rss`, `--sitemap`.

Consequence: **the console maps profile entries → discrete `boris`
invocations** and owns ordering, isolation, and result aggregation. If Boris
later ships a profile coordinator, the fan-out collapses to one `build
--profile` call behind a seam — we design for that from the start.

---

## 3. Settings model: settled D2 (two layers)

D2 is settled *against afterparty*, where a native project config now
exists. The split is by **what Boris consumes**:

1. **Project configuration → the Boris publication profile (repo-side).**
   `input`, `input_format`, `site`, `publication`, `targets`, `editions` are
   exactly the settings that change Boris output. They live in the profile
   (`boris init` writes it as `boris.json` — binary-verified — and the
   console reads/writes that file): the single shareable, reproducible,
   `plan`-validated truth. Duplicating them in an app plist would create two
   sources of truth that must be kept in sync on every build — the profile
   wins.
2. **Execution controls + machine-local state → app-side plist.**
   `jobs`, `incremental`, `quiet` are deliberately *not* plan identity per
   the profile contract, so they stay machine-local alongside window layout,
   recent projects, pinned preview port, and last-opened project.

**Rule:** if a setting affects Boris output, it lives in the profile; the
app plist never duplicates it. The console's settings UI is a form over the
profile schema — every control maps 1:1 to a profile key, and `Plan`
validates before anything executes.

### 3.1 Input model (the "multiple input sources" axis)

Boris is **one content root per invocation**. "Multiple input sources" maps
to three orthogonal axes, all modeled by the profile:

| Axis | Profile/flag | Console presentation |
|---|---|---|
| Content root | `input` | Folder picker (security-scoped bookmark) |
| Format adapter | `input_format`: markdown / textile / cook | Segmented control |
| Graph selection | `--scope` (entity id or collection prefix; editions only) | Scope field on RAG/Context editions |

The console shows these as three axes of one input — not separate "inputs" —
because that is what Boris does. No multi-root model Boris doesn't have.

### 3.2 Output model (the "multiple output directions" axis)

Two families, matching the profile:

- **Targets** — rendered HTML sites. Each is an independent output tree with
  its own theme/layout, layout rules, and optional sitemap/RSS/llms
  projections. Multi-target is first-class: isolated cache/staging,
  sorted-by-name execution, per-target fail-fast.
- **Editions** — machine exports of the same frozen graph: IR (manifest/
  graph/completion), RAG (working-context packs by default; `--complete`
  for the full corpus), Context bundle, `llms.txt`.

The console presents a single **"Outputs"** screen: a list of targets, each
expandable into its projections, plus an editions section. "Build all" runs
the fan-out; "Build this" runs one entry.

**Verified flag vectors** (from the agent-kit binary's `--help`; the
`ProfileExecutor` maps each profile entry to one of these):

| Profile entry | Execution vector |
|---|---|
| `editions.ir` | `--out DIR` (or `--no-rag`) |
| `editions.rag` | `--rag --rag-dir DIR [--scope VALUE] [--split-size BYTES]` |
| `editions.rag` (full corpus) | `--rag --complete` — rejects `--scope`/`--split-size`/`--bundles-only` |
| `editions.context` | `--context --context-dir DIR [--scope VALUE] [--split-size BYTES]` |
| target `llms` | `--llms` / `--llms-path PATH` |
| target `rss` | `--rss --rss-path PATH --rss-title … --rss-description … [--rss-limit N] --site-url URL` |
| target `sitemap` | `--sitemap` / `--sitemap-path PATH --site-url URL` |

Note: `--bundles-only` is a RAG-compatibility no-op (working packs are
bundle-style by design), so the console omits it.

---

## 4. UI shape

Three-pane `NavigationSplitView`, macOS-native.

```
┌───────────────┬──────────────────────────┬───────────────────────┐
│ Project       │ Outputs & Profile        │ Preview / Results      │
│ (sidebar)     │ (detail)                 │ (detail)              │
├───────────────┼──────────────────────────┼───────────────────────┤
│ • Content tree│ Targets (expandable)     │ Tabs:                 │
│ • Status      │   • theme/layout/rules   │  • Preview (WKWebView)│
│ • Page count  │   • sitemap/rss/llms     │  • Plan (declaration) │
│ • Diagnostics │ Editions                 │  • Build report       │
│   summary     │   • IR / RAG / Context   │  • Diagnostics        │
│ • Recent      │ Publication              │  • Timings            │
│   projects    │   • target + location    │  • Check / Impact     │
└───────────────┴──────────────────────────┴───────────────────────┘
        Toolbar: [Plan] [Validate] [Build all] [Preview ▶] [Stop]
        Status bar: engine version · last result · page/error counts
```

- **Sidebar** — thin display adapter over `graph.json`/`manifest.json` (no
  graph logic in Swift; Boris owns structure, Swift owns selection/order).
- **Detail (settings)** — the profile form. Every control maps to a profile
  key; `Plan` revalidates and shows the normalized declaration, with a
  "profile changed, plan stale" indicator.
- **Results** — machine artifacts rendered read-only: declaration JSON,
  `html-build-report`, diagnostics, `--timings`, check/impact reports.

### 4.1 Preview (D5: engine-owned)

No app HTTP server, no `file://`. The console runs
`boris watch --serve --port 0`, parses the one stderr startup line to find
the ephemeral port, and loads `http://127.0.0.1:PORT/__boris/` in a
`WKWebView` (the helper page owns the iframe + `EventSource`). SSE
`event: reload` (generation counter, first event fires on connect) drives
reload. Multi-target serves the first canonical target.

Entitlements: `network.server` (loopback listen). `network.client` only if a
theme loads remote fonts/CDNs — and for Standard.site/Nostr publication
(§6 S4).

### 4.2 Authoring bridge (D4 decided)

v1 ships **native ergonomics** around an embedded editor, not a full editor:

1. **Problems panel** — decode `validate --report` (save-triggered) +
   IR `build-report.json`; severity coloring, remediation, click-to-jump.
2. **Completion-driven inspector** — `completion.json` supplies entity ids
   (wiki-link `[[…]]`), `parent_targets`, `relation_kinds`, and the closed
   `layout_slots` set for frontmatter/theme inspection.
3. **Authoring itself** — **decided:** embed `boris-editor` by spawning its
   Zig host and pointing a `WKWebView` at its session-token URL. The
   sandbox/token/CSP mechanics need a spike (§9); the fallback if that fails
   is "Open in Boris Editor" (link out). No from-scratch native editor in v1.

---

## 5. Engine layer

One `actor BorisEngine` owns **one `Process?` slot**. No separate watcher
type. The actor serializes invocations and enforces the watch/one-shot
policy.

| Method | Boris invocation | Machine result consumed |
|---|---|---|
| `version()` | `boris --version` | stdout line |
| `plan(profile)` | `boris plan --profile P` | `boris-publication-plan` (stdout) |
| `validate(profile)` | `boris validate … --report` | `html-build-report-0.1.0` |
| `check` / `impact` | `boris check|impact … --report` | `boris-documentation-intelligence` |
| `buildTarget(entry)` | `boris build --target NAME=DIR …` | `--report` + `--timings` |
| `buildEdition(entry)` | `--out` / `--rag…` / `--context…` / `--llms…` | artifacts + `--timings` |
| `buildAll(profile)` | fan-out of the above, sequentially | aggregated result |
| `previewStart/Stop` | `boris watch --serve --port 0` | SSE reload + port line |

### 5.1 Execution policy (the coordinator)

Two lanes with different concurrency rules:

- **Build lane (writes `dist/` and editions):** stop the watch session
  first — Boris forbids concurrent invocations against one content root.
  UI shows "pausing preview…" and resumes after. Execute entries in profile
  order (targets sorted by name, then editions), each as a separate `boris`
  process, collecting `--report`/exit/`--timings` per entry.
- **Diagnostics lane (`validate --report` is artifact-free):** debounced on
  save, runs *alongside* `watch --serve` without touching `dist/` or cache.
  This is the live-diagnostics path until A1/A5 land. **Binary-verified
  safe:** `validate` exits 0 while watch is idle and mid-rebuild, and exits
  1 with a full report on broken content — the concurrent `validate` never
  disturbs the watch process itself.

**Watch robustness (binary-verified defect):** `watch` itself **exits**
(code 1) when a rebuild hits `GraphValidationFailed` (e.g. a duplicate id),
printing `error: rebuild failed with unrecoverable I/O error:
GraphValidationFailed` — contrary to the watch contract's "content failures
keep the watcher alive" claim. The app must detect watch death
(`terminationStatus == 1` after a rebuild) and offer "preview stopped — fix
and restart", and must not assume the watcher survives broken content. This
is a Boris defect to feed back (sibling of the known "watcher exit on failed
include rebuild" defect).

The fan-out is isolated behind `ProfileExecutor` so it can be replaced by a
single `build --profile` call if/when Boris ships a coordinator.

### 5.2 Contracts to mirror (Codable)

New mirrors beyond the M1 set, each `schemaVersion`-gated:

- `PublicationProfile` (schema v1) — the settings form's model.
- `PublicationPlan` (schema v1) — the `plan` declaration.
- `HTMLBuildReport` (`html-build-report-0.1.0`) — build/validate feedback
  (no `pageCount`).
- `TimingsReport` (`boris-timings`) — optional, observational.
- `Completion` (`boris-completion-1`) — **note `schema_version` is an
  integer `1`**, unlike the string `schemaVersion` on IR artifacts; gate on
  both forms.
- Existing `Manifest`/`Graph`/`BuildReport`/`AnalysisReport` — refresh
  against the published JSON Schemas under `docs/contracts/schemas/`.

**D8 policy:** unknown/newer `schemaVersion` → degrade to HTML-only + a
"newer engine" banner, never crash. Consider generating Codable mirrors from
the published JSON Schemas rather than hand-writing them.

---

## 6. Milestones (console slice; maps onto PLAN-MAC-APP M2–M8)

- **S0 — Re-baseline the engine layer.** Add `version()`, `plan()`,
  `validate()`, `--report`, `--timings`; pin afterparty `b82e9e2`; refresh
  decoders against the schemas. Gate: spike runs `plan` + `validate` + one
  `--report` build against a real project.
- **S1 — Console MVP.** Open project → render profile form → `Plan`
  validates → `Build` runs one HTML target → results pane shows the
  declaration, build report, diagnostics. Gate: open a folder, see settings,
  validate, build, see page/error counts — end to end.
- **S2 — Preview + authoring bridge.** `watch --serve` in WKWebView with SSE
  reload; save-triggered `validate --report` problems panel; embed
  `boris-editor` (D4) with link-out as fallback.
- **S3 — Editions fan-out.** IR/RAG/Context/llms in the Outputs screen with
  `scope`/`split_size`/`bundles_only` controls; per-edition results.
- **S4 — Publication console (native flows).**
  - **GitHub Pages:** profile → plan → build → packaging evidence shown
    read-only. Deployment is a GitHub Actions concern (boris ships the
    workflow); the console surfaces the plan + evidence, not the push.
  - **Standard.site:** `login` (browser OAuth or `--app-password` via
    stdin), `plan`/`records` (offline), `publish` (CAS reconciliation),
    `verify`, opt-in `smoke`. Secrets only via stdin, never argv/env.
  - **Nostr:** `plan` (offline) → `sign --key-stdin` (key via stdin, never
    argv/env/profile) → `publish` to configured relays with per-relay
    evidence. Offline-first: plan+sign need no network.
- **S5 — Multi-target + themes.** Full target editor, theme picker over
  `themes/`, per-target RSS/sitemap/llms projections.

---

## 7. Decisions locked (this doc)

| # | Decision |
|---|---|
| D2 | Profile = project-config truth (repo-side); app plist = `jobs`/`incremental`/`quiet` + UI state only |
| D4 | Editor scope: native ergonomics + embedded `boris-editor` (link-out fallback); no from-scratch native editor in v1 |
| D5 | Preview via `boris watch --serve` + SSE; no app HTTP server, no `file://` |
| D6 | Stay sandboxed; add `network.server` (preview) and `network.client` (publication/remote assets) |
| D7 | Pin afterparty `b82e9e2` (v0.8.1 candidate) as the tested contract |
| D8 | `schemaVersion`-gated decoders (both string and integer forms); degrade, never crash; codegen from JSON Schemas |
| — | One `Process?` slot in `BorisEngine`; no separate watcher type |
| — | Build lane stops watch; `validate` diagnostics lane runs alongside watch (verify at M3/M5) |
| — | Machine feedback via `--report`/`--timings`/`plan`; only the watch port line is parsed from stderr |
| — | Swift owns display/selection only; Boris owns all content semantics |

## 8. Explicitly out of scope for v1

- A from-scratch native editor (D4 decided: embedded `boris-editor` + native
  ergonomics; not a Markdown IDE).
- Cloudflare Pages / Vercel / Netlify / commodity deploy adapters.
- Wasm/`compileBundle` embedding (in-process engine remains off the table).
- Theme *authoring*; theme *selection* only.
- The migration labs and standalone `tools/` binaries (out of the app's
  runtime entirely).

## 9. Open questions / fact-check TODOs

1. **Boris Editor embed mechanics.** D4 decided: embed. The remaining work is
   the sandbox/token/CSP spike to load `boris-editor`'s session-token URL in
   WKWebView; link-out is the fallback if that fails.
2. ~~**Exact edition flag spelling.**~~ **Resolved** — binary-verified against
   the agent kit's `--help`; see the flag-vector table in §3.2.
3. **`plan` has no `--out`.** Re-run `plan` per settings change (cheap and
   deterministic). Revisit if plan artifacts land.
4. ~~**Concurrent `validate` + `watch --serve`.**~~ **Resolved** —
   binary-verified safe (see §5.1). New finding: watch exits on
   `GraphValidationFailed` rebuilds; the diagnostics lane must be
   `validate`, not watch stderr.
5. **`buildAll` ordering vs Boris's future coordinator.** Keep
   `ProfileExecutor` as the single replaceable seam.
6. **Security-scoped bookmarks across app updates** (bundle-id drift orphans
   bookmarks) — test before packaging, not during.
7. **Standard.site/Nostr secret handling under sandbox.** Passing the key
   via stdin through `Process` must never leak into argv/env/logs; confirm
   the FileHandle plumbing and the sandbox's network stance before S4.
