# Card M3 — Inspector drawer

**Milestone:** M3
**Lane:** `Sources/Inspector/` and `Sources/Chrome/InspectorDrawer.swift`
(host the sections; do not restyle the window).
**Do not touch:** `Play/`, `Companions/`, `Engine/`, `Spike/`,
`Sources/Models/`, `Workspace/Source.swift`, `WorkspaceSelection` shape.

## Why

The drawer is how the one-window workflow works. It reads the current
noun and shows minutiae. It never owns selection.

## Depends

`PublicationProfile` and `Completion` land in `Sources/Models/` on
[M4-engine-s0](M4-engine-s0.md). You may start in parallel: build the
section chrome against optional/`nil` models. If those types are not
in the tree yet, show the quiet empty caption for that section — do
**not** add Codable types yourself (that file is M4’s). Merge or rebase
onto M4 when it lands and wire the real fields.

## Do

1. Fill `Sources/Inspector/`. Keep `Inspectable` / `InspectorSection`.
2. `InspectorDrawer` becomes a stack of sections, not a caption:
   - **Profile** when a local source is selected: form over `boris.json`
     if present (`site.title`, `site.url`, `input`, `input_format`,
     publication target). Every control maps 1:1 to a profile key (D2).
     Save writes the file. Do not invent keys Boris rejects (strict
     JSON, no comments).
   - **Page** when `noun.kind == "page"`: title, id, parent, status,
     tags, relation kinds / layout slots from `completion.json` if
     loaded. Read-only is fine this card; editing frontmatter is the
     editor companion (M6).
   - **Execution** (`jobs` / `incremental` / `quiet`): app plist /
     `UserDefaults` only — never `boris.json`.
3. Quiet empty state when there is no source (already there).
4. Load `completion.json` from `<source>/.boris/` if play has produced
   it; do not spawn `boris` yourself.

## Do not

- Third settings store.
- Parse frontmatter out of the markdown.
- Grow `MainWindow`.
- Implement Plan/Validate buttons (M4 UI).

## Facts

- Profile schema v1: `format = boris-publication-profile`,
  `schema_version = 1`, `input`, `input_format`, `site`, `publication`,
  `targets[]`, `editions`. Unknown keys fail on `plan` — do not emit
  them.
- `completion.json` uses integer `schema_version`.
- Noun kinds: `page` / `profile` (see [README](README.md)).

## Gate

Drawer sections render for `profile` / `page` without crashing when
models are missing. After M4 is merged: open a project with `boris.json`
and `.boris/completion.json` → edit `site.title` → file changes →
select a page → drawer shows that page. `make build` succeeds.
