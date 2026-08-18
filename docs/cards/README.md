# Next cards

Session briefs. Pick **one**. Paths are the contract — if two sessions
need the same file, stop and recut.

Read first: `agents.md` → `docs/HARNESS.md` → `docs/ROADMAP.md`.
These cards win on *what to do now*; those docs win on *what we are*.

## Board — superseded by the roadmap batch

The old one-card-per-session board below has been **replaced by the
roadmap batch in the issue tracker**: one card per milestone gate, each
with a dispatch comment — [#72 M3](https://github.com/drawmeanelephant/solipsist/issues/72) ·
[#73 M4](https://github.com/drawmeanelephant/solipsist/issues/73) ·
[#74 M5](https://github.com/drawmeanelephant/solipsist/issues/74) ·
[#75 M6](https://github.com/drawmeanelephant/solipsist/issues/75) ·
[#76 M7](https://github.com/drawmeanelephant/solipsist/issues/76) ·
[#77 M8](https://github.com/drawmeanelephant/solipsist/issues/77) ·
[#78 M9](https://github.com/drawmeanelephant/solipsist/issues/78).

M3–M8 **gates** are closed (#72–#77). The #87 depth batch is closed
(#88/#94 · #89/#96 · #90/#95 · #91/#93). Active card:
[#78 ship](https://github.com/drawmeanelephant/solipsist/issues/78).

**Legacy board (landed or withdrawn — do not pick):**

| Card | Fate |
|------|------|
| [P-subdomain](P-subdomain.md) | ⛔ withdrawn — site ships via Cloudflare Pages (`site/`) |
| [M3-local-play](M3-local-play.md) | ✅ landed (M3, #72/#80) |
| [M4-engine-s0](M4-engine-s0.md) | ✅ landed (M1 engine spike + S0 methods) |
| [M4-coordinate](M4-coordinate.md) | ✅ landed (M4, #73/#80) |
| [M3-inspector](M3-inspector.md) | ✅ landed (M3, #72/#80) |
| [ISSUES-file](ISSUES-file-A1-A14-A7.md) | ✅ rolled — A1/A14/A7/A5 filed |

## Batch 3 (production readiness)

From the roadmap audit — issues
[#58](https://github.com/drawmeanelephant/solipsist/issues/58) –
[#61](https://github.com/drawmeanelephant/solipsist/issues/61). These
own grind-lane paths (`Engine/`, `Coordinator.swift`, `Workspace/`,
`embed-boris.sh`), so they are **not** queue cards; one card = one
worktree = one PR. Dispatch is recorded in the comments on each issue.

| Card | Issue | Lane | Parallel with | Gate |
|------|-------|------|----------------|------|
| [B3-1](B3-coordinator.md) | #58 | coordinator (grind) | B3-2, B3-3, B3-4 | state-machine spec, zero subprocess leak |
| [B3-2](B3-workspace.md) | #59 | workspace | B3-1, B3-3, B3-4 | restart → source persists; stale → non-blocking warning |
| [B3-3](B3-publish-security.md) | #60 | publish-security (uncle-gravity) | B3-1, B3-2, B3-4 | secrets on stdin, zeroed, never persisted |
| [B3-4](B3-ship.md) | #61 | ship/build (uncle-gravity) | B3-1, B3-2, B3-3 | universal app spawns boris, `spctl` clean |

Sequencing: `Sources/Engine/**` is single-owner under B3-1; B3-3's
stdin wiring merges after B3-1. B3-4 must keep
`files.user-selected.read-write` (B3-2) and `network.server` (M5
preview) in the entitlements matrix.

## Do not start yet

GitHub as a source. Wasm in the app. The fart app. Preview, editor,
and publish already have gates — do not rebuild them.

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

## Parallel lane (external agent)

Background pile that must not touch Play / Inspector / Engine /
Models / Spike / `MainWindow`. PR cop + Boris issue filing + the
cards under [`parallel/`](parallel/README.md).
