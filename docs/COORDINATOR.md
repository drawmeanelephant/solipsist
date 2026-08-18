# Coordinator — subprocess lifecycle state machine

**Status:** design gate for
[#58](https://github.com/drawmeanelephant/solipsist/issues/58) (card
[B3-1](cards/B3-coordinator.md)). Drafted by the dispatcher to jump-start
the coordinator lane; the lane owns this file and the implementation.
Design gates M4 (Coordinate) and M5 (Preview): every transition below
must hold **zero subprocess leaks** and honor the roadmap rule — *"One
`Process?` slot. Build lane stops watch; `validate` may run alongside
watch"* (ROADMAP §7).

## 1. What exists today

| Piece | Current behavior |
|-------|------------------|
| `BorisEngine` (actor) | One `RunHandle` = one `Process?` slot for one-shots. `run()` is **async** (`terminationHandler` + continuation) so `interrupt()` / `forceKill()` / `escalate()` stay responsive on a wedged child. One-shots never overlap (actor + one handle). `interrupt()` = SIGTERM; `forceKill()` = SIGKILL. |
| `BorisRunner.run` | stdout/stderr → temp files (no pipe deadlock). Async wait. `RunHandle.terminate()` = SIGTERM; `forceKill()` = SIGKILL; `escalate()` = SIGTERM → grace → SIGKILL. |
| `ChildProcessControl` | Shared SIGSTOP / SIGCONT / SIGKILL primitive. |
| `Coordinator` (MainActor) | `state` (`idle` / `watching` / `validating` / `building` / `terminating`) plus `isRunning` / `verb` / `summary` / `exitCode` / `problems`. Weak watch registry. Tree-writing verbs SIGSTOP watch, resume on finish. Stop / hang watchdog: SIGTERM then SIGKILL after 2s. Save-triggered validate: FSEvents on the selected content root, 300 ms debounce, coalescing, skip window. `terminateAll()` on quit. |
| `WatchServer` | Long-lived `boris watch --serve`. `suspend()` / `resume()` / `forceKill()`. `stop()` continues a frozen child before SIGTERM. |
| `PreviewSession` | Owns the `WatchServer`; registers/unregisters with the coordinator on start/stop/exit/timeout. |

**Landed (this card):** save-triggered validate + debounce, job hang
watchdog (timeouts in §5), `waitUntilExit` moved off the engine actor.

## 2. Canonical states

Five states per the issue. `validating` is shorthand for *any one-shot
non-tree-writing job* (plan, validate, check, impact — they do not
touch the trees watch owns); `building` is shorthand for *any one-shot
tree-writing job* (buildIR, buildHTML — they write the trees watch
owns). The two classes differ **only** in watch arbitration (§3).

```
                  ┌──────────────┐
        preview▶  │             ▼
        idle ────▶ watching ──▶ idle        (preview stop / exit)
          ▲            │
          │            │ job starts
          │            ▼
          │        validating ──▶ idle      (plan/validate/check/impact done)
          │            │
          │            │ build starts (watch suspended)
          │            ▼
          │        building ────▶ idle      (build done; watch resumed)
          │            │
          │            │ Stop / timeout / hang
          │            ▼
          │       terminating ──▶ idle      (SIGTERM → SIGKILL → reaped)
          └────────────┘
```

| State | Meaning | Watch | One-shot slot |
|-------|---------|-------|---------------|
| `idle` | No one-shot job, no watch. | — | free |
| `watching` | Preview `watch --serve` up (starting or serving). | running | free |
| `validating` | One-shot non-tree job in flight (plan/validate/check/impact). | **running** | busy |
| `building` | One-shot tree job in flight (buildIR/buildHTML). | **suspended** | busy |
| `terminating` | Teardown in progress (Stop, timeout, hang, quit). | stopped/suspending | draining |

Invariants (hold in every state):

