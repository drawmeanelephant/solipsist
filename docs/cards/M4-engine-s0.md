# Card M4 — Engine S0 (contracts + verbs)

**Milestone:** M4 (engine half; UI verbs come after)
**Lane:** `Sources/Engine/`, `Sources/Models/`, `Spike/`
**Do not touch:** any SwiftUI (`App/`, `Chrome/`, `Play/`, `Inspector/`,
`Companions/`).

## Why

The coordinator is discrete `boris` invocations. The actor does not yet
speak `plan`, `validate`, `--report`, or `--timings`. Completion and
the publication profile are not modeled. Inspector and later UI need
those mirrors more than they need new chrome.

## Do

Additive methods on `BorisEngine` (one `Process` slot, same runner):

| Method | Invocation | Consume |
|--------|------------|---------|
| `version()` | `boris --version` | stdout line, e.g. `boris/0.8.1` |
| `plan(profileURL:)` | `boris plan --profile PATH` | stdout JSON (declaration). cwd = project |
| `validate(contentRoot:reportURL:)` | `boris validate --input … --report PATH` | `html-build-report-0.1.0` file |
| `timings` on an existing build | `--timings` | stdout `boris-timings` JSON (optional decode) |

Also decode, on successful `buildIR`, `completion.json` into a new
`Completion` type. Add `PublicationProfile` (schema v1) and
`HTMLBuildReport` (`html-build-report-0.1.0`). D8: unknown
`schemaVersion` / `schema_version` must not crash — optional fields,
degrade.

Grow `Spike/main.swift` to call `version`, `plan` (if a profile
exists), `validate --report`, and one `--report` HTML or validate
path. Keep the existing IR + check + impact probes.

Use the kit binary. Content:
`/Users/tbuddy/dev/drawmeanelephant/boris/main/content`. Afterparty
`boris init` writes `boris.json` — if the dogfood tree has no profile,
`plan` may exit 2; surface that, do not fake a profile.

## Do not

- Parse stderr except you will not need to (no watch on this card).
- Rewrite `BorisRunner`.
- Unify `compiler` / `compiler_id` / `compilerId` — accept all three.
- Touch SwiftUI so play/inspector sessions do not conflict.

## Facts

- Streams: human prose on stderr; stdout is `--version`, `--timings`,
  `plan` (and publication verbs). Machine files via `--report`.
- `validate` is artifact-free and may run while watch is idle (later).
- Containment: output *trees* stay under cwd; `--report` single files
  may be absolute. IR `--out` must be a relative path.
- HTML build-report has **no** `pageCount`; it has `compilerId`, `ok`,
  `errorCount`, `diagnostics` (nullables on location fields).
- `completion.json`: `format: boris-completion-index`,
  `schema_version` is an **integer** `1` (not the IR string).
- Pin is still `b82e9e2`. A3’s `compiler` on IR report may be absent
  until we bump.

## Gate

```
SOLIPSIST_BORIS_BIN=SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris \
  make spike && build/Build/Products/Debug/boris-spike \
  /Users/tbuddy/dev/drawmeanelephant/boris/main/content
```

Prints version, attempts plan, writes a validate `--report` and decodes
it, still ends `SPIKE OK` for the original IR/check/impact path.
`Sources/Models/` compiles with the new types. No SwiftUI diff.
