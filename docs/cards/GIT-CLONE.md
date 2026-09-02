# Card — Add Git Repository… (clone into a Local source)

**Milestone:** M12 · **Issue:**
[#131](https://github.com/drawmeanelephant/solipsist/issues/131)
**Lane:** Settings / workspace. One worktree, one PR against `main`;
branch suggestion `feat/git-clone-source`.

This is the first git slice. It is **not** GitHub OAuth and it is
**not** a new `SourceKind` payload. A clone is a folder. We already
know how to add a folder.

## Owns

- `Sources/App/Settings/SourcesSettingsPane.swift` — **Add Git
  Repository…**
- File menu clone verb in `Sources/App/Commands.swift` (menus first)
- A small git helper (new file under `Sources/Workspace/Git/` or
  next to `LocalSource`) that runs `/usr/bin/git` as a `Process`
- Settings / sidebar **detail** when the workspace root is a git
  checkout (branch; dirty optional)
- Tests for URL / dest validation and for parsing `git status`
  porcelain — no network in CI

## Do not touch

- `Sources/Engine/**` (this is not boris)
- `Sources/Play/**` except a caption if the account header already
  shows `detailLine`
- Fake `SourceKind.github` rows
- Commit / push / pull / fetch UI
- GitHub app passwords, OAuth, or `gh`

## Why

Settings is the account book. People who do not live in this repo
will want to add a remote publication the way they add a local
folder. `git clone` into a user-chosen directory, then the existing
`WorkspaceStore.addLocal` bookmark, is that verb. GitHub-as-its-own
source kind stays a follow-on.

## Do

1. **Add Git Repository…** (Settings + File menu). Prompt for a
   clone URL and a destination folder (`NSOpenPanel` can-create).
   Reject empty URL, `file://`, and non-`git`/`https`/`ssh`/`git@`
   shapes. Do not invent a browser OAuth sheet.
2. Run `/usr/bin/git clone -- <url> <dest>` with the destination
   already in the sandbox (user-selected). Surface stdout/stderr and
   a non-zero exit. Do not swallow. Cancel = SIGTERM on that
   process (not the engine slot — this is a one-shot next to
   Settings, not `BorisEngine`).
3. On exit 0, `store.addLocal(url: dest)`. Same store as Open….
4. If `workspaceRoot/.git` exists, Settings row (and sidebar
   tooltip / detail if it already shows a second line) shows
   `branch` from `git rev-parse --abbrev-ref HEAD` or
   `status --porcelain=v2 --branch`. Missing git or not-a-repo →
   no badge, not an error.
5. Entitlements: `network.client` already exists for clone.
   Do not add a new entitlement unless sandbox blocks `/usr/bin/git`
   — if it does, file the finding on the issue, do not guess.

## Do not

- Reimplement git in Swift.
- Clone into `SUPPORT-NOT-FOR-GITHUB/` or any kit path.
- Auto-open a default GitHub account.
- Walk `content/` as Finder.
- Expand the Apple-account ship posture (#110 / #111, now closed).

## Gate

Settings → Add Git Repository… a public `https://` URL into a new
folder → it appears as a Local source and the sidebar can open it.
A Local source that is already a checkout shows its branch in
Settings. Failed clone shows the git exit / stderr. `SKIP_EMBED_BORIS=1
make build` + `make test` green (no live clone in CI).
