# Next cards

Session briefs. Pick **one**. Paths are the contract — if two sessions
need the same file, stop and recut.

Read first: `agents.md` → `docs/HARNESS.md` → `docs/ROADMAP.md`.
These cards win on *what to do now*; those docs win on *what we are*.

## Board

| Card | Lane | Parallel with | Gate |
|------|------|----------------|------|
| [P-subdomain](P-subdomain.md) | project site (`site/`) | everything | `https://<subdomain>` serves a Boris-built Solipsist page |
| [M3-local-play](M3-local-play.md) | `Sources/Play/Local/`, `Workspace/Local/` | P, M4 | Open dogfood content → graph list → select a page |
| [M4-engine-s0](M4-engine-s0.md) | `Sources/Engine/`, `Sources/Models/`, `Spike/` | P, M3-play | spike runs `plan` + `validate` + `--report` + `--timings` |
| [M3-inspector](M3-inspector.md) | `Sources/Inspector/`, `Chrome/InspectorDrawer.swift` | P, M3-play, M4 (do not edit `Models/`) | select a page → drawer shows fields; profile writes `boris.json` |
| [ISSUES-file](ISSUES-file-A1-A14-A7.md) | `docs/issues/` | everything | A1, A14, A7 pasted when GitHub is back |

## Do not start yet

Preview companion, Editor companion, GitHub-as-source, publication
flows, Wasm in the app. A page must be selectable first (M3-play).

## Shared noun kinds (play writes, inspector reads)

Do not invent a second vocabulary.

| `WorkspaceNoun.kind` | `id` | When |
|----------------------|------|------|
| `page` | graph/manifest entity id | a row in the play list |
| `profile` | `"boris.json"` | source selected, no page (inspector may set this; play may too) |
| `target` / `edition` | profile entry name | M7, not these cards |

`WorkspaceStore.select(noun:)` already exists. Drawer and companions
only read `store.selection`.

## Running them all at once

Yes — **five sessions, five worktrees** (or five branches), never one
shared dirty checkout.

| | P | M3-play | M4-engine | M3-inspector | Issues |
|--|---|---------|-----------|--------------|--------|
| P | | ok | ok | ok | ok |
| M3-play | | | ok | ok | ok |
| M4-engine | | | | ok if inspector stays out of `Models/` | ok |
| M3-inspector | | | | | ok |
| Issues | | | | | |

Same worktree + five agents = they will fight over `git status` and
`make generate` even when the cards are disjoint. Clone or
`git worktree add` per card. Merge M4 before the inspector can show
real completion/profile fields.
