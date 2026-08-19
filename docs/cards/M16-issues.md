# Card M16-4 — Issues mailbox (`GET/POST /repos/{owner}/{repo}/issues`)

**Milestone:** M16 (write the remote) · **Issue:**
[#185](https://github.com/drawmeanelephant/solipsist/issues/185)
**Lane:** workspace / play. One worktree, one PR against `main`;
branch suggestion `feat/github-issues`.

Design gate: [`docs/M16-WRITE-REMOTE-DESIGN.md`](../M16-WRITE-REMOTE-DESIGN.md)
— the lane owns that file and the implementation.

## Owns

- `Sources/Workspace/WorkspaceSelection.swift` — `issues` mailbox
  token, github-only via `WorkspaceMailbox.all(for:)` (M15 `remote`
  pattern: never in `all`, `display` passes through).
- `Sources/Workspace/GitHub/GithubAPIClient.swift` — `listIssues`
  (`?state=open`, filter `pull_request == nil` — REST mixes PRs into
  issues) + `createIssue` (title/body).
- `Sources/Workspace/GitHub/GithubOAuth.swift` — transport JSON-post
  seam shared with M16-3 (merge order: after or with that card).
- `Sources/Play/GitHub/IssuesMailboxView.swift` (new) — rows (number,
  title, labels) → Open on GitHub; create-issue sheet.

## Do not touch

- `Sources/Engine/**`, `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- A Pull Requests mailbox (named "Later", not built here)
- Token in argv/env/logs; repo/branch list fetches without the user's pick

## Do

1. `issues` mailbox token + sidebar row for github sources only;
   `LocalPlay` switch case → `IssuesMailboxView`.
2. List issues (open, PRs filtered), honest empty state.
3. Create-issue sheet → row appears on refresh; API errors surfaced
   (D11).

## Gate

Issues mailbox lists the repo's open issues with no PRs in the list;
create-issue posts a new issue that appears on refresh. API unit tests
green; `make build` + `make test` green.
