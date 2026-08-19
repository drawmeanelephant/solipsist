# Card M16-1 — Commit verb (changed-files picker + git commit)

**Milestone:** M16 (write the remote) · **Issue:**
[#185](https://github.com/drawmeanelephant/solipsist/issues/185)
**Lane:** workspace / play / settings. One worktree, one PR against
`main`; branch suggestion `feat/github-commit`.

Design gate: [`docs/M16-WRITE-REMOTE-DESIGN.md`](../M16-WRITE-REMOTE-DESIGN.md)
— the lane owns that file and the implementation.

## Owns

- `Sources/Workspace/Git/GitClone.swift` — extend with
  `statusEntries(at:)` (parse `status --porcelain` v1/v2 + untracked;
  same runner shape as `branchStatus`). Do not re-derive the runner.
- `Sources/Workspace/GitHub/GithubCommit.swift` (new) — `git add --`
  + `git commit` one-shots with a `Session` cancel path (SyncSession
  shape); identity is never invented — git's missing-identity error
  surfaces verbatim.
- `Sources/Play/GitHub/RemoteMailboxView.swift` — Commit verb +
  changed-files picker sheet (checkboxes → `git add -- <picked>` →
  commit → `branchStatus` refresh).
- `Sources/App/Settings/` — optional repo-local identity row (writes
  `user.name`/`user.email` to the working copy's `.git/config` only
  on explicit save; never `--global`).

## Do not touch

- `Sources/Engine/**`, `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- `git add -A`; staging anything the user did not pick
- Global git config; invented identity; force-push
- The `GithubSync` fetch/pull path (read-only, keep)

## Do

1. `statusEntries(at:)` porcelain parse + tests (v1/v2, untracked,
   deleted, renamed).
2. Picker sheet in the Remote mailbox: changed files with checkboxes,
   commit-message field, Commit button. Runs one-shots off the main
   actor; cancel = SIGTERM.
3. After commit: `branchStatus` refresh (ahead grows by 1), surface
   git's exit + stderr verbatim on failure (D11).
4. Missing `user.name`/`user.email` → git's error surfaced with a
   repo-config hint (and the Settings row if shipped).
5. Watch is **not** suspended for commit (design §2) — nothing in
   this slice calls `beginTreeWrite`.

## Gate

Edit a file in the working copy → Commit picker shows it → commit with
a message → ahead 1, working copy otherwise untouched; no identity →
git's own error, no fake commit. `make build` + `make test` green, no
live GitHub in CI.
