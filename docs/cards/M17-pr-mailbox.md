# Card M17-2 — Pull Requests mailbox surface (`pulls` token + rows)

**Milestone:** M17 (Pull Requests mailbox) · **Issue:**
[#192](https://github.com/drawmeanelephant/solipsist/issues/192)
**Lane:** workspace / play. One worktree, one PR against `main`;
branch suggestion `feat/github-pr-mailbox`.

Design gate: [`docs/M17-PR-MAILBOX-DESIGN.md`](../M17-PR-MAILBOX-DESIGN.md)
— the lane owns that file and the implementation.

## Owns

- `Sources/Workspace/WorkspaceSelection.swift` — `pulls` mailbox token,
  github-only via `WorkspaceMailbox.all(for:)` (M16-4 `issues`
  pattern: never in `all`, `display` passes through, `displayName`
  "Pull Requests", branch-style symbol).
- `Sources/Play/GitHub/PullRequestsMailboxView.swift` (new) — rows
  `#number · title · head → base` with a draft badge; click → Open on
  GitHub (`NSWorkspace`, existing pattern); honest "No Open Pull
  Requests" empty state; loading/error states; the M15 §10 needsAuth
  posture on 401/403.
- `Sources/Play/Local/LocalPlay.swift` — `pulls` switch case → the new
  view (github cast + honest trunk fallback, exactly as `issues` /
  `remote` do).

## Do not touch

- `Sources/Engine/**`, `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- The issues mailbox / `listIssues` filter (keep)
- Merge/close/review endpoints; token in argv/env/logs
- Watch primitives — this mailbox is API-only, never suspended

## Do

1. `pulls` token + sidebar row for github sources only (the row
   appears automatically via `all(for:)` — no Chrome edit).
2. `PullRequestsMailboxView`: load via `GithubTokenStore` +
   `URLSessionGithubTransport` + `listPullRequests` (M17-1), rows →
   browser, draft badge, honest empty state, error bodies verbatim
   (D11) with the needsAuth hint on 401/403.
3. Tests: github-only `pulls` row (Local sources untouched), token
   load path via the stub transport.

## Gate

Pull Requests mailbox lists the repo's open PRs (no issues mixed in,
drafts badged); click opens the PR; empty repo → honest empty state.
`make build` + `make test` green, no live GitHub in CI.
