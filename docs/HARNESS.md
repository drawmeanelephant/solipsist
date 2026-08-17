# Solipsist — Harness & Lanes

**Date:** 2026-08-17
**Status:** locked direction (spatial model + how we split work)
**Parents:** Radio UserLand × Mail, HIG pedant, contract pedant
This file is the product chassis and the agent-split. Goals live in
[`ROADMAP.md`](ROADMAP.md). If they disagree about where a surface
lives, this file wins.

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

Left to right, one main window. Companion windows for foreign surfaces.

```
┌──────────────────┬─────────────────────────────┬──────────────────┐
│ SOURCES          │ PLAY                        │ DRAWER           │
│                  │                             │                  │
│ Local folder     │ The work, for the selected  │ Options          │
│ GitHub           │ source. Pages, outputs,     │ Settings         │
│ (whatever next)  │ activity, reports.          │ Minutiae         │
│                  │ Noun selected here.         │ of the selection │
└──────────────────┴─────────────────────────────┴──────────────────┘

Companion windows (hosted, not authored):
  • Preview   — boris watch --serve in WKWebView
  • Editor    — boris-editor (Svelte) at its session-token URL
  • anything else Boris already built that we will not rewrite
```

### Left — sources

Accounts, not a file tree. A **source** is a place content lives or
publishes: a local folder (security-scoped bookmark), a GitHub repo,
later whatever earns a provider. The first source type is local. GitHub
is the second. The sidebar is a source list, Mail-style, not a project
tree. Trees and mailboxes of a source belong to that source's play
surface.

Do not hardcode "the open folder" as the app model. Hardcode `Source`.

### Middle — play

Where work happens for the selected source. For a local Boris project
that means the coordinator surface: the graph as a workable list,
outputs (targets / editions), plan/validate/build activity, reports.
Selecting a noun in the play place is what the drawer and the companion
windows listen to.

Play is **not** the editor, **not** the preview, **not** a settings form.

### Right — drawer

Inspector. Options, settings, minutiae. Collapsible. This is what makes
the one-window workflow: you should not leave the main window to change
a profile key, a scope, a theme, a page's frontmatter fields, or
`jobs` / `incremental` / `quiet`.

Rule still stands (D2): if it changes Boris output, the control writes
the publication profile. If it is machine-local, it writes the app
plist. The drawer is a view over those two stores, never a third.

### Companion windows

Surfaces we host and do not write. Preview. The Svelte editor. Future
Boris UIs. They open from the main window (and the menu bar) against the
current selection. They are not columns. They are not tabs in the
drawer.

Mail's Activity window is the analog for build/plan/timings if that
surface ever outgrows the play place. It is still *our* chrome if we
author it; companions are specifically the things we refuse to author.

---

## 3. Why this splits cleanly

Agents collide when everyone edits `ContentView` and invents state.
They do not collide when the chrome exposes **slots** and each slice
owns a directory.

```
Sources/
  App/            process entry, menu bar, window groups
  Chrome/         the one window: sidebar slot, play slot, drawer slot
  Workspace/      Source protocol + selection store + providers
    Local/        first provider (bookmark, open/save, recents)
    GitHub/       later
  Play/           one play surface per source kind
    Local/        graph list, outputs, activity, reports
  Inspector/      Inspectable sections, no selection ownership
  Companions/     PreviewWindow, EditorWindow (WKWebView hosts)
  Engine/         existing — the only Process owner
  Models/         existing — Codable mirrors, no SwiftUI
```

`ContentView.swift` is gone. Chrome is `MainWindow` and empty slots.
Do not grow `MainWindow` — fill `Play/`, `Inspector/`, `Companions/`.

### Load-bearing types (the seams)

Four protocols, one store. These get written once, then everyone else
fills them in.

| Seam | Owns | Does not own |
|------|------|----------------|
| `Source` | identity, title, kind, how to appear in the sidebar | play UI, inspector UI |
| `PlaySurface` | the middle view for one source kind | engine process, window chrome |
| `Inspectable` | sections the drawer renders for the current selection | the selection itself |
| `Companion` | a window that hosts a foreign surface | compiler semantics |
| `WorkspaceSelection` | the single selected source + noun | views |

Rules:

- Selection is a value type in one observable store. The drawer and the
  companions **read** it. They never own it.
- Engine is the only thing that starts a `Process`. Companions ask the
  actor; they do not spawn `boris`.
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
| **GitHub source** | `Sources/Workspace/GitHub/`, `Sources/Play/GitHub/` | Local play, Engine | A GitHub source appears in the sidebar and vends its own play |
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

### Integration rules

- Never `git add -A`. Stage the paths your lane owns.
- Work on a branch / worktree per lane. `main` stays tidy.
- Engine methods are additive. If you need a new invocation, add a
  method; do not rewrite `BorisRunner` unless that is your card.
- Unknown/newer `schemaVersion` degrades, never crashes (D8).
- If a feature is not in the menu bar, it is not a feature.
- If you are about to write a Markdown editor, a graph algorithm, a
  frontmatter parser, or an HTTP server — stop. That is Boris's job or
  a companion host.

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
