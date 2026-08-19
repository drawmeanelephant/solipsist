# GitHub OAuth / `SourceKind.github` — Design Specification

**Status:** design gate for
[#179](https://github.com/drawmeanelephant/solipsist/issues/179)
(card [`cards/GITHUB-OAUTH.md`](cards/GITHUB-OAUTH.md)). Drafted by the
dispatcher to jump-start the GitHub-source lane; the lane owns this file
and the implementation. This is the ROADMAP §3 "Later" item — *"GitHub
as its own `SourceKind` (OAuth / app password, not just a clone)"* —
kicked off now that the board is empty of grind cards. The clone slice
(M12 / #131 → PRs #152/#153) stays exactly what it is: URL → folder →
Local source. This design is the authenticated remote **payload** the
clone was explicitly not.

## 1. What exists today (do not redo)

| Piece | Current behavior |
|-------|------------------|
| `SourceKind` (`Sources/Workspace/Source.swift`) | Enum already has a `.github` case with symbol `chevron.left.forwardslash.chevron.right` and displayName `GitHub` — **no payload behind it**. Chrome reads only `id` / `title` / `kind`, so a payload lands without chrome changes. |
| `SourceItem` | Only `.local(LocalSource)` today. Add `.github(GithubSource)`; every `switch` in the enum gains one case. |
| `WorkspaceStore` | `addLocal` / `relocate` / `remove` / `beginAccess` (security-scoped bookmark + start/stop access) / `persist` (UserDefaults via `WorkspacePersistence`, locals only). |
| `GitClone` (`Sources/Workspace/Git/GitClone.swift`) | Proven one-shot `/usr/bin/git` runner with the **sandbox trap solved**: the real CLT/Xcode git is resolved (`gitExecutableURL`), xcrun shim refused. `CloneSession` for SIGTERM-cancel, `currentBranch` / porcelain parsing, URL validation. Reuse, do not re-derive. |
| `CREDENTIAL-LIFECYCLE.md` | Approved design spec (#60): `SecureBuffer` (zeroing), `KeychainStore` (service `dev.drawmeanelephant.solipsist`), `EphemeralSecretStore`, stdin delivery, the zero-leak invariant (no argv / env / logs / plaintext files). GitHub tokens are secrets — same discipline. |
| Coordinator (#58, `docs/COORDINATOR.md`) | `WatchServer.suspend()` / `resume()` (SIGSTOP/SIGCONT) + weak registry. Tree-writing one-shots suspend watch. **Git is not boris** — git verbs are settings-adjacent one-shots (clone precedent), never the engine's `Process?` slot. |

## 2. What a GitHub source is

A `GithubSource` is an **authenticated remote publication**: identity
(`owner/repo`, default branch, granted scopes) plus a **local working
copy** the way every other source is a folder. Boris is a subprocess
that reads a filesystem tree — it cannot talk to GitHub. So the payload
wraps a sandbox-bookmarked working copy, and **every existing surface
(play, mailboxes, inspector, compose, watch, plan/validate/build)
operates on the working copy exactly as it does for a Local source.**

```swift
struct GithubSource: PublicationSource, Hashable, Sendable, Codable {
    var id: SourceID
    var title: String              // "owner/repo"
    var owner: String
    var repository: String
    var defaultBranch: String      // from the remote, not guessed
    var bookmarkData: Data         // working-copy folder, LocalSource-style
    var displayPath: String
    var grantedScopes: [String]    // display-only; never the token
    // Transient (not persisted): resolved at load, like LocalSource.
    var isAvailable: Bool = true
    var branch: String? = nil
    var isSyncing: Bool = false
    var lastSyncError: String? = nil
}
```

`SourceItem` gains `.github(GithubSource)`; `kind` returns `.github`
(already in the enum). Persistence: `WorkspacePersistence` gains a
`github: [GithubSource]` array beside `sources: [LocalSource]` (the
token itself never touches UserDefaults — see §4).

**The fence from M12 still holds:** a *clone* of a public repo into a
folder is Local-source business and stays that way. `GithubSource` is
chosen deliberately in Settings ("Add GitHub Account…"), not inferred
from a folder's `.git/config`.

## 3. OAuth: GitHub device flow (primary) + fine-grained PAT (fallback)

The roadmap names "OAuth / app password". Both are supported; the
primary is **device flow** because it needs no redirect URI, no
`ASWebAuthenticationSession`, and no secret on the client — built for
CLI/native apps, and it works even when the confirmation happens on
another device.

### Device flow steps (app-owned; boris has no GitHub OAuth surface)

1. `POST https://github.com/login/device/code` (form: `client_id`,
   `scope=repo`) → `device_code`, `user_code`, `verification_uri`,
   `expires_in`, `interval`. Accept `application/json`.
2. `NSWorkspace.shared.open(verification_uri)` — sandbox-safe (URL
   open is permitted; `network.client` covers the polling). Show the
   `user_code` in the sheet too (the user may be confirming elsewhere).
3. Poll `POST https://github.com/login/oauth/access_token` (form:
   `client_id`, `device_code`,
   `grant_type=urn:ietf:params:oauth:grant-type:device_code`) every
   `interval` until success or error:
   - `authorization_pending` → keep polling (respect `interval`).
   - `slow_down` → increase interval by 5 s (server's contract).
   - `expired_token` / `access_denied` → surface, never retry silently.
4. On success: `GET https://api.github.com/user` with
   `Authorization: Bearer <token>` → `login`, `name`, `id`, avatar.
   The login becomes the account title; then `GET /repos/owner/repo`
   for `default_branch`.
5. Token → Keychain (§4). Any step's non-2xx / error body is surfaced
   (D11: never swallow), and the poll loop cancels with the sheet.

**`client_id` is an operator step** (like #110/#111): register a GitHub
OAuth App (device flow, no secret) and put the client id in the app's
Info.plist. The client id is public by design — it is not a secret and
not a credential. The seam reads it from the bundle so tests inject a
stub id and CI never touches GitHub.

**Fallback — app password / PAT:** a fine-grained personal access token
pasted into the sheet (the "app password" the roadmap names). Same
storage + git delivery as the device-flow token, zero scopes required
for public repos, `repo` for private. The sheet offers "Use a token
instead".

### Scopes

Request `repo` (covers public + private read for clone/sync; no write
scope exists in that grant beyond the user's choice). The granted
scopes returned by GitHub are stored in `grantedScopes` (display-only)
and shown in Settings — the user sees exactly what the source can do.
No `workflow`/`admin` scopes, ever.

## 4. Credential lifecycle (reuse, extend)

The token is a `SecureBuffer` at rest and in memory; the Keychain is the
only persistence. CREDENTIAL-LIFECYCLE.md invariants hold verbatim:
never argv, never env, never logs, never plaintext files.

- **Keychain:** `kSecClassGenericPassword`, service
  `dev.drawmeanelephant.solipsist`, **account `github` — host-keyed,
  not per-repo**. Probed against CLT/Xcode git: the credential-helper
  input carries only `protocol` / `host` / `username` — git omits the
  repo `path` — so a `github:<owner>/<repo>` account could never be
  looked up by the helper. This also matches the OAuth reality: one
  device-flow token per GitHub user per client, used for every repo
  that user can reach. `GithubTokenStore` (new, `Sources/Security/`)
  wraps `KeychainStore` + `SecureBuffer`; the source payload never
  carries the token. Restart → source persists and the token is still
  there (B3-2-style gate: no re-auth on relaunch).
  **Limitation:** one GitHub account per install — multiple accounts
  stay later (the helper cannot distinguish them by host alone).
- **Ephemeral vs remembered:** unlike publish secrets, a *source*
  token must survive relaunch — the source IS the account. So the
  default is Keychain persistence with the existing opt-out pattern;
  "sign out" deletes the Keychain item (and, for PAT, offers to delete
  the credential on GitHub — device-flow tokens cannot be revoked via
  API; the user is pointed at github.com/settings/security).
- **Git delivery — `git-credential-solipsist`, helper mode of the app
  binary.** Git verbs authenticate via
  `git -c credential.helper=<app> …`, where `<app>` is the app's own
  executable launched with a `--git-credential-helper` flag (early
  exit path in `main`, like `xcodebuild -runFirstLaunch`). Git invokes
  the helper with `get`, the helper reads the Keychain and prints
  `username=x-access-token\npassword=<token>` on **stdout** (git's own
  pipe). The token travels Keychain → helper stdout → git pipe: never
  argv, never env, never on disk. This mirrors
  `git-credential-osxkeychain`, is sandbox-safe (the app already holds
  keychain-access), and avoids embedding a second binary.
  Rejected: `GIT_ASKPASS` scripts that must *know* the token, and
  `https://x-access-token:<token>@…` URLs (token in argv, visible to
  `ps` — zero-leak violation).

## 5. Git verbs (v1 scope)

| Verb | Mechanism | Arbitrates with watch? | Engine slot? |
|------|-----------|------------------------|--------------|
| **Add GitHub Account…** | Device-flow sheet → clone the default branch into a user-chosen sandbox folder via `GitClone.clone` with `credential.helper` (private repos) → `WorkspaceStore.addGithub(...)` | no (new source, no watch yet) | **no** — Settings one-shot, clone precedent |
| **Sync** (Remote mailbox verb) | `git -C <worktree> fetch` then `git -C <worktree> pull --ff-only` (same helper), one-shot `Process` + `SyncSession` cancel like `CloneSession` | **yes** — the working copy is the tree watch serves: SIGSTOP watch (COORDINATOR.md §3 primitives), pull, SIGCONT | **no** — git is not boris; parallel one-shot is the established pattern |
| Branch / ahead-behind | Reuse `GitClone.currentBranch` porcelain parsing | n/a | n/a |

**Out of v1 (roadmap §3 "Later" keeps them later):** commit, push, pull
request authoring, issue mailboxes. The deferral said *"Fetch / pull /
commit / push on a checkout (clone is M12; remotes stay later)"* — the
design decision here is that **Sync is load-bearing for a GitHub
source** (a mailbox that never refreshes is not a mailbox), so fetch +
`pull --ff-only` move up with this lane; everything that *writes* the
remote (push, PRs, issues) stays out. If the lane disagrees, it must
say why in the issue — this is the one deliberate re-scope.

## 6. Files and lanes

| File | Lane | Owns |
|------|------|------|
| `Sources/Workspace/GitHub/GithubSource.swift` | workspace | payload, `SourceItem.github` case (all switches) |
| `Sources/Workspace/GitHub/GithubOAuth.swift` | workspace | device-flow state machine (injectable HTTP transport + clock for tests) |
| `Sources/Workspace/GitHub/GithubAPIClient.swift` | workspace | `GET /user`, `GET /repos/owner/repo`, `GET /repos/…/pulls` (later) |
| `Sources/Workspace/GitHub/GithubSync.swift` | workspace | fetch + `pull --ff-only` one-shot, `SyncSession` |
| `Sources/Security/GithubTokenStore.swift` | security | Keychain + `SecureBuffer` token lifecycle |
| `git-credential-solipsist` helper mode | security | `--git-credential-helper` early-exit path in `main` |
| `Sources/App/Settings/SourcesSettingsPane.swift` | settings | Add GitHub Account… sheet, scopes + sign-out rows |
| `Sources/Play/GitHub/RemoteMailboxView.swift` | play | Remote mailbox: branch, ahead/behind, last-synced, Sync verb, Open on GitHub |
| `Sources/Workspace/WorkspacePersistence.swift` | workspace | `github: [GithubSource]` array; token never persisted here |
| `Sources/Workspace/WorkspaceStore.swift` | workspace | `addGithub`, `syncGithub`, `remove` (token delete), `beginAccess` reuse |

**Untouched:** `Sources/Engine/**` (boris never talks to GitHub; the
working copy is the tree), `Sources/Compose/**`,
`Sources/Chrome/MainWindow.swift`, entitlements (`network.client`
already exists; keychain-access already granted).

## 7. Mailboxes

A GitHub source is an account header like any other. Its children:

- **Pages / Outputs / Publish / Plan / Activity** — identical to Local,
  off the working copy's graph/contracts. No new code path: the source
  resolves to a folder.
- **Remote** (new mailbox token, `Sources/Play/GitHub/`) — read-only
  sync state: branch, ahead/behind (existing porcelain), last-synced,
  **Sync** verb, and **Open on GitHub** (`NSWorkspace.open` of the
  repo URL — an Open-Recent-style convenience, not an API client).

## 8. Do not

- Reimplement git in Swift; re-derive `gitExecutableURL`; invent a
  second credential seam (reuse `SecureBuffer` / `KeychainStore`).
- Put the token in `WorkspacePersistence`, `boris.json`, plists,
  `UserDefaults`, argv, env, or logs (zero-leak invariant).
- Use `ASWebAuthenticationSession` / redirect URIs (device flow has
  none) or `https://token@…` clone URLs.
- Request `workflow` / `admin` / `delete_repo` scopes.
- Treat a GitHub source as a second engine surface — boris runs
  against the working copy, period.
- Grow `Sources/Chrome/MainWindow.swift`; touch `Sources/Engine/**`.
- Auto-add a default GitHub account or fetch a repo list without the
  user's pick.
- Build commit / push / PR / issues mailboxes (roadmap "Later").

## 9. Gate (how the lane proves it)

Manual, against the real app (`make build`):

1. Settings → **Add GitHub Account…** → device-flow sheet shows the
   code, the browser opens, the user confirms → the sheet polls to a
   token, `GET /user` names the account, the default branch is cloned
   into a user-chosen sandbox folder.
2. The source appears as an account header with the GitHub symbol;
   Pages/Outputs/Publish/Plan/Activity work off the working copy
   (45-page dogfood clone → 7 trunks, same as Local).
3. **Remote** mailbox shows branch + sync state; **Sync** pulls
   (watch suspended during the pull, resumed after — same port, same
   URL, SSE reload fires).
4. Quit and relaunch: source persists, **no re-auth**, token intact in
   Keychain.
5. Sign out: Keychain item deleted; the working copy stays on disk
   (user-owned folder; nothing removed without an explicit prompt).
6. A private repo with a PAT pasted in works through the same path.
7. `SKIP_EMBED_BORIS=1 make build` + `make test` green — **no live
   GitHub in CI**.

Automated (unit, injected transport + clock, no network):

- Device-flow state machine: code → poll → token; `slow_down` backoff;
  `expired_token` / `access_denied` surfaced; sheet cancel stops the
  poller; browser-open recorded.
- Token lifecycle: Keychain CRUD + toggle, `SecureBuffer` redaction
  (mirror `SecurityTests`), helper-mode stdout format.
- Persistence: encode/decode round trip of `GithubSource` (mirror
  `WorkspacePersistenceTests`); token absent from the payload.
- Sync: invocation shape + porcelain ahead/behind parsing against a
  stub script (`SOLIPSIST_GIT_BIN`-style seam, clone precedent).
- Source-item switches: `SourceItem.github` id/title/kind/branch
  exhaustiveness.

## 10. Edge cases

- **Polling while the user walks away:** `expires_in` (900 s) →
  surface "code expired" and re-open the sheet; never poll forever.
- **Token revoked on GitHub while the app is open:** next Sync fails
  with 401 → surface the git exit + stderr, mark the source
  `needsAuth` (non-blocking badge, B3-2 posture), offer re-auth.
- **Device flow vs. `slow_down`:** server's interval is the contract;
  honor it exactly (no faster-than-asked polling).
- **Private repo, no scope granted:** clone fails with git's
  authentication error — shown verbatim, with a hint that the token
  needs `repo` scope. Never a silent retry.
- **Working copy deleted / moved:** `beginAccess` marks unavailable
  (existing badge behavior); Settings offers Relocate (existing verb)
  and Sync re-clones on demand (`git clone` again into the same path).
- **Watch serving during Sync:** SIGSTOP before `pull`, SIGCONT after
  (§5) — the frozen-window guarantee from COORDINATOR.md §3 holds; a
  subsequent SSE reload reflects the new tree.
- **Two GitHub sources, same repo:** allowed (two working copies,
  distinct `SourceID`s); both share the single host-keyed `github`
  Keychain item — which is correct, the token is user-scoped.
  Removing one source does not touch the token (sign-out is the only
  deletion path, a later slice).
- **Client id missing (dev build):** sheet explains the operator step,
  then falls back to the PAT path — the flow is never dead.
