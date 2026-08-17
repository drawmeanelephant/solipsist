# Solipsist

A native macOS harness for
[Boris](https://github.com/drawmeanelephant/boris), the deterministic
Zig graph-native publication compiler.

Radio UserLand’s job in Mail’s body: sources on the left, play in the
middle, inspector drawer on the right. Preview and the Svelte editor
are companion windows we host. We do not invent a second compiler.

**Status:** M2 chassis. File → Open… adds a local folder as a source.
Next work is cards in [`docs/cards/`](docs/cards/README.md). Goals:
[`docs/ROADMAP.md`](docs/ROADMAP.md).

## Layout

```
Sources/
  App/ Chrome/ Workspace/ Play/ Inspector/ Companions/
  Models/     Codable mirrors of Boris JSON contracts
  Engine/     locate, run, actor — the only Process owner
Spike/        M1 CLI spike (`make run-spike`)
scripts/      embed-boris.sh
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
SOLIPSIST_BORIS_BIN=/path/to/boris make run-spike
```

Engine search order: `SOLIPSIST_BORIS_BIN` → app bundle →
`SUPPORT-NOT-FOR-GITHUB/…/bin/boris` (local only) →
`../boris/zig-out/bin/boris`.

## CI

PRs to `main` run GitHub Actions (`spike` compile + `app` compile).
There is no boris binary in CI, so the spike is compile-only and the
app embeds nothing. A `fart` job is reserved and disabled.

## Boundaries

- Never touch the boris repo from here. File issues; vendor the binary.
- Never reimplement Boris semantics in Swift.
- Never swallow diagnostics or exit codes.
- Subprocess isolation is a feature.
