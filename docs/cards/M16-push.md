# Card M16-2 — Push verb (`git push` through the credential helper)

**Milestone:** M16 (write the remote) · **Issue:**
[#185](https://github.com/drawmeanelephant/solipsist/issues/185)
**Lane:** workspace / play. One worktree, one PR against `main`;
branch suggestion `feat/github-push`.

Design gate: [`docs/M16-WRITE-REMOTE-DESIGN.md`](../M16-WRITE-REMOTE-DESIGN.md)
— the lane owns that file and the implementation.

## Owns

- `Sources/Workspace/GitHub/GithubCommit.swift` (or the commit slice's
  file — this lane may extend it) — `git push -u origin <branch>`
  one-shot, credential helper, `GIT_TERMINAL_PROMPT=0`, `Session`
  cancel.
- `Sources/Workspace/GitHub/GithubSource.swift` — transient
  `lastPushedAt: Date?` (not persisted, like `lastSyncedAt`).
- `Sources/Play/GitHub/RemoteMailboxView.swift` — Push verb next to
  Sync/Commit; success → ahead 0 + last-pushed shown.

## Do not touch

- `Sources/Engine/**`, `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- Force-push, ever; the credential helper seam (reuse, do not re-derive)
- The token in argv/env/logs

## Do

1. Push one-shot with `-u` (sets upstream tracking for a new branch).
2. Surface git's stderr verbatim on failure — 401 → the M15 §10
   `needsAuth` posture (non-blocking; re-auth via the existing
   settings flow).
3. On success: ahead → 0, `lastPushedAt` set, Remote mailbox reflects
   it.
4. Watch is **not** suspended (design §2).

## Gate

After an M16-1 commit, Push → ahead 0; the change is on the remote
(verified via GitHub or a second clone). Non-fast-forward rejection =
git's error, no force-push. `make build` + `make test` green.
