# M13 — Graph folders (tracker)

**Milestone:** M13 · **Lane:** design (this file) + three child cards.
Does **not** own `Sources/`. Children do.

Parent issue:
[#142](https://github.com/drawmeanelephant/solipsist/issues/142).

## Why

M10 stored `mailbox` as an open string and displayed five tokens.
HARNESS already named trunks as folders under Pages. M10-DESIGN
D-S1 / D-S6 deferred them on purpose: unknown still *displays* as
Pages, so a persisted trunk id would open the full letter list.

Dogfood is **45 pages / 7 trunks**. The list already walks
`graph.parent` (`LocalPlayGraph.pages`). The sidebar does not.

## Children

One card = one worktree = one PR. M13-0 first. M13-1 writes
`mailbox = trunk id`. M13-2 reads it.

| Card | Issue | Lane | Gate (short) |
|------|-------|------|----------------|
| [M13-0 Unknown mailbox](M13-unknown-mailbox.md) | [#144](https://github.com/drawmeanelephant/solipsist/issues/144) | Workspace | unknown raw `mailbox` is not treated as Pages in the center switch |
| [M13-1 Trunk folders](M13-trunk-folders.md) | [#145](https://github.com/drawmeanelephant/solipsist/issues/145) | Mailboxes | Pages grows children from `graph.parent`; no disk walk |
| [M13-2 Filter letters](M13-filter-letters.md) | [#146](https://github.com/drawmeanelephant/solipsist/issues/146) | Reading | trunk mailbox filters the list; Pages still means all |

## Not this tracker

- M12 clone (#131)
- Walking `content/` as Finder; `.boris/` / `themes/` / `dist/` as mailboxes
- Status / tag folders
- Persist outline expansion
- Engine / `--watch-json` (M14)
- GitHub as a source
- Growing #110 / #111

## Shared nouns

Do not invent a second field. `mailbox` stays an open string.

| `mailbox` | Meaning |
|-----------|---------|
| `pages` | all graph nodes |
| `outputs` / `publish` / `plan` / `activity` | unchanged |
| a trunk id | nested folder under Pages, from `graph.parent` only |

Chrome writes `sourceID` + `mailbox`. Play writes `noun`. Drawer
and companions only read.
