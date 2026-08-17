# Card B3-4 — Ship: universal binary, sandbox, notarization

**Milestone:** M9 (Ship) · **Issue:**
[#61](https://github.com/drawmeanelephant/solipsist/issues/61) ·
**Lane:** ship/build · **Owner:** uncle-gravity. One worktree, one PR
against `main`; branch suggestion `ship/m9-hardening`.

## Owns

- `scripts/embed-boris.sh` — universal binary embedding (lipo arm64 +
  x86_64 into `Contents/Resources/boris`), codesign identity for the
  embedded `boris` matching the host app
- `Project.yml` + `Solipsist/Solipsist.entitlements` — App Sandbox
  matrix
- New `.github/workflows/release-notarize.yml` — build →
  `xcrun notarytool submit --wait` → `stapler staple`, credentials via
  CI secrets
- Ship plan doc under `docs/` (clean-Mac proof checklist)

## Do

1. Universal Mach-O fat binary via `scripts/embed-boris.sh`; sign the
   embedded engine.
2. Entitlements matrix: `app-sandbox`,
   `files.user-selected.read-write`, `network.client` — and keep
   `network.server` (M5 preview depends on it).
3. Automated notarization + stapling in CI.
4. Clean-Mac proof: no Zig, no kit folder, bundled engine only.

## Do not

- Touch `Sources/**` or `Tests/**` — build lane stays build-only; if a
  Swift-side change is needed to prove the gate, file it on the issue
  instead.
- Drop `files.user-selected.read-write` (breaks
  [B3-2](B3-workspace.md)) or `network.server` (breaks M5 preview).
- Break the embed search-order contract (`SOLIPSIST_BORIS_BIN`,
  `SKIP_EMBED_BORIS=1 make build`).

## Gate

Universal `Solipsist.app` runs, spawns `boris`, compiles a publication,
passes `spctl --assess -vvv --type exec` on a fresh macOS machine.
Local: `SKIP_EMBED_BORIS=1 make build` + `make test` green.
