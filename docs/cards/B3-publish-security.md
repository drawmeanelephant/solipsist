# Card B3-3 — Publish credentials (Keychain + stdin)

**Milestone:** M8 (Publish) · **Issue:**
[#60](https://github.com/drawmeanelephant/solipsist/issues/60) ·
**Lane:** publish-security · **Owner:** uncle-gravity. One worktree,
one PR against `main`; branch suggestion `ship/publish-security`. Runs
parallel with [B3-4](B3-ship.md).

## Owns

- New `Sources/Security/` module — `KeychainStore`
  (`kSecClassGenericPassword`, per-target "Remember in Keychain"
  toggle), ephemeral session state, zeroing `Data` / `[UInt8]` buffers
  after the stdin write
- `Tests/` — unit tests proving secrets reach the stdin pipe and are
  zeroed, never persisted in app state or plaintext storage
- The credential-lifecycle design spec (the issue's gate)

## Do

1. Keychain integration with an optional per-target remember toggle.
2. Ephemeral session mode — memory-only secrets wiped immediately
   after publication.
3. Zero byte buffers after writing to the child process `stdin` pipe.

## Do not

- Touch `Sources/Engine/**` or `Sources/App/Coordinator.swift`
  ([B3-1](B3-coordinator.md)). Build the stdin secret-writer on a
  `SecretProviding` seam in your own module; wiring it into
  `BorisEngine` merges after B3-1 lands.
- Touch build files / entitlements / workflows
  ([B3-4](B3-ship.md), same owner — keep the two PRs separate).

## Gate

Design spec + test case verifying secrets are written to `stdin`
without persisting in application state or plaintext storage.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
