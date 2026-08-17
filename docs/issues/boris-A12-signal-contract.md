# A12 — Signal/cancellation contract for watch mode (moot — superseded by afterparty)

> **⛔ Moot / withdrawn.** afterparty's `docs/contracts/watch-mode.md` §6
> already documents graceful SIGINT/SIGTERM shutdown, finish-rebuild-before-
> shutdown, and staged-publish atomicity, and C06 pins the failure/exit
> classes. The only residual (a shutdown-latch unit test) is nice-to-have,
> not a blocker; the draft below is retained as evidence only.

---

**Title:** Specify signal handling in watch mode: graceful SIGTERM/SIGINT, SIGKILL atomicity

## Summary

Any tool that spawns a long-running compiler process — an editor, a CI
wrapper, a dev-server, a GUI — has one question that matters about shutdown:
*"can I kill it, and what state does it leave behind?"* Boris's watch mode
already answers it well. Verified empirically on afterparty:

| Signal | Verified behavior |
|--------|-------------------|
| `SIGTERM` | Graceful: exit **0**, prints `watch: received shutdown signal, cleaning resources...`, within one idle poll (≤500ms) |
| `SIGINT` | Same graceful path (SIGINT/SIGTERM share a handler) |
| During a rebuild | The shutdown latch is checked between loop iterations, so an in-flight rebuild **completes before shutdown** — a cancelled build never publishes a partial tree |
| `SIGKILL` | Nothing can handle it — but the staged publish + atomic cache manifest mean **no `.boris-stage` leftovers** and the last-good manifest stays intact; the next build recovers cleanly |

The C06 conformance work already pins watch exit classes and failure
recovery. What it does not yet do is pin the *signal* path. The behavior is
discoverable only by experiment — and an experiment that signals mid-rebuild
(or signals the wrong process) produces scary-looking but wrong results,
which is exactly what pushes consumers to build process-killing workarounds
that *do* leave partial state. A compiler that promises atomic publication
should also promise what happens when it's killed.

## Proposal

1. **Document** a short "Signals" section in
   `docs/contracts/watch-mode.md`:
   - SIGINT/SIGTERM during watch ⇒ graceful shutdown, exit 0, resources
     cleaned; the latch is checked between loop iterations, so an in-flight
     rebuild finishes first (no partial publish).
   - SIGKILL may leave transient state, but publication is staged and
     atomic — output trees and the cache manifest are never half-written;
     the next build reconciles.
   - Consumers distinguish *cancelled* via the OS signal-termination status
     (e.g. Swift `Process.terminationReason == .uncaughtSignal`), not via a
     Boris exit code — watch exits 0 on graceful signal shutdown.
   - One-shot runs have no signal handlers — default dispositions apply,
     and the same staged-publish atomicity holds.
2. **Pin the shutdown latch with a test.** The repo already has a
   `FakeWatcher` harness and deterministic coordinator tests. Add one that
   flips the shutdown latch mid-cycle and asserts: the in-flight rebuild
   completes, the pending set is not lost, and the coordinator returns
   without error. A documented contract that tests don't enforce is a
   comment; this converts it into a promise.

## Why this is a strong decision for boris

Graceful shutdown + kill-atomicity is a real, already-implemented property
that completes the process ABI story: spawn it, feed it, and *stop it*
safely. Documenting it removes the single largest source of distrust a
consumer has toward a long-running subprocess, and the test makes the
property permanent rather than incidental. Zero behavior change, two small
deltas (doc + test) on top of the C06 work already in place.

## Acceptance criteria

- [ ] `docs/contracts/watch-mode.md` documents the signal table above, the
      "rebuild completes before shutdown" rule, and the SIGKILL atomicity
      guarantee.
- [ ] A unit test (FakeWatcher-driven) asserts shutdown-latch semantics:
      in-flight rebuild completes, then the coordinator exits cleanly.
