# Solipsist — Roadmap

**Date:** 2026-08-18
**Status:** the goals document. Spatial model:
[`HARNESS.md`](HARNESS.md). Boris surface:
[`BORIS-CAPABILITIES.md`](BORIS-CAPABILITIES.md).

---

## 1. What we are building

Solipsist is Radio UserLand’s job in Mail’s body: a native Mac
workstation that broadcasts a local Boris publication and refuses to
invent anything either the HIG or a Boris contract already named.

It is a **harness**, not a better compiler and not a Markdown IDE.
Boris stays a better Boris. We vendor the binary, file issues, render
contracts, host the surfaces we will not rewrite.

```
Settings → Sources (the account book; not a column)

┌──────────────────┬─────────────────────────────┬──────────────────┐
│ MAILBOXES        │ READING                     │ DRAWER           │
│ Source as        │ Message list + reading      │ Profile, page    │
│ account header;  │ pane for the selected       │ fields, options  │
│ folders under it │ message                     │                  │
└──────────────────┴─────────────────────────────┴──────────────────┘
Companion windows we host: Preview (full site) · Editor (boris-editor)
Compose window we author: native buffer (`⌘⇧C`) + Oliver preview (#106)
```

M2–M8 shipped a flatter cut (source list + tabbed play). M10 is the
recut to the diagram above. Spatial detail: [`HARNESS.md`](HARNESS.md).

