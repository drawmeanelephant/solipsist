# Card M13-1 — Trunk folders under Pages

**Milestone:** M13 · **Issue:**
[#145](https://github.com/drawmeanelephant/solipsist/issues/145)
(parent [#142](https://github.com/drawmeanelephant/solipsist/issues/142))
· **Lane:** Mailboxes. One worktree, one PR against `main`;
branch suggestion `feat/m13-trunk-folders`.

Merges **after** M13-0. Writes `mailbox = trunk id`. Does not
filter the letter list (M13-2).

## Owns

- `Sources/Chrome/SourceSidebar.swift` — child rows under Pages
- Read-only use of the already-decoded graph (do not parse JSON
  here; Play / the store already have `Graph`)

## Do not touch

- `WorkspaceMailbox.display` rules (M13-0)
- `Sources/Play/Local/` filter (M13-2)
- `Sources/Engine/**`
- Settings / `Workspace/Git/`
- `MainWindow.swift` unless a column-width collision is real —
  stop and recut if it is
- Walking the content directory

## Why

Mailboxes are not Finder. Nested folders under Pages are allowed
when they come from `graph.parent` — trunks as folders, satellites
as messages. M10 shipped five flat mailboxes. Dogfood has 7 trunks.

## Do

1. Under each source’s **Pages** row, add one child row per trunk
   (`role == trunk`, or a root with children — same walk
   `LocalPlayGraph` already does). Label is the trunk title; the
   selection value is the trunk **id**.
2. Clicking a trunk writes `selection.mailbox` to that id (raw).
   Clicking Pages still writes `pages`.
3. No disk walk. No `.boris/`, `themes/`, `dist/` rows.
4. Expansion is not persisted. A disclosure that forgets on
   relaunch is acceptable.
5. Chrome does not decode `graph.json`. If the graph is not loaded
   yet, Pages has no children — not an error.

## Do not

- Filter the letter list (M13-2).
- Persist outline expansion.
- Use `WorkspaceMailbox.display` to coerce a trunk id back to
  `pages` on click.
- Invent status / tag folders.

## Gate

Open dogfood → Pages shows **7 trunk folders** from `graph.json`.
Selecting a trunk writes that id as `mailbox`. Selecting Pages
writes `pages`. No folder comes from walking the disk.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
