# Card M3 — Local play (graph list)

**Milestone:** M3
**Lane:** `Sources/Play/Local/`, maybe `Sources/Workspace/Local/`
**Do not touch:** `Sources/Chrome/` internals, `Sources/Inspector/`,
`Sources/Companions/`, `Sources/Models/` (Graph/Manifest already exist),
`Spike/`.

## Why

The middle is empty. Open a local source and the publication must appear
as a Mail-style list you can select. Inspector and companions listen to
that selection.

## Do

1. Replace the placeholder in `Sources/Play/Local/LocalPlay.swift`.
2. Resolve the folder from `LocalSource.resolve()` (bookmark; access is
   already started by `WorkspaceStore`).
3. Load the graph:
   - If `<source>/.boris/graph.json` exists, decode it (existing `Graph`).
   - Else run `AppRuntime.engine.buildIR` with
     `contentRoot = source URL`, `outDir = source/.boris`
     (cwd = source, `--out .boris`, relative — D1 + containment).
   - If the folder contains `content/` **and** `boris.json`, treat it as
     a project root: `--input content` (or the profile `input` once M4
     can read it), cwd = source, `--out .boris`.
4. Render a `List` of pages from `graph.nodes` (or `manifest.pages` if
   you prefer summaries). Group trunks; indent satellites by `parent`.
   Show `title`, `status`, `id`. System list, not a custom graph view.
5. On select, `store.select(noun: WorkspaceNoun(kind: "page", id: id,
   title: title))`. Changing source already clears the noun.
6. Empty / error / unavailable states stay `ContentUnavailableView` —
   no monospaced dump. Surface `buildIR` failures (exit, diagnostics
   count). Do not swallow them.
7. `check` unreferenced badges are nice-to-have, not the gate.

## Do not

- Parse frontmatter or invent edges. `Graph` is the structure.
- Spawn `Process`. Only `BorisEngine`.
- Implement Plan/Validate/Build menus (M4).
- Draw a mind-map.
- Grow `MainWindow` or `PlayHost` beyond the existing `LocalPlay`
  dispatch.

## Facts

- `Graph` / `Manifest` / `BuildReport` are already in
  `Sources/Models/BorisContracts.swift`.
- `WorkspaceStore.select(noun:)` exists.
- `buildIR` is on the actor; call from a `Task`. `AppRuntime` is in the
  environment.
- Dogfood: `/Users/tbuddy/dev/drawmeanelephant/boris/main/content` —
  45 pages, 7 trunks. Spike already proved the decode.
- Kit binary: `SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris`

## Gate

File → Open… that content folder → play lists the trunks/satellites →
click a row → status bar still sane, inspector (even empty) is looking
at `noun.kind == "page"`. `make build` succeeds. `make run-spike`
unchanged.