1. **At most one** one-shot job in flight (the engine's `Process?` slot).
2. **At most one** watch server per app (per selected source; switching
   sources restarts, never doubles).
3. `building` ⟹ watch process suspended (`SIGSTOP`); the moment
   `building` ends, watch is resumed (`SIGCONT`) or confirmed gone.
4. Every launched PID is reaped: SIGTERM → 2 s grace → SIGKILL → wait.
   No orphaned `boris` processes, on any exit path (job end, Stop,
   timeout, hang, app quit).
5. Cancel is detected as `terminationReason == .uncaughtSignal`
   (AGENTS.md boundary 5). A deliberate SIGTERM that exits 0 (watch,
   A12) is *not* a failure.

## 3. Watch vs build arbitration

**Rule:** `validating`-class jobs run alongside watch (roadmap allows
it — validate never writes the trees watch owns). `building`-class
jobs require watch suspended.

Mechanism — **SIGSTOP / SIGCONT**, not stop-and-restart:

- `WatchServer.suspend()` → `kill(processIdentifier, SIGSTOP)`.
  The process freezes in place: port stays bound, helper URL stays
  valid, the web view keeps its `…/__boris/` URL. No rebuild race
  while frozen.
- `WatchServer.resume()` → `kill(processIdentifier, SIGCONT)`.
  Watch continues from where it froze; at most one refresh build may
  follow (Boris watcher semantics), surfaced by the existing SSE
  reload. Accepted.
- Rejected alternative: SIGTERM + fresh `WatchServer` — the ephemeral
  port (`--port 0`) changes, breaking the preview URL and forcing the
  web view to rebind. Not acceptable for a live workflow.

Registry — **the coordinator must see watch.** Today `PreviewSession`
owns the server privately. Add a weak registration:

- `PreviewSession.start` → `coordinator.registerWatch(server)`
- `PreviewSession.stop` / `onExit` / `failTimeout` →
  `coordinator.unregisterWatch()`
- `Coordinator.activeWatch: WatchServer?` (weak; MainActor both sides).

Build flow: `idle|watching → building` — if `activeWatch` is running,
`suspend()`; run the job; on finish, `resume()` if it is still alive
(else unregister). If watch exits spontaneously mid-build (A13-class),
resume is a no-op and the exit handler unregisters — the build is
never blocked on watch.

## 4. Save-triggered validate (debounce)

A per-selected-source FSEvents watcher on the content root is owned
by the coordinator; every change → `coordinator.noteSave()`.

- **Debounce:** 300 ms from the *last* save before a validate may
  start (rapid typing coalesces into one run). Constant
  `saveDebounceInterval = 300 ms` in one place.
- **Coalescing:** a save-triggered validate is a *pending flag*, not a
  queue entry. New saves re-arm the timer; one run per burst.
- **While a manual job runs:** set `validateQueued = true`; run when
  the coordinator returns to `idle|watching`, but only if the last
  save is still fresh (≤ 2 s) — otherwise drop; the next save re-arms.
- **Manual verb arrives while a save-validate is pending:** cancel the
  pending validate (drop the flag + timer); the manual verb wins.
- **Skip window:** after a completed *manual* validate, suppress
  save-triggered validates for 2 s (the user just validated).
- **In `terminating`:** never start; drop pending.
- Save-triggered validate runs in `validating` state → coexists with
  watch (§3). Never while `building`.

Manual verbs are **never** queued (menu is disabled while a job runs —
current behavior, kept). Save-triggered validate is the only
background item, and it yields to everything manual.

## 5. Cancellation, timeout, hang

| Event | Action | Escalation |
|-------|--------|------------|
| Stop (⌘.) | Cancel task; SIGTERM the in-flight one-shot (`engine.interrupt()`); SIGTERM watch if `watching`. | 2 s grace → SIGKILL each still-running PID → wait. |
| Job hang (no exit) | Watchdog fires at the per-job timeout. | SIGTERM → 2 s grace → SIGKILL → wait. |
| App quit | `terminateAll()` on termination: drain one-shot + watch as above. | Same. |

- **Timeouts (constants, one place):** plan/validate/check/impact
  60 s; buildIR/buildHTML 300 s; **watch: no timeout** (long-lived;
  only Stop tears it down). Watch port-line failure keeps the existing
  15 s `PreviewSession` guard.
- **SIGKILL primitive:** `RunHandle.forceKill()` (Darwin `kill(pid,
  SIGKILL)`); the runner must expose the pid and a reaped confirmation
  (via `terminationHandler` / wait after SIGKILL).
- **Hang must not freeze the app or the engine slot:** today
  `BorisRunner.run` blocks the actor on `waitUntilExit()`. The lane
  must move one-shot completion off the actor — either an async
  `run` backed by `terminationHandler` + continuation, or a worker
  thread with a separate watchdog thread that can escalate. The actor
  must stay responsive so Stop always works, even on a wedged child.
- After teardown, state returns to `idle` with the exit code /
  `"cancelled"` / timeout reason surfaced in `summary` + problems
  (never swallow an exit code — D11).

## 6. Required primitives (implementation deltas)

1. `CoordinatorState` enum (`idle`, `watching`, `validating`,
   `building`, `terminating`) + `state` on `Coordinator`
   (supplements `isRunning`/`verb`; status bar + menus read it).
2. `WatchServer.suspend()` / `resume()` / `isSuspended` (SIGSTOP /
   SIGCONT) — process must be running; no-op otherwise.
3. `RunHandle.forceKill()` + pid exposure; async completion for
   one-shots (§5).
4. `Coordinator.registerWatch` / `unregisterWatch` (weak registry).
5. Save watcher + debounce timer + `validateQueued` (§4).
6. Job watchdog tasks per timeout (§5) and `terminateAll()` for quit.
7. `Commands.swift` enable/disable by state: verbs enabled when
   `idle`/`watching`; Stop enabled when `state != idle` (covers
   watching); while `terminating` everything disabled. *Menus first —
   Commands.swift stays the source of truth.*
8. D2: debounce interval and timeouts are **machine state** → app
   plist / UserDefaults. Never `boris.json`.

## 7. Edge cases

- Watch exits spontaneously (`GraphValidationFailed` class): exit
  handler unregisters; coordinator goes `idle` (or stays in its job
  state) — never wedged.
- Watch dies mid-build: `resume()` no-ops; build completes; state
  returns to `idle` (no watch to restore — the preview window shows
  its failed state, existing UX).
- Source switched while a job runs: job finishes against the source it
  started on (snapshot the source in the job, as `Coordinator.perform`
  does today); watch restarts per new source id (`task(id:)`).
- Rapid save storm during a build: `validateQueued` set once; runs
  after the build, then drops if stale (§4).
- Two sources / two preview windows: one selected source at a time —
  one watch server. The registry asserts this; a second registration
  replaces the first (stop + unregister old).
- SIGSTOP leaves the process mid-write if frozen mid-build: resume is
  atomic from Boris's perspective (it sees a consistent tree on the
  next pass); accepted, same posture as a paused editor.

