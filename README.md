# Solipsist

A native macOS harness for
[Boris](https://github.com/drawmeanelephant/boris), the deterministic
Zig graph-native publication compiler.

Radio UserLand’s job in Mail’s body: sources in Settings, mailboxes
on the left, a reading place in the middle, inspector drawer on the
right. Preview and the Svelte editor are companion windows we host.
We do not invent a second compiler.

**Status:** M0–M8 gates plus depth. Next ship is M9
([#78](https://github.com/drawmeanelephant/solipsist/issues/78)).
Next product cut is M10 Mail body
([#98](https://github.com/drawmeanelephant/solipsist/issues/98)).
File → Open… a folder under [`Stunts/`](Stunts/) (start with
`happy/`). `make test` decodes checked-in fixtures (no boris binary).

## Layout

```
Sources/
  App/ Chrome/ Workspace/ Play/ Inspector/ Companions/
  Models/     Codable mirrors of Boris JSON contracts
  Engine/     locate, run, actor — the only Process owner
Spike/        M1 CLI spike (`make run-spike`)
scripts/      embed-boris.sh, stunt-smoke.sh, stunt-from-testdata.sh
Stunts/       dogfood corpora (happy, broken-*, cook-one)
Tests/        Contract decode tests and JSON fixtures
vendor/boris-agent-kit/   pin only (no binaries)
docs/         ROADMAP · HARNESS · MISSION · cards · issues
```

Never commit `SUPPORT-NOT-FOR-GITHUB/` or engine binaries.

## Prerequisites

- macOS 14+ arm64
- Xcode 16+ (tested Xcode 27 / Swift 6)
- Zig 0.16+ only if you must *rebuild* the engine
- XcodeGen is vendored into `.tools/` by `make tools`

## Commands

```bash
make tools
make generate
make build
make test
SOLIPSIST_BORIS_BIN=/path/to/boris make run-spike
```

Engine search order: `SOLIPSIST_BORIS_BIN` → app bundle →
`SUPPORT-NOT-FOR-GITHUB/…/bin/boris` (local only) →
`../boris/zig-out/bin/boris`.

## Stunts & Contract Testing

Solipsist includes a suite of test corpora under [`Stunts/`](Stunts/):
- `happy/`: Valid 3-page publication.
- `broken-frontmatter/`: Invalid YAML frontmatter (`EFRONTMATTER`).
- `broken-parent/`: Missing trunk/parent node (`EPARENTMISSING`).
- `broken-duplicate-id/`: Duplicate page IDs (`EDUPLICATEID`).
- `broken-wikilink/`: Unresolved wikilink references (`EREFERENCEMISSING`).
- `cook-one/`: Recipe markup in Cooklang format.

Run `make test` to execute contract decoding tests against checked-in fixtures, or run `scripts/stunt-smoke.sh` to smoke test against a live Boris engine.

## CI

PRs to `main` run GitHub Actions (`spike` against a pin-built boris,
`app` compile, `fixtures` contract tests, and `lint`). The app job
still sets `SKIP_EMBED_BORIS=1` — no engine binary is vendored. A
`fart` job is reserved and disabled.

## Boundaries

- Never touch the boris repo from here. File issues; vendor the binary.
- Never reimplement Boris semantics in Swift.
- Never swallow diagnostics or exit codes.
- Subprocess isolation is a feature.
