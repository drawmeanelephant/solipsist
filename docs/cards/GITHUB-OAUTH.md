# Card — GitHub source (OAuth device flow + `SourceKind.github` payload)

**Milestone:** M15 (first post-batch milestone) · **Issue:**
[#179](https://github.com/drawmeanelephant/solipsist/issues/179)
**Lane:** workspace / settings / play (see ownership table below).
One worktree, one PR against `main`; branch suggestion
`feat/github-source`.

Design gate: [`docs/GITHUB-OAUTH-DESIGN.md`](../GITHUB-OAUTH-DESIGN.md)
— the lane owns that file and the implementation. The design doc is the
spec; this card is the dispatch brief.

## Owns

- `Sources/Workspace/GitHub/` (new folder): `GithubSource.swift`,
  `GithubOAuth.swift` (device flow), `GithubAPIClient.swift`,
  `GithubSync.swift`
- `Sources/Security/GithubTokenStore.swift` + `--git-credential-helper`
  mode of the app binary (early-exit in `main`)
- `Sources/App/Settings/SourcesSettingsPane.swift` — **Add GitHub
  Account…** sheet (device flow + PAT fallback, scopes, sign out)
- `Sources/Play/GitHub/RemoteMailboxView.swift` — Remote mailbox:
  branch, ahead/behind, last-synced, Sync verb, Open on GitHub
- `SourceItem.github` case (all switches in `Sources/Workspace/Source.swift`)
- `Sources/Workspace/WorkspaceStore.swift` + `WorkspacePersistence.swift`
  — `addGithub` / `syncGithub` / remove-with-token-delete; token never
  persisted in the payload

## Do not touch

- `Sources/Engine/**` — boris never talks to GitHub; the working copy
  is the tree (D11)
- `Sources/Compose/**`, `Sources/Chrome/MainWindow.swift`
- Entitlements — `network.client` + keychain-access already exist
- Commit / push / PR / issues mailboxes (roadmap "Later")
- The M12 clone path (`GitClone`, Local sources) — a public clone into
  a folder stays Local business

## Do

1. **Device flow first** (`docs/GITHUB-OAUTH-DESIGN.md` §3): code →
   browser → poll (`interval`/`slow_down`/`expired_token` honored) →
   token → `GET /user` names the account → `GET /repos/owner/repo`
   gives `default_branch`. `client_id` from Info.plist (operator step),
   PAT paste as fallback.
2. **Credential discipline** (§4): `SecureBuffer` + `KeychainStore`
   (account `github:<owner>/<repo>`), never argv/env/logs/plist. Git
   auth via `git -c credential.helper=<app> …` helper mode.
3. **Add**: clone the default branch into a user-chosen sandbox folder
   (reuse `GitClone.clone`, `credential.helper` for private) →
   `WorkspaceStore.addGithub`.
4. **Remote mailbox**: branch + ahead/behind from the existing
   porcelain parsing; **Sync** = `fetch` + `pull --ff-only`, one-shot
   `Process` (not the engine slot), watch suspended via the
   COORDINATOR.md §3 primitives during the pull.
5. **Tests** (no network in CI): device-flow state machine with
   injected transport + clock; token lifecycle (mirror
   `SecurityTests`); `GithubSource` persistence round trip (token
   absent); sync invocation + porcelain parsing against a stub script;
   `SourceItem.github` exhaustiveness.

## Gate

Settings → **Add GitHub Account…** → device-flow confirm in the
browser → token in Keychain → default branch cloned → account header
with the GitHub symbol; Pages/Outputs/Publish/Plan/Activity work off
the working copy; **Remote** shows sync state and **Sync** pulls
(watch suspended/resumed, same port); relaunch → source persists with
no re-auth; sign out deletes the Keychain item. `SKIP_EMBED_BORIS=1
make build` + `make test` green; no live GitHub in CI.
