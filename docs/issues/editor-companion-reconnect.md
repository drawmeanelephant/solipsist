# Editor: Auto-Reconnect When boris-editor Crashes

**Track:** Editor companion / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#232](https://github.com/drawmeanelephant/solipsist/issues/232)
**Lane:** `Sources/Companions/Editor/`

## Problem

When the `boris-editor` host process crashes, the Editor companion shows a
static error and the user must click "Restart Host". A companion window
should feel integrated: a transient crash should auto-restart.

## Verified current state

`EditorSession` (`Sources/Companions/Editor/EditorSession.swift`):
`handleExit(_:)` sets `phase = .idle` on exit 0 and
`phase = .failed("Editor host exited (N)…")` on non-zero. `stop()` clears the
`onConnect`/`onExit` callbacks and stops the server, so **`handleExit` only
fires on spontaneous exit** — the "not user-initiated" distinction is already
guaranteed by the current code; keep it that way. `restart()` reuses
`lastContentRoot` / `lastProjectRoot` / `lastEngine`. `EditorWindow`'s
`.onDisappear` calls `session.stop()`.

## Scope

### Must land

- On a **spontaneous non-zero exit**, automatically restart after a short
  delay, with **exponential backoff** (2s, 4s, 6s).
- Show a **transient status** ("Editor host restarted") on success instead of
  a static error.
- Cap at **3 attempts within 30s**; past that, show the error state and
  require manual restart.
- **Reset the attempt counter on a successful connect** (`handleConnect`).
- Must **not** fire on:
  - exit code 0 (clean shutdown);
  - window close (`.onDisappear` → `stop()`, which clears callbacks — keep);
  - a manual "Restart Host" / "Stop" (they go through `stop()`/`restart()`,
    which clear callbacks — keep);
  - a host that fails to **start** (that is a config error, not a crash — the
    failed phase comes from `start()` directly, not `handleExit`).

### Nice-to-have (not gate)

- A countdown ("Reconnecting in 2s…") in the status bar before each retry.
- A `UNUserNotificationCenter` notification when auto-reconnect exhausts and
  manual action is needed.
- A "Don't Auto-Reconnect" toggle in the toolbar.

### Must not land

- Auto-reconnect on clean exit, window close, or start failure (above).
- Auto-reconnect when the engine or editor binary is missing (permanent
  errors — `start()` already fails them before a server exists).

## Implementation sketch

1. In `EditorSession`, add state:
   ```swift
   private var autoReconnectAttempts = 0
   private var autoReconnectTask: Task<Void, Never>?
   ```
2. In `handleExit(_:)` (the non-zero branch only), schedule a reconnect:
   ```swift
   autoReconnectAttempts += 1
   if autoReconnectAttempts <= 3 {
       let delay = Double(autoReconnectAttempts) * 2 // 2, 4, 6
       autoReconnectTask = Task { [weak self] in
           try? await Task.sleep(for: .seconds(delay))
           guard !Task.isCancelled else { return }
           self?.restart()   // reuses lastContentRoot / projectRoot / engine
       }
   } else {
       phase = .failed("Editor host crashed 3 times. Manual restart required.")
   }
   ```
3. Reset `autoReconnectAttempts = 0` in `handleConnect(_:)`.
4. **Cancel the pending task in `stop()`** (and in `start()`'s early-return /
   `fail()` paths). A `restart()` calls `stop()` first, so a manual restart
   cancels any pending auto-reconnect — correct.
5. **Source switch is already safe**: `EditorWindow`'s `.task(id: source.id)`
   re-runs `startEditor` → `session.start(...)`, and `start()` calls `stop()`
   when the root differs, cancelling the pending task. Verify, do not regress.

## Gate

While connected, kill the `boris-editor` process → the window shows a
transient "restarting" state and reconnects automatically (2s) → kill it three
times within 30s → the error state requires manual restart → a manual Restart
Host works and resets the counter → closing the window never triggers a
reconnect. `SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testAutoReconnectFiresOnNonZeroExit` — a non-zero exit schedules a
  restart.
- `testAutoReconnectDoesNotFireOnCleanExit` — exit 0 does not.
- `testAutoReconnectStopsAfterMaxAttempts` — 3 failures → manual state.
- `testAutoReconnectResetsOnSuccess` — a connect resets the counter.
- `testAutoReconnectDoesNotFireOnWindowClose` — `stop()` cancels the task.

## Edge cases

- The 2s delay prevents a new host from starting while the old one is still
  shutting down.
- Engine / editor binary missing → permanent failed phase, no reconnect.
- Source switch while a reconnect is pending → the pending task is cancelled
  and the new source's session starts fresh.
