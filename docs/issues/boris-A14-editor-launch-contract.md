# A14 — Pin the `boris-editor` subprocess launch contract

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: S. Mostly docs + a test pin; one small behavior add
> (SIGTERM/SIGINT) matching watch.
> **Fact-checked against afterparty `editor/src/{main,server}.zig`.** The
> host already prints a machine-shaped launch line. This issue makes that
> line a contract and gives the process the same graceful shutdown watch
> already has.

---

**Title:** Document and pin the `boris-editor` launch line; exit 0 on SIGTERM/SIGINT

## Summary

`boris-editor` is already a well-behaved loopback host: ephemeral port,
random session token, token + `Host` + `Origin` checks, CSP that frames
only its own preview port. Embedders (a native WKWebView, a test harness,
another desktop shell) spawn it as a subprocess and need two things the
compiler already believes in:

1. A **specified** way to discover the session URL.
2. A **safe** way to stop the process.

Today both exist only as implementation details.

## Verified behavior (afterparty, `editor/src`)

On listen, `editor/src/server.zig` prints exactly:

```
BORIS_EDITOR_URL=http://127.0.0.1:<port>/#token=<32 hex chars>
```

Flags (from `editor/src/main.zig`): `[DIR] [--boris PATH] [--ui-dir DIR] [--port PORT]`. Default port is `0` (ephemeral). Loopback only (`127.0.0.1`). Every API request requires the token (fragment or `x-boris-editor-token`) and a loopback `Host`; a supplied `Origin` must match the session origin.

There are **no signal handlers**. The accept loop is `while (true)`. SIGTERM/SIGINT is an uncaught signal — the same class of shutdown watch already documents and handles (`watch-mode.md` §6 → exit 0, cleanup). An embedder that tears down a window currently has to SIGKILL or live with a non-zero `terminationReason == .uncaughtSignal`.

## Proposal

1. **Document the launch line as a contract** in `editor/README.md` (and a
   short subsection under `docs/contracts/` if that is the house style):
   - one line, stderr, `BORIS_EDITOR_URL=` prefix, URL shape above;
   - `--port 0` is the embedder default; the printed port is the bound one;
   - token stays in the URL fragment (not a query string — fragments are
     not sent to the server on navigation; the host already accepts the
     `x-boris-editor-token` header for API calls);
   - `--boris` / `--ui-dir` / project `DIR` meanings as they are today;
   - security posture is **not** relaxed: loopback, token, Host, Origin, CSP
     stay as implemented.
2. **Pin the line** with a host test (the existing `editor/scripts/test-host.sh`
   already boots the binary — assert the first matching line parses).
3. **Catch SIGINT/SIGTERM** the way `watch` does: stop accepting, close the
   listener, exit 0. No new flags. No drain of in-flight HTTP is required
   beyond what a single-request accept loop already implies.

## Why this is a strong decision for boris

The editor already chose a KEY=value launch line instead of prose. That is
the compiler's instinct; this issue just writes it down and stops the
process the same way the watch daemon already stops. Embedders stop
regex-hoping the print stays put. Authors using the editor in a browser
lose nothing. Token/CSP/Origin do not change — this is not a hole, it is a
pin.

## Non-goals

- No `--watch-json` / NDJSON on the editor. The launch line is enough.
- No change to CSP, Origin matching, token entropy, or the file API.
- No requirement that the agent-pack ship `boris-editor` (separate
  packaging question; the host builds from `editor/build.zig`).
- No WKWebView-specific behavior. The contract is process + URL.

## Acceptance criteria

- [ ] `editor/README.md` (or `docs/contracts/`) specifies the
      `BORIS_EDITOR_URL=` line, flag set, and loopback/token/Host/Origin
      rules as they exist.
- [ ] A host test fails if the launch line is missing or unparsable.
- [ ] SIGINT and SIGTERM exit 0 after the listener closes; an embedder
      can treat `terminationReason == .uncaughtSignal` as cancel, not a
      crash, the same way it already does for `boris watch`.
