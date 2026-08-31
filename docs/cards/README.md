# Next cards

Session briefs. Pick **one**. Paths are the contract — if two sessions
need the same file, stop and recut.

Read first: `AGENTS.md` → `docs/HARNESS.md` → `docs/ROADMAP.md`.
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
(#88/#94 · #89/#96 · #90/#95 · #91/#93). **M9 ship** (#78), **M10
Mail body** (#98), **M11 prove** (#123), **M12 clone** (#131),
**M13 graph folders** (#142), and **M14 watch contract** (#143) all
landed. **M15** (GitHub source), **M16** (remote write verbs), and
**M17** (Pull Requests mailbox) followed. The milestone-10 editor
polish batch (#225–#238) and the accessibility tracker (#236 +
children #239–#243) are merged. The engine-settings-truth cleanup
(#292, PR #293) landed. **M18** (Siri drafts posts via App Intents +
on-device FoundationModels, macOS 27) landed as PR #294. The
Apple-account ship blockers #110 / #111 are closed. **The tracker is
empty** — no pickable cards remain. The named-but-unscheduled items in
ROADMAP §3 (Cooklang recipe-scale mailbox, width-adaptive
list-left-of-letter split, theme authoring) are the honest next-layer
candidates; cut an issue draft for one of those before picking up a card.

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

## M10 — Mail body ✅

Landed. Settings, mailboxes, reading pane, hosted Edit, native
Compose. Do not pick.

| Card | Issue | Fate |
|------|-------|------|
| [M10 tracker](M10-mail-body.md) | [#98](https://github.com/drawmeanelephant/solipsist/issues/98) | ✅ |
| [M10-1 Settings](M10-settings-sources.md) | [#99](https://github.com/drawmeanelephant/solipsist/issues/99) | ✅ |
| [M10-2 Mailboxes](M10-mailbox-sidebar.md) | [#100](https://github.com/drawmeanelephant/solipsist/issues/100) | ✅ |
| [M10-3 Reading](M10-reading-pane.md) | [#101](https://github.com/drawmeanelephant/solipsist/issues/101) | ✅ |
| [M10-4 Editor](M10-editor-wiring.md) | [#102](https://github.com/drawmeanelephant/solipsist/issues/102) | ✅ |
| [M10-5 Compose](COMPOSE-EDITOR.md) | [#106](https://github.com/drawmeanelephant/solipsist/issues/106) | ✅ PR [#108](https://github.com/drawmeanelephant/solipsist/pull/108) |

## M11 — Prove the Mail body ✅

Landed. Help and empty states match the window; Help-vs-Commands and
letter-URL contract tests pin the recut. Do not pick.

| Card | Issue | Fate |
|------|-------|------|
| [M11 tracker](M11-prove.md) | [#123](https://github.com/drawmeanelephant/solipsist/issues/123) | ✅ |
| [M11-1 Chrome/Help audit](M11-chrome-audit.md) | [#124](https://github.com/drawmeanelephant/solipsist/issues/124) | ✅ PR [#126](https://github.com/drawmeanelephant/solipsist/pull/126) |
| [M11-2 Test pass](M11-test-pass.md) | [#125](https://github.com/drawmeanelephant/solipsist/issues/125) | ✅ PRs [#127](https://github.com/drawmeanelephant/solipsist/pull/127), [#128](https://github.com/drawmeanelephant/solipsist/pull/128) |

## M12 — Clone ✅

| Card | Issue | Lane | Parallel with | Gate |
|------|-------|------|----------------|------|
| [Add Git Repository…](GIT-CLONE.md) | [#131](https://github.com/drawmeanelephant/solipsist/issues/131) | Settings / workspace | #110 (closed) | clone URL → folder → Local source; branch in Settings |

## M13 — Graph folders (filed; pick after M12 or in a second worktree)

| Card | Issue | Lane | Parallel with | Gate |
|------|-------|------|----------------|------|
| [M13 tracker](M13-graph-folders.md) | [#142](https://github.com/drawmeanelephant/solipsist/issues/142) | design | — | children filed; unknown mailbox is not Pages |
| [M13-0 Unknown mailbox](M13-unknown-mailbox.md) | [#144](https://github.com/drawmeanelephant/solipsist/issues/144) | Workspace | M14 | unknown `mailbox` displays verbatim; center does not treat it as Pages |
| [M13-1 Trunk folders](M13-trunk-folders.md) | [#145](https://github.com/drawmeanelephant/solipsist/issues/145) | Mailboxes | after #144 | Pages grows children from `graph.parent` |
| [M13-2 Filter letters](M13-filter-letters.md) | [#146](https://github.com/drawmeanelephant/solipsist/issues/146) | Reading | after #145 | trunk mailbox filters the list; Pages still means all |

## M14 — Watch contract (filed; parallel with M13)

| Card | Issue | Lane | Parallel with | Gate |
|------|-------|------|----------------|------|
| [M14 tracker](M14-watch-contract.md) | [#143](https://github.com/drawmeanelephant/solipsist/issues/143) | design | — | children filed |
| [M14-1 A1 consume](M14-a1-consume.md) | [#147](https://github.com/drawmeanelephant/solipsist/issues/147) | Engine + Preview | M13 | `--watch-json` / `serve-started` is how we learn the port |
| [M14-2 Letter SSE](M14-letter-sse.md) | [#148](https://github.com/drawmeanelephant/solipsist/issues/148) | Reading | after #147 | letter reloads on `event: reload`; no second watch |

## Post-ship — Later promotions ✅

Promoted from ROADMAP §3 "Later" — all landed. #165/#166 were unblocked
because the agent kit ships the binaries; probed contracts are recorded
in `docs/ENGINE-CONTRACTS.md` §8–§9 (PR #168). The two tool cards ran
through the coordinator's single `Process?` slot; #167 compose depth
landed as five slices, one worktree/PR each. Do not pick.

| Card | Issue | Fate |
|------|-------|------|
| [Content-audit mailbox](LATER-content-audit.md) | [#165](https://github.com/drawmeanelephant/solipsist/issues/165) | ✅ PR [#171](https://github.com/drawmeanelephant/solipsist/pull/171) |
| [Source-RAG export](LATER-source-rag.md) | [#166](https://github.com/drawmeanelephant/solipsist/issues/166) | ✅ PR [#170](https://github.com/drawmeanelephant/solipsist/pull/170) |
| Compose depth (tracker) | [#167](https://github.com/drawmeanelephant/solipsist/issues/167) | ✅ PRs [#173](https://github.com/drawmeanelephant/solipsist/pull/173)–[#177](https://github.com/drawmeanelephant/solipsist/pull/177) |
| [3.1 Span diagnostics](LATER-compose-diagnostics.md) | #167 | ✅ PR [#173](https://github.com/drawmeanelephant/solipsist/pull/173) |
| [3.2 Incremental highlight](LATER-compose-highlight.md) | #167 | ✅ PR [#174](https://github.com/drawmeanelephant/solipsist/pull/174) |
| [3.3 Front-matter form](LATER-compose-frontmatter.md) | #167 | ✅ PR [#175](https://github.com/drawmeanelephant/solipsist/pull/175) |
| [3.4 Cooklang autocomplete](LATER-compose-cooklang.md) | #167 | ✅ PR [#176](https://github.com/drawmeanelephant/solipsist/pull/176) |
| [3.5 Bundle oliver](LATER-compose-bundle-oliver.md) | #167 | ✅ PR [#177](https://github.com/drawmeanelephant/solipsist/pull/177) |

## M15 — GitHub source ✅

Landed — PRs #180 (seam) · #181 (settings sheet) · #182 (credential
helper) · #183 (Remote mailbox) · #184 (sign-out). Do not pick.

| Card | Issue | Fate |
|------|-------|------|
| [GitHub source](GITHUB-OAUTH.md) | [#179](https://github.com/drawmeanelephant/solipsist/issues/179) | ✅ |

## M16 — Write the remote ✅

Landed — PRs #187 (commit) · #188 (push) · #189 (PR authoring) ·
#190 (issues mailbox). Do not pick.

| Card | Issue | Fate |
|------|-------|------|
| [M16-1 Commit](M16-commit.md) | [#185](https://github.com/drawmeanelephant/solipsist/issues/185) | ✅ |
| [M16-2 Push](M16-push.md) | #185 | ✅ |
| [M16-3 PR](M16-pr.md) | #185 | ✅ |
| [M16-4 Issues](M16-issues.md) | #185 | ✅ |

## M17 — Pull Requests mailbox ✅

Landed — PRs #194 (PR list) · #195 (mailbox surface) · #196 (authoring
entry). Do not pick.

| Card | Issue | Fate |
|------|-------|------|
| [M17-1 PR list](M17-pr-list.md) | [#192](https://github.com/drawmeanelephant/solipsist/issues/192) | ✅ |
| [M17-2 PR mailbox](M17-pr-mailbox.md) | #192 | ✅ |
| [M17-3 Authoring entry](M17-pr-authoring.md) | #192 | ✅ |

## M18 — Siri drafts posts ✅

The new Siri speaks App Intents only; the on-device FoundationModels
session drafts. Compose stays the review surface; nothing touches the
content tree until an explicit ⌘S. macOS-27-only: deployment target
moves to 27.0 in the same PR.

| Card | Issue | Lane | Gate |
|------|-------|------|------|
| [Siri drafts posts](M18-siri-drafts.md) | — (PR [#294](https://github.com/drawmeanelephant/solipsist/pull/294)) | `Sources/Intents/` + compose save seam | “Draft a post in Solipsist …” stages an untitled buffer; ⌘S asks where; Apple Intelligence off surfaces an alert |


## Editor accessibility — milestone 10 polish ✅

VoiceOver across the editor surfaces, cut into five disjoint lanes from
tracker [#236](https://github.com/drawmeanelephant/solipsist/issues/236).
Each card is one worktree, one PR against `main`; all five are now
merged. Specs live in
[`docs/issues/`](../issues/README.md) (child-of-#236 drafts); the cards
below are the session briefs.

| Card | Issue | Lane | Parallel with | Gate |
|------|-------|------|----------------|------|
| [A11Y tracker](../issues/editor-compose-accessibility.md) | [#236](https://github.com/drawmeanelephant/solipsist/issues/236) | design | — | five children land; VoiceOver covers all surfaces |
| [A11Y-1 Compose toolbar + diagnostics](A11Y-compose-toolbar.md) | [#239](https://github.com/drawmeanelephant/solipsist/issues/239) | Compose | A11Y-2..A11Y-5 | ✅ merged (PR #247) |
| [A11Y-2 Reading pane header](A11Y-reading-header.md) | [#240](https://github.com/drawmeanelephant/solipsist/issues/240) | Reading | A11Y-1, A11Y-3..A11Y-5 | ✅ merged (PR #249) |
| [A11Y-3 Preview toolbar](A11Y-preview-toolbar.md) | [#241](https://github.com/drawmeanelephant/solipsist/issues/241) | Preview companion | A11Y-1, A11Y-2, A11Y-4, A11Y-5 | ✅ merged (PR #251) |
| [A11Y-4 Editor toolbar](A11Y-editor-toolbar.md) | [#242](https://github.com/drawmeanelephant/solipsist/issues/242) | Editor companion | A11Y-1..A11Y-3, A11Y-5 | ✅ merged (PR #252) |
| [A11Y-5 Mailbox sidebar counts](A11Y-sidebar-counts.md) | [#243](https://github.com/drawmeanelephant/solipsist/issues/243) | Mailboxes | — | ✅ merged (PR #244) |

Filed 2026-08-21 as #239–#243 (milestone 10). **All five children landed:**
#243 (PR #244), #239 (PR #247), #240 (PR #249), #241 (PR #251),
#242 (PR #252). #236 tracker closed. Do not grow a card into another
card's lane — the Owns / Do-not-touch lists are the contract.

## Do not start yet

Wasm in the app. The fart app.

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
