# M10 — Mail body (tracker)

**Milestone:** M10 · **Lane:** design (this file) + four child cards.
Does **not** own `Sources/`. Children do.

Parent issue:
[#98](https://github.com/drawmeanelephant/solipsist/issues/98).
#78 (M9 ship) stays its own track.

## Why

The window is Mail-shaped and still behaves like a tabbed workbench.
Sources are a flat sidebar added via File → Open…. Play stacks Pages /
Outputs / Publish / Plan / Activity as a segmented control. Preview
and Editor are companions with no reading pane and no page-scoped
Edit. That is the M2–M8 chassis. It is not Mail's body.

[`HARNESS.md`](../HARNESS.md) §2 is now the destination: Settings for
the account book, mailboxes on the left, messages + reading pane in
the middle, drawer for minutiae, companions for the full site and
`boris-editor`. A native buffer is named Later, not this milestone.

## Children

One card = one worktree = one PR. Settings can run next to Mailboxes.
Reading follows Mailboxes. Editor wiring **merges after Reading**
(it reads `noun.sourcePath` that Reading writes). Development of
#102 may start after #100. See [`docs/M10-DESIGN.md`](../M10-DESIGN.md).

| Card | Issue | Lane | Gate (short) |
|------|-------|------|----------------|
| [M10-1 Settings](M10-settings-sources.md) | [#99](https://github.com/drawmeanelephant/solipsist/issues/99) | Settings | Settings → Sources adds/removes/relocates; same store as Open… |
| [M10-2 Mailboxes](M10-mailbox-sidebar.md) | [#100](https://github.com/drawmeanelephant/solipsist/issues/100) | Mailboxes | Sidebar is account headers + mailboxes; writes `selection.mailbox` |
| [M10-3 Reading](M10-reading-pane.md) | [#101](https://github.com/drawmeanelephant/solipsist/issues/101) | Reading | Tabs gone; list + reading pane; no `file://`, no Swift Markdown |
| [M10-4 Editor](M10-editor-wiring.md) | [#102](https://github.com/drawmeanelephant/solipsist/issues/102) | Editor wiring | File → Edit Page; header shows title + `sourcePath` |

## Not this tracker

- #78 ship (build lane)
- A native `TextView` / from-scratch editor
- GitHub as a source
- Walking the content directory as a Finder tree
- An app-side HTTP server or `file://` preview
- Reimplementing coordinator verbs, publish, or contracts

## Shared nouns

Do not invent a second vocabulary. `WorkspaceSelection` grows
`mailbox` (open string, same style as `noun.kind`):

| `mailbox` | Meaning |
|-----------|---------|
| `pages` | graph nodes as messages |
| `outputs` | profile targets / editions |
| `publish` | publication console |
| `plan` | plan document |
| `activity` | timings / job log |
| later: a trunk id | nested folder under Pages, from `graph.parent` only |

Existing `WorkspaceNoun.kind` values (`page`, `profile`, `target`,
`edition`) stay. Chrome writes `sourceID` + `mailbox`. Play writes
`noun`. Drawer and companions only read.

## Sequence

1. M10-1 and M10-2 may start in parallel (Settings does not restructure
   the sidebar; Mailboxes does not own the Settings scene).
2. M10-3 starts after M10-2 lands `selection.mailbox` (a sync shim
   that keeps today's tabs driven by `mailbox` is an acceptable
   M10-2 landing if Reading is not ready).
3. M10-4 **merges after M10-3**. It may be *developed* after M10-2
   (`sourcePath` on the type) but must not touch `LocalPlay.swift`
   or `MainWindow.swift`.
