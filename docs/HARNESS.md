# Solipsist — Harness & Lanes

**Date:** 2026-08-18
**Status:** locked direction (spatial model + how we split work)
**Parents:** Radio UserLand × Mail, HIG pedant, contract pedant
This file is the product chassis and the agent-split. Goals live in
[`ROADMAP.md`](ROADMAP.md). If they disagree about where a surface
lives, this file wins.

M2–M8 shipped a flatter cut of this model (source list + tabbed play +
companions). **M10** is the recut to the Mail body named below. Do not
expand [#78](https://github.com/drawmeanelephant/solipsist/issues/78)
(M9 ship) into this chrome. What ships today is recorded in §7.

---

## 1. What we are

Solipsist is a **native Mac harness** for Boris. It does not try to be a
better editor, a better previewer, or a better compiler. It makes what
Boris already is — a lot — easy to enjoy from a one-window Mac
workstation, and it hosts the surfaces we refuse to rewrite.

Boris stays a better Boris. We file issues. We vendor the binary. We
render its contracts. We never reimplement its semantics.

---

## 2. Spatial model

Left to right, one main window. A Settings scene for the account book.
Companion windows for foreign surfaces.

```
Settings (not a column) — Sources: add / relocate / remove accounts

┌──────────────────┬─────────────────────────────┬──────────────────┐
│ MAILBOXES        │ READING                     │ DRAWER           │
│                  │                             │                  │
│ Source as        │ Message list of the         │ Options          │
│ account header;  │ selected mailbox, plus a    │ Profile / page   │
│ folders under    │ reading pane for the        │ fields / knobs   │
│ it (Pages,       │ selected message.           │ of the selection │
│ Outputs, …)      │ Noun selected here.         │                  │
└──────────────────┴─────────────────────────────┴──────────────────┘

Companion windows (hosted, not authored):
  • Preview   — full site; boris watch --serve in WKWebView
  • Editor    — boris-editor (Svelte) at its session-token URL
  • anything else Boris already built that we will not rewrite

Our chrome (authored):
  • Compose   — native buffer (`Sources/Compose/`, ⌘⇧C). Oliver
    renders the preview. Explicit save. Not a hosted companion.
```

Mail, not Finder, not Xcode. Accounts in Preferences. Mailboxes on the
left. Messages in the middle. The letter you picked, readable. Compose
is a separate window — the native buffer — not a tab in Play.

### Settings — the account book

A **source** is a place content lives or publishes: a local folder
(security-scoped bookmark), a GitHub repo, later whatever earns a
provider. The first source type is local. GitHub is the second.

Sources are **accounts**. They are added, renamed, relocated, and
removed in **Settings → Sources**, the way Mail adds accounts. File →
Open… and Open Recent still add a local source — that is the Mac verb
for a folder — but they write the same store the Settings pane shows.
The sidebar plus button is a shortcut to that add, not a second
inventory.

Do not hardcode "the open folder" as the app model. Hardcode `Source`.

Settings is a `Settings` scene, not a column, not a play tab, not the
drawer. Machine-local app state that is not selection-minutiae may
grow further panes here. D2 still holds: output-changing controls write
`boris.json`; machine state writes the plist; Settings and the drawer
are views, never a third store.

### Left — mailboxes

A mailbox tree, Mail-style. Each source is an **account header**.
Under it live that source's mailboxes:

| Mailbox | What it is | Was (M3–M8) |
|---------|------------|-------------|
| Pages | `graph.json` nodes as messages | Play → Pages tab |
| Outputs | profile targets / editions | Play → Outputs tab |
| Publish | publication console | Play → Publish tab |
| Plan | `plan --profile` as a document | Play → Plan tab |
| Activity | timings / job log | Play → Activity tab |

Nested folders under Pages are allowed when they come from the
**graph** (`parent`, later `status` / tags) — trunks as folders,
satellites as messages. They are not allowed when they come from
walking the content directory. This is not a Finder clone. `.boris/`,
`themes/`, and the rest of the project tree stay off the sidebar
unless a mailbox contract names them.

Selecting a mailbox is what the reading place listens to. Selecting a
source header without a mailbox selects that source's default mailbox
(Pages).

### Middle — reading

The message list of the selected mailbox, plus a **reading pane** for
the selected message. For Pages that means the graph list (title,
status, id, check badges) and, under it or beside it, the selected
page as a letter:

- If `watch --serve` is up, the reading pane loads that page's served
  URL through the existing preview session. It does not spawn a second
  watch. It does not use `file://`.
- If watch is down, the pane shows a contract-backed summary (title,
  id, status, `sourcePath`, relations from `completion.json`) and the
  verbs Preview / Edit. It does not render Markdown. It does not parse
  frontmatter.

Selecting a noun in the reading place is what the drawer and the
companion windows listen to.

The reading place is **not** the editor, **not** the full-site
preview, **not** a settings form, **not** a homegrown Markdown
previewer. Outputs / Publish / Plan / Activity are still *our* chrome
when those mailboxes are selected; they are no longer tabs stacked on
top of Pages.

### Right — drawer

Inspector. Options, profile keys, page fields, execution knobs.
Collapsible. This is what makes the one-window workflow: you should
not leave the main window to change a profile key, a scope, a theme, a
page's frontmatter fields, or `jobs` / `incremental` / `quiet`.

The drawer is minutiae of the **selection**, not the account book.
Adding a source does not belong here.

Rule still stands (D2): if it changes Boris output, the control writes
the publication profile. If it is machine-local, it writes the app
plist. The drawer is a view over those two stores, never a third.

### Companion windows

Surfaces we host and do not write. The full-site Preview. The Svelte
editor. Future Boris UIs. They open from the main window (and the menu
bar) against the current selection. They are not columns. They are not
tabs in the drawer.

Edit ▶ / double-click a page / Return on a Pages row opens the editor
companion against the selected source (and against the selected
`sourcePath` once that launch contract exists). Link-out remains the
accepted fallback.

Mail's Activity window is the analog for build/plan/timings if that
surface ever outgrows its mailbox. It is still *our* chrome if we
author it; companions are specifically the things we refuse to author.

### Compose — native buffer (M10)

Mail's compose is a separate window. Ours is `Sources/Compose/`: a
native Markdown / Textile / Cooklang buffer over the selected page's
`sourcePath`, with Oliver as the language reference and the preview
renderer. Highlighting is heuristic paint, not a parse. The front
matter boundary is sniffed, never parsed. Save is explicit and flows
into the coordinator's validate gate.

This does **not** replace the hosted `boris-editor` companion (#102).
Edit ▶ still opens that host. Compose ▶ (`⌘⇧C`) opens the native
buffer. Distinct lanes: `Companions/Editor/` vs `Compose/`.

Oliver is spawned only from `Engine/` (`OliverRenderer` reuses
`BorisRunner`). Play does not grow a `TextView`. Remaining compose
depth (span diagnostics, incremental highlight, bundling `oliver`
next to `boris`) is Later, not the M10 gate.

---

## 3. Why this splits cleanly

Agents collide when everyone edits `ContentView` and invents state.
They do not collide when the chrome exposes **slots** and each slice
owns a directory.

```
Sources/
  App/            process entry, menu bar, window groups
    Settings/     Settings scene — Sources pane (the account book)
  Chrome/         the one window: mailbox slot, reading slot, drawer slot
  Workspace/      Source protocol + selection store + providers
    Local/        first provider (bookmark, open/save, recents)
    GitHub/       later
  Play/           one reading surface per source kind
    Local/        message list + reading pane; mailbox contents
  Inspector/      Inspectable sections, no selection ownership
  Companions/     PreviewWindow, EditorWindow (WKWebView hosts)
  Compose/        native buffer + Oliver preview (M10)
  Engine/         existing — the only Process owner (boris *and* oliver)
  Models/         existing — Codable mirrors, no SwiftUI
```

`ContentView.swift` is gone. Chrome is `MainWindow` and empty slots.
Do not grow `MainWindow` — fill `Play/`, `Inspector/`, `Companions/`,
`Compose/`, `App/Settings/`. Recut `SourceSidebar` into a mailbox
tree; do not start a second sidebar.

### Load-bearing types (the seams)

Four protocols, one store. These get written once, then everyone else
fills them in.

| Seam | Owns | Does not own |
|------|------|----------------|
| `Source` | identity, title, kind, how to appear as an account header | mailbox contents, inspector UI |
| `PlaySurface` | the middle view for one source kind + selected mailbox | engine process, window chrome |
| `Inspectable` | sections the drawer renders for the current selection | the selection itself |
| `Companion` | a window that hosts a foreign surface | compiler semantics |
| `WorkspaceSelection` | the single selected source + mailbox + noun | views |

Rules:

- Selection is a value type in one observable store. The drawer and the
  companions **read** it. They never own it. Chrome writes `sourceID`
  and `mailbox`; play writes `noun`.
- `mailbox` is an open string (like `noun.kind`): `pages`, `outputs`,
  `publish`, `plan`, `activity`, later a trunk id. Do not invent a
  second vocabulary.
- Engine is the only thing that starts a `Process`. Companions and the
  reading pane ask the actor; they do not spawn `boris`. One watch
  session per selected source — the reading pane reuses it.
- Models do not import SwiftUI. Play/Inspector do not parse JSON —
  they take decoded contracts.
- A new source type is a new folder under `Workspace/` + `Play/`. It
  does not touch another source's folder.

---

## 4. Lanes (pick one, don't overlap)

Paths are the contract. If two agents need the same file, the work was
cut wrong — stop and recut.

| Lane | Owns (paths) | Does not touch | Gate |
|------|----------------|----------------|------|
| **Chassis** (serial, first) | `Sources/App/`, `Sources/Chrome/`, `Sources/Workspace/Source.swift`, `WorkspaceSelection`, `Project.yml` | Play implementations, companions, Models | Main window shows an empty source list, empty play, empty drawer; Open… adds a local source |
| **Contracts** | `Sources/Models/`, `Spike/`, `docs/ENGINE-CONTRACTS.md` | any SwiftUI | `make run-spike` + fixture decode for each new schema |
| **Engine** | `Sources/Engine/` | SwiftUI, Models shape (additive Codable only, with Contracts lane) | spike probes for `plan` / `validate` / `--report` / `--timings` / `watch --serve` |
| **Local play** | `Sources/Play/Local/`, `Sources/Workspace/Local/` | Chrome internals, other sources | Open a folder → graph list from `graph.json` in the play slot |
| **Inspector** | `Sources/Inspector/` | selection store shape, Engine | Selecting a page/target/profile key shows the matching section |
| **Preview companion** | `Sources/Companions/Preview/` | editor, play | Preview window loads `watch --serve` and reloads on SSE |
| **Editor companion** | `Sources/Companions/Editor/` | preview, play | Editor window loads `boris-editor` token URL; link-out fallback |
| **GitHub source** | `Sources/Workspace/GitHub/`, `Sources/Play/GitHub/` | Local play, Engine | A GitHub source appears as an account header and vends its own mailboxes |
| **Settings** (M10) | `Sources/App/Settings/`, Settings scene in `SolipsistApp.swift` | `Commands.swift`, Play, mailbox tree, `Project.yml` | Settings → Sources adds/removes/relocates a local source; same store as File → Open… |
| **Mailboxes** (M10) | `SourceSidebar.swift`; `WorkspaceSelection` / `WorkspaceStore` / `WorkspacePersistence`; sole `MainWindow.swift` | Settings scene, `Commands.swift`, Play row rendering, Inspector, `Project.yml` | Sidebar is account headers + mailboxes; selecting one writes `selection.mailbox` |
| **Reading** (M10) | `Sources/Play/Local/`; named recut: `PlayHost` binder, `AppRuntime.previewSession`, `Companions/Preview/` session share + `PreviewURL` helpers | Chrome mailbox construction, `MainWindow.swift`, Engine | Tabs gone; center is message list + reading pane driven by `mailbox` |
| **Editor wiring** (M10) | `Sources/Companions/Editor/`, File → Edit Page in `Commands.swift` | `Sources/Compose/`, Play list internals, `MainWindow.swift` | File → Edit Page; header shows title + `sourcePath`; merge after Reading |
| **Compose** (M10) | `Sources/Compose/`, `OliverRenderer` / `OliverBinary` in `Engine/`, Compose menu / window | `Companions/Editor/`, Play list internals, `MainWindow.swift` | ⌘⇧C opens the selected page; explicit save; Oliver preview when the binary is present |
| **Issues** | `docs/issues/` | `Sources/` | Draft fact-checked against afterparty, then filed |
| **Design** | `docs/*.md` except `issues/` | `Sources/` | Decisions recorded; no silent contradiction with this file |

### Sequence

1. **Chassis lands first.** Slots and `Source` / `WorkspaceSelection`
   exist. This is the serial bottleneck on purpose. It is short.
2. **Then fan out.** Contracts + Engine (S0) can run next to Local play
   + Inspector + Issues. Preview companion starts once Engine has
   `previewStart/Stop`.
3. **Editor companion and GitHub source** start after Local play is
   something you can select in. They must not block the one-window
   workflow.
4. **M10 (Mail body) starts after M9 is the remaining ship card, not
   instead of it.** Settings can run next to Mailboxes. Reading follows
   Mailboxes (it consumes `selection.mailbox`). Editor wiring **merges
   after Reading** (it reads `noun.sourcePath` that Reading writes).
   Compose (#106) keys off the same page noun, owns `Sources/Compose/`
   + the Oliver engine seam, and does not block #101 or #102.

### Integration rules

- Never `git add -A`. Stage the paths your lane owns.
- Work on a branch / worktree per lane. `main` stays tidy.
- Engine methods are additive. If you need a new invocation, add a
  method; do not rewrite `BorisRunner` unless that is your card.
- Unknown/newer `schemaVersion` degrades, never crashes (D8).
- If a feature is not in the menu bar, it is not a feature.
- If you are about to write a Markdown editor, a graph algorithm, a
  frontmatter parser, or an HTTP server — stop. That is Boris's job,
  Oliver's job, or a companion host. The native buffer lives in
  `Sources/Compose/` (#106). Do not drop a surprise `TextView` in Play.

---

## 5. What "kick ass" means here

The chassis and the seams are the substantial work. Once they exist,
this is not a one-person contest: a contracts agent, a local-play
agent, an inspector agent, and a preview agent should not need each
other's files.

The harness author's job after chassis:

- recut lanes when two people reach for the same file
- keep Boris behind the subprocess boundary
- refuse surfaces we said we would host instead of write
- integrate slices so the main window stays one piece of Mail-grade
  chrome, not a pile of panels

---

## 6. First chassis slice (definition of done) ✅

Landed. Goals from here: [`ROADMAP.md`](ROADMAP.md) M3+.

- `MainWindow` is a two-column `NavigationSplitView` (source list + play)
  with a trailing `.inspector` drawer that collapses. Preview and Editor
  are companion windows, not columns.
- File → Open… creates a `Local` source via a security-scoped bookmark
  and selects it.
- Play host and drawer render empty-state views, not a monospaced dump.
- Preview and Editor are registered `WindowGroup`s and stay closed.
- `ContentView.swift` is gone.
- `make build` still produces a runnable app; `make run-spike` is
  unchanged (spike does not import Chrome).

---

## 7. What ships today (M2–M8), vs M10

Do not "fix" the shipping chrome back onto this file's destination
without picking an M10 card. The live app is still the flatter cut:

| Surface | Ships today | M10 destination |
|---------|-------------|-----------------|
| Account book | File → Open… / sidebar plus / Remove Source | Settings → Sources (same `WorkspaceStore`) |
| Left column | Flat source list (`SourceSidebar`) | Account headers + mailboxes |
| Center | Segmented play tabs (Pages / Outputs / Publish / Plan / Activity) + problems strip | Message list + reading pane, driven by the selected mailbox |
| Preview | Companion only | Companion (full site) + reading pane (selected page, same watch) |
| Editor | Companion only; source-scoped, not page-scoped | Companion, opened from the selected page (#102) |
| Compose | none | Native buffer window (`⌘⇧C`) over `sourcePath`; Oliver preview (#106) |
| Selection | `sourceID` + `noun` | `sourceID` + `mailbox` + `noun` |

M10 cards live in [`cards/`](cards/README.md)
([#98](https://github.com/drawmeanelephant/solipsist/issues/98)).
#78 stays build-lane only.
