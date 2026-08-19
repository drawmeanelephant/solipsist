# Card M17-1 — PR list seam (`GET /repos/{owner}/{repo}/pulls`)

**Milestone:** M17 (Pull Requests mailbox) · **Issue:**
[#192](https://github.com/drawmeanelephant/solipsist/issues/192)
**Lane:** workspace. One worktree, one PR against `main`;
branch suggestion `feat/github-pr-list`.

Design gate: [`docs/M17-PR-MAILBOX-DESIGN.md`](../M17-PR-MAILBOX-DESIGN.md)
— the lane owns that file and the implementation.

## Owns

- `Sources/Workspace/GitHub/GithubAPIClient.swift` — `GithubPullRequest`
  model (`number`, `title`, `html_url`, `draft`, `state`, `head` +
  `base` as `{label, ref}`) and
  `listPullRequests(owner:repository:state:bearer:transport:)` →
  `GET pullsURL` with `?state=` (default `open`). Same error contract
  as every client call: non-2xx bodies surface as
  `httpStatus(status, message)` (D11). Uses the existing bearer-`get`
  transport seam — no new transport code.

## Do not touch

- `createPullRequest` / `GithubPullRequestCreated` (M16-3, ships as-is)
- The issues-list `pull_request` filter (that mailbox keeps it; this
  slice uses `/pulls`, the proper source)
- `Sources/Engine/**`, `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- Token in argv/env/logs; merge/close/review endpoints

## Do

1. `GithubPullRequest` + `GithubPullRequestRef` (head/base) decode,
   `convertFromSnakeCase` not needed — explicit CodingKeys match the
   GitHub wire (`html_url`, `head.ref`, `base.ref`).
2. `listPullRequests` with `state` defaulting to `open`.
3. Tests (injected `StubTransport`, no network): draft true/false
   decode, fork `head.label` (`owner:branch`), `state=open` rides the
   URL, non-2xx surfaced verbatim.

## Gate

`listPullRequests` decodes a real `/pulls` list shape (draft + head →
base) and errors surface as `httpStatus`; `make build` + `make test`
green, no live GitHub in CI.
