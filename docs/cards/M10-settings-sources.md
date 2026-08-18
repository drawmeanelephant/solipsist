# Card M10-1 — Settings → Sources

**Milestone:** M10 · **Issue:**
[#99](https://github.com/drawmeanelephant/solipsist/issues/99) ·
**Lane:** Settings. One worktree, one PR against `main`; branch
suggestion `feat/m10-settings-sources`.

Design: [`docs/M10-DESIGN.md`](../M10-DESIGN.md). Recut vs the original
Owns: **do not edit `Commands.swift`** — Solipsist → Settings… is the
system item for a `Settings` scene. #102 owns `Commands.swift`.

## Owns

- `Sources/App/Settings/` (new)
- Settings scene registration in `Sources/App/SolipsistApp.swift`
- Read-only use of `WorkspaceStore` add / remove / relocate APIs

## Do not touch

- `Sources/App/Commands.swift` (system Settings… is enough; #102 owns this file)
- `Sources/Play/**`
- `Sources/Chrome/SourceSidebar.swift` internals (plus button may
  stay; it already calls `presentOpenPanel()`)
- `Sources/Engine/**`
- `Sources/Inspector/**`
- `scripts/embed-boris.sh`, **any of** `Project.yml`, #78 paths

## Why

Sources are accounts. Mail puts the account book in Preferences, not
in the sidebar plus button. File → Open… stays — that is the Mac verb
for a folder — but the inventory you can add, relocate, and remove
has to live in Settings too, same `WorkspaceStore`, no second list.

## Do

1. Add a SwiftUI `Settings` scene with a **Sources** pane.
2. List current sources (title, kind, path, stale badge). Actions:
   Add Local…, Relocate…, Remove. Reuse
   `WorkspaceStore.presentOpenPanel` / `presentRelocatePanel` /
   `remove` — do not invent a second bookmark store.
3. Empty state: say what a source is and point at `Stunts/happy`.
4. Menu: Solipsist → Settings… is the system item (adding the
   `Settings` scene is sufficient). File menu keeps Open… / Open
   Recent / Relocate / Remove. Do not add a Sources command.
5. D2: this pane writes bookmarks / plist only. It does not write
   `boris.json`. Do not move profile keys or execution knobs here.

## Do not

- Redesign the three-column layout (M10-2 / M10-3).
- Add a GitHub account row that does not work.
- Auto-open a repo path or `SUPPORT-NOT-FOR-GITHUB/`.
- Grow `MainWindow`.

## Gate

Solipsist → Settings… → Sources → Add Local… a folder with
`boris.json` → it appears in the sidebar and is selected. Relocate
and Remove from Settings match the File-menu verbs. Restart → the
source is still **in the list** (#59). Selected-row persistence is
#100 (`select` does not write defaults until then). After #100,
Settings `select(id)` also resets mailbox to `pages`.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
