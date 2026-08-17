# Q20 — Companion URL parser tests

**Owns:** `Tests/` (new `CompanionTests` target or extend `ContractTests`
sources), plus read-only extraction if needed.

`EditorURL.parse` in `Sources/Companions/Editor/EditorWindow.swift` and the
loopback validator in `Sources/Companions/Preview/PreviewWindow.swift` are
pure logic with zero unit coverage today. Cover them:

- `BORIS_EDITOR_URL=` prefix strip, raw URL, whitespace trim
- Loopback enforcement: `127.0.0.1` / `localhost` / `::1` accepted;
  anything else rejected with `.notLoopback`
- `#token=<hex>` fragment required; non-hex rejected with `.invalidTokenHex`
- Empty input → `.empty`; garbage URL → `.invalidURL`
- Preview URL: loopback-only, same host rules, non-loopback rejected inline

If the parsers live inside `View` structs, extract them into a testable
location first (e.g. `Sources/Companions/Editor/EditorURL.swift`) — that
file is in-lane. Do not change parser behavior, only expose it.

Gate: `make test` — new tests pass; no behavior change.
