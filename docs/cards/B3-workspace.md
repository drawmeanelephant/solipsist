# Card B3-2 — Workspace bookmark persistence

**Milestones:** M2 (Chassis) + M9 (Ship) · **Issue:**
[#59](https://github.com/drawmeanelephant/solipsist/issues/59) ·
**Lane:** workspace. One worktree, one PR against `main`; branch
suggestion `workspace/bookmark-persistence`.

## Owns

- `Sources/Workspace/**` (`WorkspaceStore.swift`,
  `Local/LocalSource.swift`, `Source.swift`, `WorkspaceSelection.swift`)
- `Sources/Chrome/SourceSidebar.swift` — the stale-source badge
- App-level persistence: `Sources/App/SolipsistApp.swift` (+
  `AppRuntime.swift` as needed) — Open Recent / window restoration
- Unit tests for the persistence round-trip + stale resolution

## Do

1. Persist security-scoped bookmark `Data` per source (UserDefaults);
   resolve + `startAccessingSecurityScopedResource()` on relaunch.
2. Stale / moved / deleted directory recovery: non-blocking sidebar
   badge ("Unreachable — Relocate / Remove"), no crash, no frozen UI.
3. Native Open Recent integration.

## Do not

- Touch `Sources/App/Coordinator.swift` or `Sources/Engine/**`
  ([B3-1](B3-coordinator.md)).
- Restructure `MainWindow.swift`; the badge lives in
  `SourceSidebar.swift`.
- Edit `scripts/embed-boris.sh`, `Project.yml`, or
  `Solipsist/Solipsist.entitlements` ([B3-4](B3-ship.md)) — if the
  sandbox blocks `startAccessingSecurityScopedResource`, file the
  finding on #61 instead.

## Gate

Add source folder → restart app → source remains loaded and
accessible; deleted folder → non-blocking stale warning.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
