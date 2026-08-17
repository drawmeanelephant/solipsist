# Parallel — contract fixture tests

**Owns:** `Tests/Fixtures/`, `Tests/ContractTests/`, and **only** the
new test target stanza in `Project.yml`.
**Do not touch:** `Sources/Models/` shapes. Decode the types that
already exist.

## Why

CI cannot run `boris`. We can still refuse to break Codable mirrors
by checking in real JSON.

## Do

1. Add a `ContractTests` macOS unit-test target in `Project.yml`
   (Swift 6, same deployment). Sources: `Tests/ContractTests` +
   `Sources/Models` only.
2. Check in small fixtures under `Tests/Fixtures/`:
   - IR `build-report.json` (ok true and ok false)
   - `manifest.json` (few pages)
   - `graph.json` (few nodes/edges)
   - `html-build-report-0.1.0` if the type exists on `main`; skip if not
   - `completion.json` if `Completion` exists on `main`; skip if not
3. Harvest fixtures from a **local** kit run if you have
   `SUPPORT-NOT-FOR-GITHUB/`; otherwise hand-minify samples that match
   `docs/ENGINE-CONTRACTS.md` and the existing structs. No invented
   fields.
4. Tests: decode succeeds; `ok` / counts / first diagnostic code
   asserted. Unknown extra JSON keys must not crash (keep using
   Codable as-is).
5. Add `make test` → `xcodebuild test -scheme ContractTests` (or the
   generated scheme). Add a CI job `fixtures` that runs `make test`.
   Do not remove `spike` / `app`.

## Gate

`make test` passes without a boris binary. `make spike` still
compiles. No diff under `Sources/Engine`, `Play`, `Inspector`.
