# Solipsist — Agent Operating Manual

Read this first. Then [`docs/ROADMAP.md`](docs/ROADMAP.md) and
[`docs/HARNESS.md`](docs/HARNESS.md). Next work is one card from
[`docs/cards/`](docs/cards/README.md).

## What this is

Native macOS SwiftUI app. Boris is the engine — a subprocess, never a
library. We decode its versioned JSON contracts and host the surfaces
we refuse to write (`watch --serve`, `boris-editor`).

**Baseline:** afterparty `boris/0.8.1`. **Pin:** `b82e9e2` (kit
metadata in `vendor/boris-agent-kit/`). A3/A4/A13 merged after that
pin; bump when we vendor a newer kit.

## Hard boundaries

1. Never touch the `boris` repo. Issues live in `docs/issues/` and are
   filed on GitHub — never a PR, never a patch to boris.
2. Never reimplement Boris semantics in Swift.
3. Never silently ignore diagnostics or exit codes.
4. Never mutate the user’s content tree except on an explicit save.
5. The subprocess boundary is a feature. One `Process?` slot in
   `BorisEngine`. Cancel = `Process.terminationReason == .uncaughtSignal`.

## Doc tree

| File | Purpose |
|------|---------|
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Goals, milestones, capability coverage |
| [`docs/HARNESS.md`](docs/HARNESS.md) | Spatial model + directory lanes |
| [`docs/MISSION.md`](docs/MISSION.md) | One-page why |
| [`docs/BORIS-CAPABILITIES.md`](docs/BORIS-CAPABILITIES.md) | What the engine can do |
| [`docs/ENGINE-CONTRACTS.md`](docs/ENGINE-CONTRACTS.md) | Probed machine contracts |
| [`docs/cards/`](docs/cards/) | Grind-lane briefs |
| [`docs/cards/parallel/`](docs/cards/parallel/) | External agent — PR cop, Boris issues, busy cards off the grind paths |
| [`docs/issues/`](docs/issues/) | Ready-to-paste boris issues |

## Build

```bash
make tools && make generate && make build
SOLIPSIST_BORIS_BIN=SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris \
  make run-spike
```

Never hand-edit `Solipsist.xcodeproj` — edit `Project.yml`.

## Git

- `main` is the clean merge target. Feature work is a branch + PR.
- Never `git add -A`. Never stage `SUPPORT-NOT-FOR-GITHUB/`.
- Never commit files you did not change.
- `boris/` is never touched by git operations from this repo.

## Milestones

M0 bootstrap ✅ · M1 spike ✅ · M2 chassis ✅ · **P** withdrawn ·
**M3** play & inspect ✅ · **M4** coordinate ✅ · **M5** preview ✅
· **M6** author ✅ · **M7** outputs ✅ · **M8** publish ✅ · **M9**
ship 🔧 ([#78](https://github.com/drawmeanelephant/solipsist/issues/78))
· **M10** Mail body 📋
([#98](https://github.com/drawmeanelephant/solipsist/issues/98) —
Settings / mailboxes / reading / compose #106 — after #78, never
inside it).
