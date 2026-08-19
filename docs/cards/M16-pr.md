# Card M16-3 — PR authoring (`POST /repos/{owner}/{repo}/pulls`)

**Milestone:** M16 (write the remote) · **Issue:**
[#185](https://github.com/drawmeanelephant/solipsist/issues/185)
**Lane:** workspace / play. One worktree, one PR against `main`;
branch suggestion `feat/github-pr`.

Design gate: [`docs/M16-WRITE-REMOTE-DESIGN.md`](../M16-WRITE-REMOTE-DESIGN.md)
— the lane owns that file and the implementation.

## Owns

- `Sources/Workspace/GitHub/GithubOAuth.swift` — `HTTPTransport` gains
  `post(_ url: JSON, bearer: SecureBuffer)` (URLSession impl clones
  `get`; test stubs updated in `GithubTestSupport.swift`).
- `Sources/Workspace/GitHub/GithubAPIClient.swift` —
  `createPullRequest(owner:repository:title:body:head:base:bearer:
  transport:)`; response carries `html_url` + `number`; non-2xx
  bodies → `httpStatus(status, message)` (D11).
- `Sources/Play/GitHub/RemoteMailboxView.swift` — New Pull Request…
  sheet (title + body; branch-name title suggestion, never required;
  base = `source.defaultBranch`, user may override).

## Do not touch

- `Sources/Engine/**`, `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- Fetching repo/branch lists without the user's pick
- Merge / review endpoints; force-push; token in argv/env/logs

## Do

1. Transport JSON-post seam + stub in tests (CI never touches GitHub).
2. API client: create-PR decode + error surfacing; tests for 2xx and
   non-2xx bodies.
3. Sheet flow: no upstream → push first (`-u`, M16-2's one-shot) →
   `POST` → success opens the PR in the browser (existing
   `NSWorkspace` pattern).

## Gate

Remote mailbox → New Pull Request… → title/body → PR opens in the
browser and exists on `owner/repo`. Transport/API unit tests green;
`make build` + `make test` green.
