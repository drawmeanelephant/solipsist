# Card M17-3 — PR authoring from the mailbox (extract the M16-3 sheet)

**Milestone:** M17 (Pull Requests mailbox) · **Issue:**
[#192](https://github.com/drawmeanelephant/solipsist/issues/192)
**Lane:** play. One worktree, one PR against `main`;
branch suggestion `feat/github-pr-authoring-entry`.

Design gate: [`docs/M17-PR-MAILBOX-DESIGN.md`](../M17-PR-MAILBOX-DESIGN.md)
— the lane owns that file and the implementation.

## Owns

- `Sources/Play/GitHub/PullRequestSheet.swift` (new) — the M16-3
  `PullRequestSheet` (currently `private` inside
  `RemoteMailboxView.swift`) moved verbatim to file scope, internal,
  `describe` helper included. **No behavior change.**
- `Sources/Play/GitHub/RemoteMailboxView.swift` — presents the
  extracted sheet unchanged; its New Pull Request… button behaves
  identically.
- `Sources/Play/GitHub/PullRequestsMailboxView.swift` — toolbar gains
  **New Pull Request…** presenting the same sheet; on success the
  mailbox refreshes so the new PR appears.

## Do not touch

- The M16-3 flow itself: push-first when the branch has no upstream
  (M16-2 one-shot through the credential helper) → `POST /pulls` →
  open in the browser. Reused verbatim, never rewritten.
- `createPullRequest` / `GithubPullRequestCreated`; the git verbs;
  `Sources/Engine/**`, `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- Token in argv/env/logs; merge/close/review endpoints

## Do

1. Move the sheet (and its `describe`) out of `RemoteMailboxView.swift`
   — the extraction must compile with the Remote mailbox unchanged.
2. Add the toolbar entry to the PR mailbox; success → refresh the row
   list.
3. Verify the Remote mailbox's sheet still works (same flow, same
   tests).

## Gate

New Pull Request… works from the PR mailbox toolbar exactly as it did
from the Remote mailbox; the Remote surface is byte-for-byte the same
behavior. `make build` + `make test` green, no live GitHub in CI.
