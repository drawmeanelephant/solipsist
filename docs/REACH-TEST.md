# Solipsist — The Reach Test

**Status:** open quality program
**Question it answers:** when there is real work to do on a Boris
publication, do you open Solipsist — or the terminal?

Every gate on the roadmap has passed. That is not the same thing. This
document is the bar that remains: **one real unit of work, end to end,
inside the app.** Every exit, dead end, hesitation, or confusing moment
during a run is a finding — file it in `docs/issues/` style, fix it in
its lane per [`HARNESS.md`](HARNESS.md).

## The rule

Pick a real piece of work — a post, a fix, a publish — and do it
entirely inside Solipsist. No terminal, no other editor, no
`boris` CLI. The app is allowed to host a Boris surface (Preview,
`boris-editor`); it is not allowed to make you leave.

- **Pass** — the step did what a Mail-grade Mac app should.
- **Friction** — done, but with a stumble. File it.
- **Blocked** — could not be done in the app. File it first.

## The loop

| # | Step | Bar |
|---|------|-----|
| 1 | Cold open | Launch → add a real source → it appears as an account with mailboxes in seconds, not a project-setup ritual |
| 2 | Find the page | Trunks, filters, counts — you find the page you meant without knowing its path |
| 3 | Read it | Reading pane shows the page as a letter — served via `watch --serve` when up, contract summary when not |
| 4 | Edit it | Compose (`⌘⇧C`) or hosted editor → save → validate runs, Problems land somewhere visible |
| 5 | See it | Preview reloads through the watch session — no manual refresh, no second server |
| 6 | Break it | Introduce a real diagnostic → Problems surface it with a clickable location → fix → clears |
| 7 | Ship it | Plan / Build / Outputs show the fan-out; a publish target or dry run shows evidence + Proof Pack |
| 8 | Come back | Quit, relaunch → sources persist, selection survives, nothing half-configured |

Score honestly. "It worked but I had to think about it" is friction.

## Division of labor

- **Agent pass** — run the loop in a worktree against `Stunts/dogfood/`
  (45 pages / 7 trunks) and the `broken-*` corpora (each is a diagnostic
  vocabulary test: `EFRONTMATTER`, `EPARENTMISSING`, `EDUPLICATEID`,
  `EREFERENCEMISSING`). File findings; fix what is clearly in-lane.
- **Human pass** — same loop on a real publication, at real writing
  speed. Friction that survives the agent pass is the actual list.
- **Repeat until boring.** When a run produces no findings twice in a
  row, the next-layer candidates in [`ROADMAP.md`](ROADMAP.md) §3 earn
  their slots (recipe-scale mailbox, width-adaptive list split).

## What is out of scope

- Anything in ROADMAP §3 "v1 must not" stays out (no Markdown renderer,
  no Finder clone, no app HTTP server, no theme authoring).
- Boris-side defects found during a run go in `docs/issues/` as boris
  drafts — never a patch.
- New features do not count toward the reach test unless a run proves
  their absence is the friction.

## Build for a run

```bash
export SOLIPSIST_BORIS_BIN=~/.local/bin/boris \
       SOLIPSIST_OLIVER_BIN=~/.local/bin/oliver \
       BORIS_REPO_DIR=~/dev/boris \
       OLIVER_REPO_DIR=~/dev/oliver
make generate && make build
open build/Build/Products/Debug/Solipsist.app
```
