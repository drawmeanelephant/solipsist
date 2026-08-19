# M17 — Pull Requests mailbox (the deferred "Later" item)

**Status:** design gate for
[#192](https://github.com/drawmeanelephant/solipsist/issues/192) (cards
`cards/M17-pr-list.md` · `M17-pr-mailbox.md` · `M17-pr-authoring.md`).
Drafted by the dispatcher after M16 fully shipped (PRs #187–#190). The
lane owns this file and the implementation. This is the ROADMAP §3
"Later" remainder of the GitHub-source deferral — *"A Pull Requests
mailbox (the issues mailbox filters PRs out of the REST list; a
dedicated PR mailbox stays later)"*. M16 built every seam this needs;
nothing here is a new code path.

## 1. What exists today (do not redo)

| Piece | Current behavior |
|-------|------------------|
| `GithubSource` (`Sources/Workspace/GitHub/`) | Identity (`owner/repo`, default branch) + working-copy bookmark. `PlayFolderSource` conformance; github-only `remote` (M15) and `issues` (M16-4) mailbox tokens via `WorkspaceMailbox.all(for:)`. |
| `GithubAPIClient` | `user`, `repository`, `createPullRequest` (returns `GithubPullRequestCreated` = `number` + `html_url`), `listIssues` (filters `pull_request == nil` — REST mixes PRs into `/issues`), `createIssue`. `pullsURL(owner:repository:)` exists. |
| `GithubOAuth.HTTPTransport` | bearer `get` + form `post` + JSON `post` seams (M16-3). Token rides a `SecureBuffer`; the transport builds the Authorization header — zero-leak invariant. |
| `IssuesMailboxView` (`Sources/Play/GitHub/`) | The mailbox pattern to mirror: rows → Open on GitHub, honest empty state, needsAuth posture on 401/403, D11 (error bodies verbatim). |
| `RemoteMailboxView` | Sync / Commit / Push verbs + **New Pull Request…** sheet (`PullRequestSheet`, currently `private` to that file): push-first when the branch has no upstream, base = `defaultBranch`, success opens the PR in the browser. |
| `GitClone` + `git-credential-solipsist` | The git verbs. The PR mailbox itself is **API-only** — it never touches the working copy, `.git`, or the engine. |

## 2. What M17 is

The read sibling of the M16-4 issues mailbox: a github-only mailbox
token `pulls`, listing the repo's open pull requests via the **proper
REST endpoint** (`GET /repos/{owner}/{repo}/pulls`), rows opening in
the browser. Unlike the issues list (which mixes PRs in shallow form),
`/pulls` returns full PR objects — draft state, head + base refs — so
the mailbox renders what a PR mailbox should: `#number · title · head →
base`, with a draft badge, no issues mixed in.

Three slices, one worktree / one PR each (the #167 / M16 slice
pattern), all behind this design gate:

- **M17-1 PR list seam** — `GithubAPIClient.listPullRequests` +
  `GithubPullRequest` model over the existing bearer-`get` transport.
  No UI.
- **M17-2 PR mailbox surface** — the `pulls` token (github-only rows,
  M16-4 `issues` pattern), `PullRequestsMailboxView`, `LocalPlay`
  case, sidebar row (automatic via `all(for:)`).
- **M17-3 Authoring from the mailbox** — extract the M16-3
  `PullRequestSheet` out of `RemoteMailboxView.swift` (it is `private`
  there today) so the PR mailbox's toolbar can present it too. No new
  git or API behavior — the M16-3 flow (push-first when no upstream →
  `POST /pulls` → open in browser) is reused verbatim.

**Watch arbitration:** none of the slices touch the content tree — the
mailbox reads/writes the GitHub API, never the working copy. Watch is
never suspended (the same decision M16-4 already made for issues).

## 3. M17-1 — PR list seam

- `GithubPullRequest` (new model, `Decodable, Equatable, Sendable`):
  `number`, `title`, `htmlURL` (`html_url`), `draft: Bool`, `state`,
  `head` + `base` as `{label, ref}` sub-structs (`head` is
  `owner:branch` for fork PRs — the row renders `label`, which is the
  GitHub-facing truth, never a guessed owner).
- `GithubAPIClient.listPullRequests(owner:repository:state:bearer:
  transport:)` → `GET pullsURL` with `?state=` (default `open` — the
  mailbox's honest default, mirroring the issues mailbox; the param
  exists for tests and a future closed/all toggle). Same error
  contract as every other client call: non-2xx bodies surface as
  `httpStatus(status, message)` (D11 — never swallow).
- `createPullRequest` and `GithubPullRequestCreated` are **untouched**
  (M16-3 ships as-is). The list model duplicates `number` + `html_url`;
  folding `Created` into the rich model is a lane decision, not
  required.

## 4. M17-2 — PR mailbox surface

- New github-only mailbox token `pulls` (M16-4 `issues` pattern:
  `WorkspaceMailbox.all(for:)` appends it, never in `all`, `display`
  passes through, `displayName` "Pull Requests", a branch-style
  symbol). The sidebar picks the row up automatically — no Chrome
  edit.
- `PullRequestsMailboxView` (`Sources/Play/GitHub/`, new): rows
  `#number · title · head → base` with a **draft badge** (open draft
  PRs are included by `state=open`), click → Open on GitHub
  (`NSWorkspace`, existing pattern). Honest empty state ("No Open Pull
  Requests"), loading + error states, the M15 §10 needsAuth posture on
  401/403 (non-blocking, re-auth via the settings flow).
- `LocalPlay` switch case → the new view (github cast + honest trunk
  fallback, exactly as `issues`/`remote` do).
- No issues mixed in — this mailbox uses `/pulls`, not the
  issues-list filter (see §7).

## 5. M17-3 — Authoring from the mailbox

- Extract `PullRequestSheet` from `RemoteMailboxView.swift` into a
  shared file (e.g. `Sources/Play/GitHub/PullRequestSheet.swift`,
  internal, `describe` helper included). `RemoteMailboxView` presents
  it unchanged — the Remote mailbox's New Pull Request… button behaves
  identically.
- `PullRequestsMailboxView`'s toolbar gains **New Pull Request…**
  presenting the same sheet. The M16-3 flow runs verbatim: branch with
  no upstream → push first (the M16-2 one-shot through the credential
  helper) → `POST /pulls` → success opens the PR and the mailbox
  refreshes (the new PR appears).
- Zero new auth surface, zero new git verbs, zero new API calls — this
  slice is relocation + a toolbar entry, nothing invented.

## 6. Files and lanes

| File | Lane | Owns |
|------|------|------|
| `Sources/Workspace/GitHub/GithubAPIClient.swift` | workspace | `GithubPullRequest` model + `listPullRequests` (M17-1) |
| `Sources/Workspace/WorkspaceSelection.swift` | workspace | `pulls` mailbox token, github-only rows (M17-2) |
| `Sources/Play/GitHub/PullRequestsMailboxView.swift` (new) | play | rows → Open on GitHub, draft badge, empty state, needsAuth posture (M17-2) |
| `Sources/Play/Local/LocalPlay.swift` | play | `pulls` switch case (M17-2) |
| `Sources/Play/GitHub/PullRequestSheet.swift` (new, extracted) | play | shared authoring sheet; `RemoteMailboxView.swift` presents it unchanged (M17-3) |

**Untouched:** `Sources/Engine/**` (boris never talks to GitHub), the
git verbs (`GitClone`, `GithubSync`, `GithubCommit`, credential
helper), `Sources/Chrome/MainWindow.swift`, watch primitives, and
`createPullRequest`/`GithubPullRequestCreated` (M16-3, ships as-is).

## 7. Do not

- Reimplement git in Swift; invent a second credential seam; put the
  token in argv/env/logs/plists (zero-leak invariant holds — the
  bearer's only stop is the transient Authorization header).
- **Merge, close, or review PRs.** The M16 "do not merge anything"
  discipline holds; `/pulls/{n}/merge` and `PATCH /pulls/{n}` are out
  of scope for this Later item. A close verb, if ever wanted, is a
  separate design.
- Build the mailbox on the issues-list `pull_request` filter — `/pulls`
  is the proper source (full objects: draft, head, base). The issues
  mailbox keeps filtering for its own correctness.
- Change `createPullRequest`'s behavior or return type (M17-3 only
  relocates its sheet).
- Suspend watch; touch the working copy or `.git`; fetch repo/branch
  lists without the user's pick; grow `Sources/Chrome/MainWindow.swift`.

## 8. Gate (how the lane proves it)

Manual, against the real app (`make build`; a GitHub source with a
repo that has open PRs — including at least one draft):

1. Pull Requests mailbox lists the repo's open PRs (no issues mixed
   in); draft PRs show the draft badge; rows show `head → base`.
2. Click a row → the PR opens in the browser.
3. **New Pull Request…** works from the PR mailbox toolbar exactly as
   it did from the Remote mailbox (new branch → pushed first → PR
   opens; mailbox refreshes to show it).
4. Empty repo → honest "No Open Pull Requests" state.
5. Watch never suspended; preview keeps serving (API-only surface).
6. `SKIP_EMBED_BORIS=1 make build` + `make test` green — **no live
   GitHub in CI**.

Automated (unit, injected transport, no network):

- `listPullRequests` decode: draft true/false, head/base refs and fork
  labels, `state=open` rides the URL, non-2xx bodies surface as
  `httpStatus` (D11).
- `WorkspaceMailbox.all(for:)` github-only `pulls` row; Local sources
  untouched.
- M17-3: the extracted sheet keeps the Remote flow — existing
  `GithubAPIClientTests` (create-PR seam) and the Remote mailbox's
  behavior are unchanged (compile-level proof + suite green).

## 9. Edge cases

- **Token revoked while composing:** the API read/write fails with 401
  → `httpStatus(401, …)` surfaced, the M15 §10 `needsAuth` posture
  (non-blocking, re-auth via the existing flow).
- **Draft PRs:** shown with the draft badge, not hidden — open drafts
  are part of `state=open`.
- **Fork PRs:** `head.label` renders `owner:branch` (GitHub's own
  label), never a guessed owner.
- **PR list empty:** honest empty state, never a fake row.
- **Working copy unrelated/deleted:** irrelevant — the mailbox is
  API-only and needs only the source's identity, but the github row
  set still requires a `GithubSource` (it cannot exist without one).
- **Sheet extraction regression:** the Remote mailbox's New Pull
  Request… must behave identically after the move (same tests, same
  flow).

## 10. Sequencing

M17-1 (seam) first — it unblocks M17-2 (surface). M17-3 (authoring
entry) depends on M17-2's toolbar and can run immediately after (or
parallel with) it; the extraction is mechanical but touches the
Remote mailbox, so sequence it after the surface lands. One worktree,
one PR each, all against `main`.