## 8. Gate (how the lane proves it)

Manual, against the real app (`make build`, `SOLIPSIST_BORIS_BIN` set):

1. Open a source → Preview ▶ → state `watching`, preview loads.
2. Run Build HTML with preview open: watch PID shows `T` state
   (`ps -o stat`), build completes, watch returns to `R`/`S`, same
   port, SSE reload fires.
3. Validate with preview open: both processes alive concurrently
   (`validating` + watch running).
4. Edit a file repeatedly (save storm): exactly one validate ~300 ms
   after the last save; problems update once.
5. Stop (⌘.) during a hung job (stub `SOLIPSIST_BORIS_BIN` that
   ignores SIGTERM): SIGKILL lands ≤ ~2 s; `pgrep -P <app>` shows zero
   `boris` children after.
6. Quit mid-build: no orphaned `boris` processes on the system.

Automated (unit):

- State-transition tests on `CoordinatorState` with an injected fake
  runner (script stub as `SOLIPSIST_BORIS_BIN`): every transition in
  §2; timeout escalation; debounce coalescing with an injected clock.
- `WatchServer` suspend/resume test against the stub: `isSuspended`
  toggles; resume after suspend restores a working process.

**Do not touch:** `Sources/Workspace/**` + `SourceSidebar.swift`
([B3-2](cards/B3-workspace.md)), `scripts/embed-boris.sh` /
`Project.yml` / entitlements / workflows ([B3-4](cards/B3-ship.md)).
`Sources/Engine/**` is single-owner under this card — B3-3's stdin
secret-writer builds on a seam and merges after this lands.