**Engine baseline:** afterparty `boris/0.8.1`. **Pinned kit:** `6b930b7`
(`6b930b7bd35a1803b365a073c226df22631dc3f7`). Contains A1/A14/A7 +
A3/A4/A13 (boris#648 / #643 / #642 / #641). Remaining access issue:
A5 as a discussion (`docs/issues/README.md`).

---

## 2. North-star success

Open a folder of Boris content — or **File / Settings → Add Git
Repository…** a clone URL into a user-chosen folder — → it is added
as a **source** in Settings (File → Open… writes the same store) →
it appears as an account header with mailboxes underneath (Pages
folders come from `graph.parent`, not the disk) → the reading place
shows the selected mailbox’s messages and a reading pane for the
selected page → the drawer shows the publication profile and that
page’s fields from `completion.json` → Plan / Validate / Build are
menu verbs that surface every diagnostic and exit code → Preview
reloads the full site through `watch --serve` (the reading pane
reuses that watch; port and ready come from A1 `--watch-json`, not
a regex) → Edit opens `boris-editor` against the selected page →
Build All fans the profile out to HTML targets and editions (IR,
RAG, Context, llms, RSS, sitemap, search) → Publish runs GitHub
Pages evidence (Boris-powered, we do not need full GitHub access to
*use* the target), Standard.site, or Nostr with the Proof Pack
attached. This project’s own public face ships via Cloudflare Pages
(`site/`).

No scraped prose. No homegrown graph. No third settings store.

---

## 3. Goals

### v1 must

| Goal | Why |
|------|-----|
| One-window Mail-grade chrome | Settings for sources; mailboxes; reading pane; inspector drawer; real menus |
| Local source via security-scoped bookmark | The first account; added in Settings (Open… is the same store) |
| Graph as a workable list | Trunks, satellites, status, relations — from contracts |
| Profile is `boris.json` | D2. Drawer writes it. `plan` lints it |
| Coordinator verbs | Plan, Validate, Build, Check, Impact, Stop — each a menu item |
| Diagnostics as a place | `html-build-report` / IR `build-report` / check findings, clickable |
| Engine-owned preview | Companion; `watch --serve` + SSE; no app HTTP server |
| Hosted editor | Companion; `boris-editor` token URL; opened from the selected page; link-out fallback |
| Native compose | `Sources/Compose/`; Oliver preview; explicit save → validate |
| Outputs fan-out | Every profile target and edition, isolated, reported |
| Publication console | GH Pages evidence (Boris-owned workflow + audit), Standard.site, Nostr — secrets on stdin |
| Proof Pack visible | `boris-package` evidence, read-only |
| Clone a remote publication into a Local source | Settings is the account book. A URL is how people who do not live in this repo get a folder. Same store as Open…. |
| Pages folders from the graph | Trunks as mailbox folders. From `graph.parent` only — never a disk walk. Dogfood gate is 7 trunks. |
| Watch events from the A1 contract | Pin `6b930b7` contains `--watch-json` / `serve-started`. Preview and the letter take port / ready from the contract + SSE — no port regex. |
| Sandboxed, bundled, pinned | D6, D7. Unknown `schemaVersion` degrades (D8). Pipeline ✅ (#78). |
| Notarized DMG a stranger can download | Operator. First `v*` release + clean-Mac proof (#110 / #111). |

### v1 must not

- A frontmatter parser, a graph algorithm, or a homegrown Markdown
  renderer in Swift (Compose sniffs Oliver's boundary and paints
  tokens; Oliver/Boris parse)
- A Finder clone of the content tree in the sidebar
- An app-side HTTP server or `file://` preview
- Cloudflare / Vercel / Netlify as *in-app* deploy adapters or a
  `publication.target` we invent (Boris has not added `"cloudflare"`)
- Wasm / `compileBundle` *inside* Solipsist (subprocess isolation stays)
- Theme *authoring* (selection only)
- Migration labs as runtime
- iOS

### Later (named so they stay later)

- Compose **depth**: span diagnostics from Oliver, incremental
  highlight, front-matter form, Cooklang autocomplete, bundling
  `oliver` next to `boris`. The M10 gate is the window + save +
  preview seam (#106 / #108), not those.
- **GitHub as its own `SourceKind`** (OAuth / app password, not
  just a clone). The clone slice landed as M12:
  [#131](https://github.com/drawmeanelephant/solipsist/issues/131)
  → PRs #152/#153 (URL → folder → Local source). **M15** landed:
  device-flow OAuth + PAT fallback, Keychain token, working copy,
  Remote mailbox Sync, sign-out (PRs #180–#184;
  [`GITHUB-OAUTH-DESIGN.md`](GITHUB-OAUTH-DESIGN.md)). The remote
  *write* verbs (commit / push / PR authoring / issues mailbox)
  landed as **M16** (PRs #187–#190;
  [`M16-WRITE-REMOTE-DESIGN.md`](M16-WRITE-REMOTE-DESIGN.md),
  [#185](https://github.com/drawmeanelephant/solipsist/issues/185)).
- Content-audit mailbox (`boris-content-audit`)
- Source-RAG export for AI assist
- `validate --watch` once A5 exists (replaces save-triggered one-shots)
- Cooklang recipe-scale as a first-class mailbox (v1: available from
  the page inspector when the corpus has recipes)
- A Pull Requests mailbox (the issues mailbox filters PRs out of the
  REST list; a dedicated PR mailbox stays later)
- Width-adaptive list-left-of-letter split (M10 default is stacked)
- The fart app (CI job reserved, `make fart` refuses; do not build it)

---

## 4. Where we are

| Milestone | Status |
|-----------|--------|
| **M0** Bootstrap | ✅ |
| **M1** Engine spike | ✅ `make run-spike` decodes the IR contracts |
| **M2** Chassis | ✅ sources / play / drawer / companion slots; File → Open… adds a local source |
| **P** Project subdomain | ⛔ withdrawn — the public site ships via Cloudflare Pages (`site/`) |
| **M3** Play & inspect | ✅ gate — list from `graph.json`, drawer fields (#72, #80) |
| **M4** Coordinate | ✅ gate — menu verbs, exits visible (#73, #80) |
| **M5** Preview | ✅ gate — `watch --serve` companion (#74, #81) |
| **M6** Author | ✅ gate — `boris-editor` host + link-out (#75, #81) |
| **M7** Outputs | ✅ gate — Build this / Build all fan-out (#76, #81) |
| **M8** Publish | ✅ gate — stdin secrets, Standard.site / Nostr buttons (#77, #82/#84) |
| **M9** Ship | ✅ release pipeline, testdata, pin bump (#78); notarized `v*` + clean-Mac proof are #110/#111 (Apple-account only) |
| **M10** Mail body | ✅ Settings, mailboxes, reading pane, hosted Edit, native Compose ([#98](https://github.com/drawmeanelephant/solipsist/issues/98); children #99–#102, #106) |
| **M11** Prove the Mail body | ✅ Help audit + test pass ([#123](https://github.com/drawmeanelephant/solipsist/issues/123); #124/#125 → PRs #126/#127/#128) |
| **M12** Clone | ✅ Add Git Repository… → Local source ([#131](https://github.com/drawmeanelephant/solipsist/issues/131); PRs #152/#153) |
| **M13** Graph folders | ✅ trunk mailboxes from `graph.parent` ([#142](https://github.com/drawmeanelephant/solipsist/issues/142); #144–#146 → PRs #154/#155/#156) |
| **M14** Watch contract | ✅ A1 `--watch-json` + letter SSE ([#143](https://github.com/drawmeanelephant/solipsist/issues/143); #147/#148 → PRs #157/#158) |
| **M15** GitHub source | ✅ OAuth device flow + `SourceKind.github` payload, working copy, Remote mailbox Sync, sign-out ([#179](https://github.com/drawmeanelephant/solipsist/issues/179); PRs #180–#184) |
| **M16** Write the remote | ✅ commit / push / PR authoring / issues mailbox ([#185](https://github.com/drawmeanelephant/solipsist/issues/185); PRs #187–#190) |

**Gates plus depth.** M3–M8 closed as gates (#72–#77). The #87 depth
batch then landed: first-run and problem→page (#88/#94), graph filter /
activity / plan document (#89/#96), profile 1:1 + execution knobs +
`recipe-scale` (#90/#95), Standard.site family + package + readable
proof (#91/#93). Then **M9 ship** (#78), the **M10 Mail-body cut**
(#98 + #99–#102, #106), **M11 prove** (#123), **M12 clone**
(#131), **M13 graph folders** (#142), and **M14 watch contract**
(#143) all landed and closed. Remaining ship is Apple-account only
(#110 notarized `v*` DMG, #111 clean-Mac proof) — operator,
blocked on a paid team ID. Do not grow `MainWindow`.

---

## 5. Milestones

Each milestone is independently demoable. Gate is what you can *do*,
not what files exist. Boris surfaces are the compiler verbs and
artifacts the slice consumes — we do not reimplement them.

### M0 — Bootstrap ✅

Repo, XcodeGen, entitlements, embed script.

### M1 — Engine spike ✅

`BorisEngine` runs the binary. Decodes `build-report.json`,
`manifest.json`, `graph.json`, `completion.json`, analysis reports.
Gate: `make run-spike` → `SPIKE OK`.

### M2 — Chassis ✅

`MainWindow`: source list, play host, inspector drawer, Preview/Editor
window groups. `Source` / `WorkspaceSelection` / `WorkspaceStore`.
File → Open… bookmarks a local folder.
Gate: empty chrome is Mail-shaped; Open adds a source; spike unchanged.

### P — Project subdomain (parallel, plenty early) — ⛔ **withdrawn (2026-08-17)**

**Decision:** not building the Worker/Wasm subdomain host. The public site
ships via Cloudflare Pages (`https://solipsist.filed.fyi` — see `site/` and
`.github/workflows/deploy-site.yml`); a separate Worker + R2 + Wasm host
adds infra for no user-facing gain. The boris-side surfaces
(`hosts/cloudflare-worker`, `compileBundle` Wasm) stay in the operator
reviews, but this repo does not stand up a project subdomain on them.

**Goal.** Solipsist has a public URL that is itself a Boris publication,
without depending on GitHub being up or on us having full GitHub access.

This is **project infrastructure**, not a feature of the Mac app, and
not a new `publication.target`. Boris already ships the glue:

| Boris surface | Role |
|---------------|------|
| `hosts/cloudflare-worker/` | Official #301 host: `POST /compile`, limits, R2. Not a second Boris |
| `compileBundle` Wasm (`boris-embed-small.wasm`) | Parse / graph / render / evidence in the isolate |
| R2 `ARTIFACTS` | Successful compiles only; failed validation does not upload |
| Workers Free | Module is ~331 KiB gzip; live warm compile measured under the 10 ms CPU budget |
| GitHub Pages | Still the *in-app* Pages target (M8): Boris `.nojekyll`, artifact pack, Actions workflow, `github-pages-audit`. We surface that contract; we do not operate GitHub as our own host |

**How it is used.** A Solipsist content tree (mission, roadmap, dogfood)
is posted to the Worker as a source bundle. Wasm compiles it. Artifacts
land in R2. A custom subdomain (Workers route or a tiny GET in the same
host) serves the compiled HTML. Trusted authors only — same posture as
the host README. Generated pages are a *site*, not application UI.

**Not this card.** Embedding Wasm in Solipsist. Adding `"cloudflare"` to
`publication.target`. The #300 Containers / `boris-job-runner` path
(native `boris` in a container — different host, not Free-tier Wasm).

**Gate.** `https://<subdomain>` serves a Boris-built Solipsist page,
recompiled through the Worker, no GitHub required for the publish step.
Local smoke (`node hosts/cloudflare-worker/test.mjs`) stays the
no-credentials check.

**Lane.** New folder if it lives in this repo (`hosts/` or `site/`);
operator steps stay out of `Sources/`. Does not touch Chrome, Play, or
Engine.

### M3 — Play & inspect ✅ (#72, PR #80)

**Gate-verified 2026-08-17:** `Stunts/dogfood/` builds against the pinned
kit (`boris/0.8.1`, `b82e9e2`) to **45 pages / 7 trunks** in `graph.json`
(`boris build --out .boris` → `ok: wrote IR under .boris (45 page(s))`,
`graph.json` role count: 7 trunks).

**Goal.** Selecting a local source shows the publication as a list you
can act on, and the drawer shows minutiae of that selection.

| Boris surface | Where it appears |
|---------------|------------------|
| `graph.json` / `manifest.json` | Play: trunks, satellites, status, tags, parent |
| `completion.json` | Drawer: entity ids, parent targets, relation kinds, layout slots |
| `boris.json` (publication profile) | Drawer: site, publication, targets, editions — 1:1 with schema |
| `jobs` / `incremental` / `quiet` | Drawer: app plist only (D2) |
| `check` findings (unreferenced) | Badge on the list, not a broken build |

**Gate.** Open the dogfood `content/` folder → play lists 45 pages /
7 trunks from `graph.json` → select a page → drawer shows its
completion-backed fields → profile keys are editable and write
`boris.json`. No monospaced dump.

**Lanes.** Local play, Inspector, Contracts (profile / completion /
graph mirrors).

### M4 — Coordinate ✅ (#73, PR #80)

**Goal.** Solipsist is the coordinator Boris does not ship: it maps
profile entries to discrete invocations and aggregates machine results.

| Boris surface | Verb |
|---------------|------|
| `boris plan --profile` | Plan (stdout declaration) |
| `boris validate --report` | Validate (artifact-free; save-triggered next to watch) |
| `boris build --report` / `--timings` | Build this / Build all |
| `boris check --report` | Check (advisory) |
| `boris impact ID --report` | Impact (selected page) |
| `boris --version` | Status bar identity |
| `init` | File → New Project… |

**Gate.** From the menu: Plan a real profile (exit 2 on invalid, show
the declaration), Validate, Build one HTML target, Check, Impact.
Problems list is clickable (`sourcePath`/`line`/`column` may be null).
Every non-zero exit is visible. Watch is paused for the build lane.

**Lanes.** Engine (S0 methods), Local play (activity / reports),
Inspector (stale-plan indicator).

### M5 — Preview

**Goal.** The site is a companion window, engine-owned.

| Boris surface | Where |
|---------------|--------|
| `watch --serve --port 0` | Preview window, WKWebView on `/__boris/` |
| SSE `event: reload` | Reload; no prose parse except today’s port line |
| A1 `serve-started` | Replaces the port regex once filed and pinned |
| A13 recovery (post-pin) | Watch stays up on `GraphValidationFailed` |

**Gate.** Preview ▶ loads the built tree, reloads on save, Stop tears
down with SIGTERM. Multi-target serves the first canonical target.
Entitlement: `network.server`.

**Lanes.** Preview companion, Engine (`previewStart/Stop`).

### M6 — Author

**Goal.** Writing happens in Boris’s editor. We host it.

| Boris surface | Where |
|---------------|--------|
| `boris-editor` | Editor companion at `BORIS_EDITOR_URL=` (A14) |
| Safe file API / save | Inside the hosted editor — we do not reimplement |
| `recipe-scale` | Page inspector, when the corpus has Cooklang |
| Input format | Drawer: markdown / textile / cook (profile `input_format`) |

**Gate.** Edit ▶ spawns the host with `--boris` pointing at the bundled
engine, loads the token URL, or offers “Open in Boris Editor”. SIGTERM
on close. Link-out is the accepted fallback if WKWebView/CSP fails.

**Lanes.** Editor companion. Depends on A14 for a pinned launch line.

### M7 — Outputs

**Goal.** Everything a profile can declare, the console can run.

| Boris surface | Play / drawer |
|---------------|----------------|
| HTML targets | List: name, output, theme/layout, layout rules, public |
| Theme catalog | Picker over bundled / project `themes/` (selection, not authoring) |
| Per-target `sitemap` / `rss` / `llms` | Nested under the target |
| `editions.ir` | `--out` |
| `editions.rag` | `--rag` / `--complete` / `--scope` / `--split-size` |
| `editions.context` | `--context` |
| Rendered search index | Shown as a target projection (compiler-owned) |
| `boris-search-index` | Optional post-pass if we index already-built HTML |
| `boris-testdata` | CI fixtures for this slice |

**Gate.** “Build all” fans the profile out in isolated invocations,
profile order, per-entry report + timings. “Build this” runs one row.
Fail-fast per target as Boris does. No `--bundles-only` control (no-op).

**Lanes.** Local play (outputs list), Inspector (per-entry fields),
Engine (`buildTarget` / `buildEdition` / `buildAll`).

### M8 — Publish

**Goal.** Broadcast. The desktop is the station.

| Boris surface | Flow |
|---------------|------|
| GitHub Pages | Profile → plan → build → evidence read-only. Push is Boris’s Actions workflow when the user has a repo; **we do not need full GitHub access** to ship or demo this surface. GitHub as a sidebar *source* stays later |
| Standard.site | `login` (browser OAuth or app-password on stdin) → `plan`/`records` → `publish` → `verify` → opt-in `smoke`. Exit classes 4–9 surfaced |
| Nostr | `plan` → `sign --key-stdin` → `publish` to relays, per-relay evidence |
| Proof Pack | `boris-package` archive; MACHINE-READABLE-VERSION + SHA256SUMS shown |
| `github-pages-audit` | Optional post-publish observer |
| Evidence chain | `_boris/proof/` rendered read-only in play |

**Gate.** One Standard.site or Nostr publish from the menu, secrets only
on stdin, evidence visible, no key in argv/env/profile/logs.
`network.client` entitlement on. GitHub Pages at least shows plan +
proof without performing the git push.

**Lanes.** New `Play` sections + Engine publication methods. GitHub
source is its own folder (`Workspace/GitHub/`, `Play/GitHub/`) and must
not block the local publish flows.

### M9 — Ship ✅

**Goal.** A notarized Mac app that does not need Zig at runtime.

- Codesign, notarize, DMG
- Pin recorded where the build can read it: `6b930b7` (A1/A14/A7 +
  A3/A4/A13). Preview still hosts `watch --serve`; A1 `--watch-json`
  is a follow-on, not this card.
- `boris-testdata` fixtures in CI next to `make run-spike`
- Clean-Mac proof: no Zig, no kit folder, bundled engine only
- Window restoration, Open Recent (= persisted sources), Help

**Gate.** Download the build on a machine without this repo, open a
folder, plan, validate, build, preview.

Landed 2026-08-18 (#78). Remaining ship is Apple-account only
(#110 notarized `v*` DMG, #111 clean-Mac proof — operator, blocked on
a paid team ID).

### M10 — Mail body ✅

**Goal.** The window is Mail, not a tabbed workbench. Sources live in
Settings. The left pane is a mailbox tree. The center is messages plus
a reading pane. Edit hosts `boris-editor` from the selected page.
Compose is the native buffer (`⌘⇧C`) over that page's `sourcePath`.

This is a chrome recut, not a new compiler surface. Contracts,
coordinator verbs, publish flows, and the subprocess boundary do not
move. [#78](https://github.com/drawmeanelephant/solipsist/issues/78)
does not grow to absorb this.

| Surface | Where it appears |
|---------|------------------|
| Settings → Sources | Account book: add / relocate / remove local sources (GitHub later). Same `WorkspaceStore` as File → Open… |
| Mailbox sidebar | Source as account header; Pages / Outputs / Publish / Plan / Activity as mailboxes. Nested Pages folders only from `graph.json` (`parent`), never from walking the disk |
| Reading place | Message list of the selected mailbox + reading pane for the selected page (watch URL if up; contract summary if not) |
| Full-site Preview | Companion, unchanged |
| Editor | Companion, opened from the selected page; link-out fallback |
| Compose | Native window (`Sources/Compose/`); Oliver preview; explicit save → validate |
| Drawer | Still minutiae of the selection, not the account book |

**Gate.** Settings → Sources adds a local folder that also appears as
an account header. Selecting Pages shows the graph as a message list.
Selecting a page shows a reading pane (watch URL or summary — never
`file://`, never a Swift Markdown renderer). Outputs / Publish / Plan
/ Activity are mailboxes, not tabs. Edit ▶ on a selected page opens
the hosted editor. Compose ▶ opens the native buffer and saves
through the coordinator. `SKIP_EMBED_BORIS=1 make build` +
`make test` green.

**Lanes.** Settings, Mailboxes, Reading, Editor wiring, Compose —
paths in [`HARNESS.md`](HARNESS.md) §4. Tracker
[#98](https://github.com/drawmeanelephant/solipsist/issues/98);
compose [#106](https://github.com/drawmeanelephant/solipsist/issues/106);
cards in [`cards/`](cards/README.md). Implementation design:
[`M10-DESIGN.md`](M10-DESIGN.md).

**Not this milestone.** Compose depth (diagnostics, bundle `oliver`).
GitHub as a source. Finder sidebar. In-app HTTP server. Growing #78.

Landed 2026-08-18 (#98; children #99–#102, #106 → PRs #104/#105/#108/#113).

### M11 — Prove the Mail body ✅

**Goal.** Prove the recut: Help and empty states match the Mail-body
window, and a contract test pass pins the drift that M10's recut
introduced.

| Track | Issue | PR |
|-------|-------|----|
| Chrome / Help | [#124](https://github.com/drawmeanelephant/solipsist/issues/124) | [#126](https://github.com/drawmeanelephant/solipsist/pull/126) |
| Tests | [#125](https://github.com/drawmeanelephant/solipsist/issues/125) | [#127](https://github.com/drawmeanelephant/solipsist/pull/127), [#128](https://github.com/drawmeanelephant/solipsist/pull/128) |

**What shipped.** `docs/help.md` rewritten from the M3 source-list /
play-tabs model to the Mail body; every `Commands.swift` verb and
shortcut rowed. Empty-state / first-run copy and VoiceOver labels
match. Help-vs-Commands audit test (`HelpAuditTests`) fails loud on
any undocumented verb or shortcut. Letter-URL rule pinned verbatim
(`/{GraphNode.id}.html`, no `content/` injection, no extension
swap). `WorkspaceMailbox.display`/displayName/symbolName coverage
completed.

**Gate.** `SKIP_EMBED_BORIS=1 make build` green · `make test` 205
tests 0 failures · `make lint` 0 violations · CI `app` / `fixtures`
/ `lint` / `spike` all pass.

### M12 — Clone ✅

**Goal.** A remote publication becomes a Local source the way a
folder does. Settings → **Add Git Repository…** clones a URL into
a user-chosen directory, then the existing `addLocal` bookmark.

This is **not** GitHub OAuth and **not** a `SourceKind.github`
payload. A clone is a folder. We already add folders.

| Surface | Where |
|---------|--------|
| `/usr/bin/git clone` | Settings + File menu. One-shot `Process`, not `BorisEngine` |
| Branch badge | Settings row (and sidebar detail if it already has a second line) when `workspaceRoot/.git` exists |

**Gate.** Settings → Add Git Repository… a public `https://` URL
into a new folder → it appears as a Local source and the sidebar
can open it. An existing checkout shows its branch. Failed clone
shows git’s exit / stderr. No live clone in CI.

**Lane.** Settings / `Sources/Workspace/Git/`. Card:
[`cards/GIT-CLONE.md`](cards/GIT-CLONE.md). Issue
[#131](https://github.com/drawmeanelephant/solipsist/issues/131).
Parallel with #110. Do not share files with M13 or M14.

**Not this milestone.** Commit / push / pull / fetch UI. GitHub
app password or OAuth. Fake **Add GitHub…**. Expanding #110 / #111.

Landed 2026-08-18 (#131 → PRs #152/#153). The live gate also
caught and fixed the sandboxed-git trap: `/usr/bin/git` is an
`xcrun` shim that refuses to run inside the App Sandbox, so
`GitClone` resolves the real Command Line Tools binary.

### M13 — Graph folders ✅

**Goal.** Pages folders come from the graph. Dogfood shows **7
trunk folders** under Pages. Selecting a trunk filters the letter
list. Unknown `mailbox` is never rewritten to `pages`.

M10 stored `mailbox` as an open string and displayed only five
tokens. Trunks were named then and deferred. Do not invent a
second selection field. `mailbox` becomes the trunk id.

| Surface | Where |
|---------|--------|
| `graph.parent` / trunk nodes | Sidebar children under Pages |
| Unknown `mailbox` | Display verbatim; center switch does **not** treat it as Pages |
| Trunk mailbox | Reading list filters to that parent. Pages still means all |

**Gate.** Open dogfood → Pages shows 7 trunk folders from
`graph.json`. Selecting a trunk shows only that trunk’s pages.
Selecting Pages shows all. A stored unknown mailbox survives
relaunch and is not coerced to `pages`. `SKIP_EMBED_BORIS=1 make
build` + `make test` green.

**Lanes.** Workspace (unknown-mailbox rule) → Mailboxes (sidebar)
→ Reading (filter). Tracker
[#142](https://github.com/drawmeanelephant/solipsist/issues/142);
children #144 / #145 / #146. Cards in [`cards/`](cards/README.md).

**Not this milestone.** Walking `content/` as Finder. Status / tag
folders. Persist outline expansion. Engine. GitHub source.

Landed 2026-08-18 (#142; #144 → PR #154, #145 → PR #155, #146 →
PR #156). Live gate on `Stunts/dogfood`: 7 trunk folders, trunk
click writes the id, Pages restores all 45, stale id shows empty.

### M14 — Watch contract ✅

**Goal.** Preview and the letter take port / ready from A1
`--watch-json` / `serve-started`, not a port regex. The reading
pane reloads on the existing SSE `event: reload` without a second
`Process`.

The pin contains A1 (boris#648): `--watch-json` emits NDJSON
(`hello` schema 1 → `build-*` → `serve-started` with url / helper
/ port → `watch-stopped` on SIGTERM). The prose port regex is
gone; `build-failed` / `watch-error` / unexpected `watch-stopped`
are surfaced, never swallowed.

| Boris surface | Where |
|---------------|--------|
| `--watch-json` + `serve-started` | Engine `WatchServer`; Preview binds the helper URL |
| SSE `event: reload` | Reading pane observes the existing session |

**Gate.** Preview ▶ starts with `--watch-json`. `serve-started`
is how we learn the port. The letter reloads on rebuild without
re-selecting the row. No second watch. No `file://`. Port regex
is fallback then gone in the same PR if the pin is honest.

**Lanes.** Engine + Preview (A1 consume), then Reading (letter
SSE). Tracker
[#143](https://github.com/drawmeanelephant/solipsist/issues/143);
children #147 / #148. Cards in [`cards/`](cards/README.md).

**Not this milestone.** A5 `validate --watch`. A15 `open=` (app
already appends it; pin-follow). A second `Process`. Growing
`WatchServer` argv on the letter card.

Landed 2026-08-18 (#143; #147 → PR #157, #148 → PR #158). Live
gate: Preview starts with `--watch-json`, the helper URL comes
from `serve-started`, and a saved page reloads the letter via SSE
within a second, no re-select.

---

## 6. Capability coverage

Every afterparty surface we intend to harness, and when. If it is not
here, it is not a v1 promise.

| Boris capability | Milestone | How Solipsist uses it |
|------------------|-----------|------------------------|
| Markdown / Textile / Cooklang input | M3–M6 | Profile `input_format`; cook recipe-scale in the drawer |
| Closed frontmatter | M3, M6 | Inspector from `completion.json`; editor owns the buffer |
| Trunk/Satellite graph, wiki-links, includes, relations | M3, M13 | Play list from `graph.json`; M13 trunks as Pages folders |
| HTML + layouts + theme catalog | M4, M7 | Build target; theme picker |
| `validate` | M4 | Save-triggered problems; A5 later |
| `watch --serve` + SSE | M5, M10, M14 | Preview companion; M10 reading pane reuses the same session; M14 letter listens to SSE |
| `--watch-json` (A1) | M14 | Replaces port regex + watch prose. Pin already contains it. |
| `plan --profile` | M4, M8 | Settings lint; publish prelude |
| `build --report` / `--timings` | M4, M7 | Results + Activity |
| IR (`manifest` / `graph` / `completion` / `build-report`) | M1, M3, M7 | Decode, list, inspect, export |
| RAG / Context / llms | M7 | Edition rows |
| RSS / sitemap / search index | M7 | Target projections |
| `check` / `impact` | M4 | Advisory play + selected-page impact |
| `init` | M4 | File → New Project… |
| `recipe-scale` | M6 | Drawer, cook corpora only |
| `boris-editor` | M6, M10 | Companion (A14); M10 opens it from the selected page |
| Oliver (`oliver render`) | M10 | Compose preview; Engine-owned subprocess; not a Swift parse |
| GitHub Pages + audit | M8 | In-app evidence; Boris workflow owns push; we are not the GH operator |
| `hosts/cloudflare-worker` + `compileBundle` Wasm | **P withdrawn** | Public face is Cloudflare Pages (`site/`). Not in-app. |
| `boris-job-runner` / CF Containers (#300) | parked | Different host (native binary in a container), not the Free Wasm path |
| Standard.site family | M8 | Native flow, stdin secrets |
| Nostr plan/sign/publish | M8 | Native flow, `--key-stdin` |
| Proof Pack (`boris-package`) | M8 | Read-only evidence |
| `boris-testdata` | M9 | CI fixtures |
| `boris-content-audit` / `boris-source-rag` | later | Named, not scheduled |
| `boris-migration-lab` | out of v1 | — |
| Wasm *inside the Mac app* | never (v1) | Subprocess isolation. The Worker host is the embed path Boris chose |

---

## 7. Cross-cutting (every milestone)

- **Menus first.** If it is not in the menu bar, it is not a feature.
- **D2.** Output-changing settings write the profile; machine state
  writes the plist; the drawer is a view, never a third store.
- **D8.** Unknown/newer `schemaVersion` → degrade, banner, no crash.
- **D11.** Never touch the boris repo. Never reimplement semantics.
  Never swallow diagnostics or exit codes. Subprocess isolation.
  Never mutate the content tree except on an explicit save.
- **One `Process?` slot.** Build lane stops watch; `validate` may run
  alongside watch. Cancel = `terminationReason == .uncaughtSignal`.
- **Lanes.** Paths in `HARNESS.md`. Two agents, one file → recut.

---

## 8. Pickup (what to do next)

M10–M14, the post-ship batch (#165/#166/#167), **M15** (GitHub
source, PRs #180–#184), and **M16** (remote write verbs — commit /
push / PR authoring / issues mailbox, PRs #187–#190) all landed.
Remaining is **ship**, Apple-account only: notarization (#110) then
the clean-Mac proof (#111).

| Order | Track | Issue | Why this next |
|------:|-------|-------|----------------|
| 1 | Notarize | [#110](https://github.com/drawmeanelephant/solipsist/issues/110) | Apple secrets + first `v*` DMG. Operator. |
| 2 | Proof | [#111](https://github.com/drawmeanelephant/solipsist/issues/111) | Clean-Mac; blocked on #110. |

### Landed depth (do not redo)

| Track | Issue | PR |
|-------|-------|----|
| Usability | [#88](https://github.com/drawmeanelephant/solipsist/issues/88) | [#94](https://github.com/drawmeanelephant/solipsist/pull/94) |
| Play depth | [#89](https://github.com/drawmeanelephant/solipsist/issues/89) | [#96](https://github.com/drawmeanelephant/solipsist/pull/96) |
| Inspector depth | [#90](https://github.com/drawmeanelephant/solipsist/issues/90) | [#95](https://github.com/drawmeanelephant/solipsist/pull/95) |
| Publish depth | [#91](https://github.com/drawmeanelephant/solipsist/issues/91) | [#93](https://github.com/drawmeanelephant/solipsist/pull/93) |

### CLI vs app (honest)

Wired as a menu or pane: `build` (IR/HTML/target/edition/all),
`validate`, `watch --serve`, `check`, `impact`, `plan --profile`,
`init`, `recipe-scale`, `standard-site`
login/publish/plan/records/verify/sessions/logout/smoke, `nostr`
plan/sign/publish (per-relay verdicts), `boris-package`, `--version`,
`--timings` (activity duration), `--report`, Jobs / Incremental /
Quiet on the child.

Named in this file and **not** a product surface yet: browser OAuth,
`github-pages-audit`, A1 `--watch-json` (M14), trunk mailbox
folders (M13).

Out of v1 (unchanged): migration labs, Wasm in the app,
`validate --watch` until A5 + pin. Clone-as-local is M12 / #131.
GitHub source is M15 (landed); its remote *write* verbs are M16
(landed — commit / push / PR authoring / issues mailbox, PRs
#187–#190).
Compose **depth** (diagnostics, bundle `oliver`) stays Later; the
M10 compose window is #106 / #108.

#30 is a pr-cop dump, not a card.

Do not put Wasm in the app.

If another doc disagrees with this file about *when* a surface lands,
this file wins.
