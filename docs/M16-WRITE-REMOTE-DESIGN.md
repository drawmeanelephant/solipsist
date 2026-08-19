# M16 — Write the remote: commit / push / PR authoring / issues mailbox

**Status:** landed — all four slices shipped (PRs #187 commit · #188
push · #189 PR authoring · #190 issues mailbox) against
[#185](https://github.com/drawmeanelephant/solipsist/issues/185) (cards
`cards/M16-commit.md` · `M16-push.md` · `M16-pr.md` · `M16-issues.md`).
Drafted by the dispatcher after M15 fully shipped (PRs #180–#184). The
lane owns this file and the implementation. This is the ROADMAP §3
"Later" remainder of the GitHub-source deferral — *"Fetch / pull /
commit / push on a checkout"* — with fetch + `pull --ff-only` already
moved up as M15's Remote mailbox Sync. What remains is everything that
**writes** the remote, kept deliberately out of M15: commit, push, PR
authoring, and the issues mailbox.

## 1. What exists today (do not redo)

| Piece | Current behavior |
|-------|------------------|
| `GithubSource` (`Sources/Workspace/GitHub/`) | Identity (`owner/repo`, default branch) + working-copy security-scoped bookmark. Transient: `branch`, `isSyncing`, `lastSyncError`, `lastSyncedAt`. `PlayFolderSource` conformance — every play surface runs on the working copy. |
| `GithubSync` + `SyncSession` | fetch + `pull --ff-only`, one-shot git processes (never the engine slot), `GIT_TERMINAL_PROMPT=0`, credential helper args from `GitClone.credentialHelperArguments`. Reuse the runner shape for every new git verb. |
| `GitClone` | `gitExecutableURL()` (CLT/Xcode resolution), `currentBranch`, `branchStatus(at:)` (ahead/behind via `status --porcelain=v2 --branch`), `CloneSession`. Reuse, do not re-derive. |
| `git-credential-solipsist` helper mode | App-binary early exit, Keychain host-keyed account `github`, token on stdout only. Every https git verb authenticates through it — **push included, no new auth surface.** |
| `GithubTokenStore` | Keychain-only token lifecycle; `delete()` is sign-out's only path (M15 #184). |
| `GithubAPIClient` + `GithubOAuth.HTTPTransport` | `GET /user`, `GET /repos/{owner}/{repo}`. Transport has form-`post` (device flow) and bearer-`get`. **No JSON POST yet** — PR creation and issue creation need a new `post(json:bearer:)` seam. |
| `WorkspaceMailbox` | Open vocabulary; M15 added `remote` for github-only rows via `WorkspaceMailbox.all(for:)`. A `issues` token follows the same pattern — never in `all`. |
| `RemoteMailboxView` | Branch, ahead/behind, last-synced, Sync verb (watch suspended for the pull), Open on GitHub. The natural home for the Commit / Push verbs. |
| Proof chain (M8) | Evidence commits are **Boris's** job (its own publish flow), not an app verb. The app's commit verb is for the user's own commits; it does not reach into `_boris/proof/` any more than any other surface. |

## 2. What M16 is

The Remote mailbox already reads the remote (branch, ahead/behind,
Sync). M16 adds the **write** side of that same loop, all through the
seams M15 built:

- **Commit** — the user's own commits on the working copy: a
  changed-files picker, a message, `git add <picked>` + `git commit`
  as one-shots (never `git add -A` — the repo's own git discipline,
  and the app never mutates the content tree except on an explicit
  save).
- **Push** — `git push` through the credential helper (no new auth
  surface), branch upstream tracking, ahead → 0 on success.
- **PR authoring** — push the current branch, then
  `POST /repos/{owner}/{repo}/pulls` with the Keychain bearer (new
  JSON-post seam), title + body from a sheet, base = the source's
  `defaultBranch` (from the remote, never guessed).
- **Issues mailbox** — a github-only mailbox token listing the repo's
  issues (`GET /repos/{owner}/{repo}/issues`), each row opening in the
  browser, plus a create-issue sheet (`POST`).

Four slices, one worktree / one PR each (the #167 slice pattern), all
behind this design gate. **Watch arbitration:** `git add`/`commit`/
`push` do not rewrite the content tree watch serves (only `.git` and
the index), so — unlike pull — none of them suspend watch. That is an
explicit decision, not an accident: the only tree-writing git verb is
`pull --ff-only`, which M15 already freezes watch for.

## 3. Commit (M16-1)

- **Changed-files picker, not `add -A`.** `git status --porcelain`
  parsed (extend `GitClone` with a `statusEntries(at:)` — same runner
  shape as `branchStatus`), listed in the sheet with checkboxes, the
  user picks, `git add -- <paths>` stages exactly those, `git commit`
  runs with the message. Nothing is staged that the user did not pick;
  untracked files appear so a new page can be committed deliberately.
- **Identity is never invented.** `git commit` with no
  `user.name`/`user.email` fails with git's own error — surfaced
  **verbatim** (D11), with a hint pointing at the repo config or a
  Settings identity row. The app never writes global config and never
  synthesizes an identity (no `-c user.name` / `user.email` flags,
  ever). M16-1 may add a Settings row that writes **repo-local**
  `user.name`/`user.email` only on the user's explicit save (the
  working copy's `.git/config`, never `--global`).
  **Probed fact (recorded for the lane):** git auto-derives an
  identity from username@hostname when none is configured, so a bare
  `git commit` on a fresh clone **succeeds** silently unless the user
  has set `user.useConfigOnly=true` (git's documented opt-out). The
  app surfaces whatever git does — the verbatim-error path is what a
  user with `useConfigOnly` (or a hardened setup) sees, and the
  auto-derived-identity case is git's own behavior, not the app
  inventing one. The test exercises the true error path via
  `useConfigOnly` + isolated config.
- **One-shots.** `GithubCommit`-style enum (or extend `GithubSync`)
  with the same `Session` cancel path as `SyncSession`. Watch keeps
  running (decision above); after the commit, `branchStatus` refreshes
  (ahead grows by 1), last-synced untouched.
- **What commits are for:** the user's work in the working copy —
  content edits, new pages, profile changes. Not the proof chain, not
  the app's own state, not `.boris/` artifacts unless the user picks
  them (they show in the picker like anything else).

## 4. Push (M16-2)

- `git push -u origin <branch>` (one-shot, credential helper,
  `GIT_TERMINAL_PROMPT=0`). `-u` sets upstream tracking when the
  branch is new — `branchStatus` then reports real ahead/behind
  against `origin/<branch>` instead of nil upstream.
- 401 / auth failure → git's stderr surfaced verbatim; the mailbox
  keeps the M15 §10 posture (`lastSyncError`, non-blocking; re-auth
  = the existing settings flow, since sign-out is the only token
  deletion path).
- Success → ahead → 0, `lastPushedAt` on the source (transient, like
  `lastSyncedAt`), Remote mailbox reflects it.
- **No force-push, ever.** The verb is a plain `git push`; any
  non-fast-forward rejection is git's own error, surfaced.

## 5. PR authoring (M16-3)

- **Seam first:** `GithubOAuth.HTTPTransport` gains
  `post(_ url: URL, json: Data, bearer: SecureBuffer) async throws ->
  Data` (stub in tests; the URLSession impl is a clone of `get` with
  a JSON body). `GithubAPIClient` gains `createPullRequest(owner:
  repository: title: body: head: base: bearer: transport:)` →
  `POST /repos/{owner}/{repo}/pulls`; the response carries `html_url`
  + `number`; non-2xx bodies surface as `httpStatus(status, message)`
  (D11 — never swallow).
- **Flow:** from the Remote mailbox, "New Pull Request…" → if the
  branch has no upstream, push it first (M16-2) → sheet with title +
  body (prefilled: branch name as title suggestion, never required) →
  `POST` → success opens the PR in the browser and offers "Open on
  GitHub". Base = `source.defaultBranch`, head = current branch. The
  user picks the base explicitly if they want a different one — never
  guessed beyond the stored default.
- **Do not:** fetch repo/branch lists without the user's pick;
  fabricate a title; merge anything; touch review/merge endpoints.

## 6. Issues mailbox (M16-4)

- New github-only mailbox token `issues` (pattern: M15 `remote` —
  `WorkspaceMailbox.all(for:)` appends it, never in `all`, `display`
  passes it through).
- `GithubAPIClient.listIssues(owner:repository:bearer:transport:)` →
  `GET /repos/{owner}/{repo}/issues?state=open` (REST returns PRs in
  the same list — filter `pull_request == nil`). Rows: number, title,
  labels; click → Open on GitHub (`NSWorkspace`, existing pattern).
- Create-issue sheet → `POST /repos/{owner}/{repo}/issues` (title +
  body) → row appears on refresh. This is the one M16 surface that is
  a *mailbox* rather than a Remote-mailbox verb.
- PRs stay out of this mailbox (the REST list mixes them; we filter).
  A Pull Requests mailbox is named in "Later", not built here.

## 7. Files and lanes

| File | Lane | Owns |
|------|------|------|
| `Sources/Workspace/GitHub/GithubCommit.swift` (or extend `GithubSync`) | workspace | commit + push one-shots, `Session` cancel, status-entries picker data |
| `Sources/Workspace/Git/GitClone.swift` | workspace | `statusEntries(at:)` porcelain parse (extend, do not re-derive) |
| `Sources/Workspace/GitHub/GithubAPIClient.swift` | workspace | `createPullRequest`, `listIssues`, `createIssue` |
| `Sources/Workspace/GitHub/GithubOAuth.swift` | workspace | transport gains `post(json:bearer:)` |
| `Sources/Play/GitHub/RemoteMailboxView.swift` | play | Commit + Push verbs, New Pull Request… sheet |
| `Sources/Play/GitHub/IssuesMailboxView.swift` (new) | play | issues mailbox rows + create sheet |
| `Sources/Workspace/WorkspaceSelection.swift` | workspace | `issues` mailbox token (github-only rows) |
| `Sources/Workspace/WorkspaceStore.swift` | workspace | `commitGithub` / `pushGithub` (one-shot, off main), transient `lastPushedAt` |
| `Sources/App/Settings/` | settings | repo-local identity row (M16-1, optional) |

**Untouched:** `Sources/Engine/**` (boris never talks to GitHub; the
working copy is the tree), `Sources/Compose/**`,
`Sources/Chrome/MainWindow.swift`, entitlements (`network.client` +
keychain-access already exist). Watch is **not** suspended for any M16
verb (decision §2).

## 8. Do not

- Reimplement git in Swift; re-derive `gitExecutableURL`; invent a
  second credential seam (reuse `SecureBuffer` / `KeychainStore` /
  helper mode).
- `git add -A` or stage files the user did not pick.
- Invent commit identity, force-push, or touch global git config.
- Fetch repo/branch lists without the user's pick; guess the base
  branch beyond `defaultBranch`; merge or review PRs.
- Put the token in argv/env/logs/plists (zero-leak invariant holds —
  every write verb authenticates via the helper or the Keychain
  bearer over the transport).
- Treat issues as a PR mailbox (filter `pull_request`); grow
  `Sources/Chrome/MainWindow.swift`; touch `Sources/Engine/**`.

## 9. Gate (how the lane proves it)

Manual, against the real app (`make build`; a GitHub source with a
working copy):

1. Edit a file in the working copy → Remote mailbox → **Commit** shows
   the changed file in the picker; commit with a message → ahead 1,
   working copy unchanged otherwise.
2. **Push** → ahead 0; the change is on the remote (verified via
   GitHub or a second clone).
3. **New Pull Request…** → title/body sheet → PR opens in the browser;
   the PR exists on `owner/repo`.
4. Issues mailbox lists the repo's open issues (no PRs in the list);
   create-issue sheet posts a new issue that appears on refresh.
5. Watch was never suspended across any of the above (preview keeps
   serving; the frozen-window guarantee is untouched).
6. `SKIP_EMBED_BORIS=1 make build` + `make test` green — **no live
   GitHub in CI**.

Automated (unit, injected transport + clock, no network):

- Transport `post(json:bearer:)` stub round trip; API client decodes
  PR/issue responses and surfaces non-2xx bodies.
- `statusEntries` porcelain parsing (v1 + v2 lines, untracked files).
- Commit/push invocation against a local bare remote (clone precedent,
  live but local — no network): add → commit → ahead 1 → push → 0;
  commit with no identity fails with git's error surfaced.
- `WorkspaceMailbox.all(for:)` github-only `issues` row.

## 10. Edge cases

- **No commit identity configured:** git's own "Please tell me who you
  are" surfaces verbatim with a repo-config hint; the commit is not
  attempted with a fake identity.
- **Non-fast-forward push:** git's rejection surfaced verbatim; the
  user pulls (existing Sync verb), never a force-push.
- **PR from a branch with no upstream:** M16-3 pushes it first
  (`-u`), then creates the PR — one user-visible action, two git
  verbs.
- **Token revoked while composing:** the API write fails with 401 →
  `httpStatus(401, …)` surfaced, the M15 §10 `needsAuth` posture
  (non-blocking, re-auth via the existing flow).
- **Issues list empty:** honest empty state, never a fake row.
- **Working copy deleted:** the picker shows an unavailable state
  (existing badge); Commit/Push disabled until Relocate or re-clone.

## 11. Sequencing

M16-1 (commit) first — it unblocks M16-2 (push), and M16-3 needs
push. M16-4 (issues) is independent of the git verbs and can run
parallel with M16-1. Cards below; one worktree, one PR each, all
against `main`.
