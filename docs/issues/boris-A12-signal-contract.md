# A12 — Document signal/cancellation behavior (the "can I kill Boris?" contract)

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Documentation only.

---

**Title:** Docs: specify signal handling in watch mode (SIGTERM/SIGINT graceful shutdown, SIGKILL safety)

## Summary

A consumer driving `boris --watch` as a subprocess (a GUI) needs a
deterministic answer to *"can I kill it, and what state does it leave
behind?"* The current behavior is good — verified empirically — but it is
entirely undocumented:

| Signal | Verified behavior |
|--------|-------------------|
| `SIGTERM` | Graceful: exit **0**, prints `watch: received shutdown signal, cleaning resources...`, within one idle poll (≤500ms) |
| `SIGINT` | Same graceful path (SIGINT/SIGTERM share a handler) |
| During a rebuild | The shutdown latch is checked between loop iterations, so an in-flight rebuild **completes before shutdown** — a cancelled build never publishes a partial tree |
| `SIGKILL` | Nothing can handle it — but the staged publish + atomic `.boris-cache/manifest.json` mean **no `.boris-stage` leftovers** and the last-good manifest stays intact; the next build recovers cleanly |

## Proposal

Add a short "Signals" section to `docs/contracts/watch-mode.md` (or
`diagnostics.md`) stating:

1. SIGINT/SIGTERM during watch ⇒ graceful shutdown, exit 0, resources
   cleaned; the latch is checked between loop iterations, so an in-flight
   rebuild finishes first (no partial publish).
2. SIGKILL may leave transient state, but publication is staged and
   atomic — output trees and the cache manifest are never half-written;
   the next build reconciles.
3. The exit code on signal-driven shutdown is 0 (consumers distinguish
   *cancelled* via the OS signal-termination status, e.g. Swift
   `Process.terminationReason == .uncaughtSignal`, not via a Boris exit
   code).
4. One-shot (non-watch) runs have no signal handlers — default dispositions
   apply, and the same staged-publish atomicity holds.

## Why this is not a compromise

Documentation only. The behavior already exists and is sound; the ask is to
make it a contract so GUI consumers don't have to discover it empirically
(or, worse, assume it isn't there and build process-killing workarounds).

## Acceptance criteria

- [ ] `docs/contracts/watch-mode.md` (or `diagnostics.md`) documents the
      signal table above, the "rebuild completes before shutdown" rule, and
      the SIGKILL atomicity guarantee.
