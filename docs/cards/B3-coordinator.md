# Card B3-1 — Coordinator state machine

**Milestones:** M4 (Coordinate) + M5 (Preview) · **Issue:**
[#58](https://github.com/drawmeanelephant/solipsist/issues/58) ·
**Lane:** coordinator (grind). One worktree, one PR against `main`;
branch suggestion `coord/m4-state-machine`.

## Owns

- `Sources/App/Coordinator.swift` — verb orchestration (Plan /
  Validate / Build / Check / Impact / Stop)
- `Sources/Engine/**` (`BorisEngine.swift`, `BorisRunner.swift`,
  `WatchServer.swift`, `BorisBinary.swift`) — the one `Process?` slot,
  SIGTERM → SIGKILL teardown, zero orphaned children
- `Sources/Chrome/MainWindow.swift` — only the verb/watch wiring this
  card needs

## Do

1. Design the coordinator state machine: `idle`, `watching`,
   `validating`, `building`, `terminating` — transitions with **zero
   subprocess leak** (the issue's gate).
2. Cover the live overlaps: save-triggered `validate` debounce
   (~300 ms) racing an explicit build; `watch --serve` running while
   Build executes (roadmap M4 gate: "Watch is paused for the build
   lane"); hang/timeout recovery.
3. Land the design doc with the implementation in `Coordinator` /
   `Engine`.

## Do not

- Touch `Sources/Workspace/**` or `Sources/Chrome/SourceSidebar.swift`
  ([B3-2](B3-workspace.md)).
- Touch `scripts/embed-boris.sh`, `Project.yml`,
  `Solipsist/Solipsist.entitlements`, `.github/workflows/*`
  ([B3-4](B3-ship.md)).
- Let [B3-3](B3-publish-security.md) touch `Sources/Engine/**` while
  you own the subprocess boundary — its stdin wiring merges after this
  card.

## Gate

State-machine spec covering coordinator transitions with zero
subprocess leak. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
