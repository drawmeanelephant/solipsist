# Solipsist — Onboarding

Your first 30 minutes in this repo. For agents, [`AGENTS.md`](../AGENTS.md)
is the authority; this is the human-speed version of the same room.

## 0. What you're holding

A native macOS SwiftUI harness for
[Boris](https://github.com/drawmeanelephant/boris), the deterministic
Zig graph-native publication compiler. Radio UserLand's job in Mail's
body: sources in Settings, mailboxes on the left, a reading place in
the middle, an inspector drawer on the right. Preview and the Svelte
editor are companion windows we host. We do not invent a second
compiler.

## 1. Read (10 min)

In this order:

1. [`MISSION.md`](MISSION.md) — why a native desktop citizen at all.
2. [`HARNESS.md`](HARNESS.md) — the spatial model and the work lanes.
3. [`ROADMAP.md`](ROADMAP.md) — goals, milestones, what's next.
4. [`../README.md`](../README.md) — commands, stunts, CI, boundaries.
5. [`../AGENTS.md`](../AGENTS.md) — the hard boundaries. They apply to
   everyone, not just agents.

## 2. Check the room (5 min)

```bash
make doctor
```

`scripts/doctor.sh` checks the environment and repo hygiene: required
files present, no forbidden files tracked or staged (transport binaries
and `SUPPORT-NOT-FOR-GITHUB/` must never reach GitHub), XcodeGen
vendored, which `boris` binary the engine search order would pick, and
— on a Mac — Xcode and lint tools. Warnings are advice; failures block.

If Boris is installed only on `PATH`, set `SOLIPSIST_BORIS_BIN` to its
absolute executable path; the app and embed script do not search `PATH`.
Run `make test-doctor` for portable regression tests of the health checks.

## 3. Build (10 min, macOS only)

The app only builds on a Mac. Docs, scripts, and `make doctor` work
anywhere.

```bash
make tools && make generate && make build
make test   # contract decode tests; needs no boris binary
```

Never hand-edit `Solipsist.xcodeproj` — edit `Project.yml`, then
`make generate`.

## 4. Touch it (5 min)

Launch the app, **File → Open…** a folder under [`Stunts/`](../Stunts/)
(start with `happy/`). That is the whole dogfood loop: a tiny Boris
tree becomes sources, mailboxes, and a reading pane. The broken-*
stunts are the diagnostic vocabulary — open one and watch Problems
become a place.

## Map

```
Sources/
  App/        app lifecycle, coordinator, settings, commands, help
  Chrome/     main window chrome: sidebar, reading host, inspector drawer
  Workspace/  sources (local / git / GitHub), sidebar state, persistence
  Play/       mailbox surfaces: pages, outputs, publish, plan, activity
  Inspector/  drawer content: profile/page fields, theme browser
  Companions/ hosted foreign surfaces: Preview (watch --serve), Editor
  Compose/    native editor window: buffer, highlight, Oliver preview
  Intents/    App Intents — Siri drafts (M18)
  Models/     Codable mirrors of the Boris JSON contracts
  Engine/     locate, run, actor — the only Process owner
  Security/   stdin secret buffers, Keychain, credential helpers
Spike/        M1 headless CLI (`make run-spike`)
scripts/      embed-boris.sh, doctor.sh, stunt-smoke.sh, …
Stunts/       dogfood corpora (happy, broken-*, cook-one)
Tests/        contract decode tests + JSON fixtures
vendor/boris-agent-kit/   kit pin metadata only (no binaries)
site/         public docs site — itself a Boris publication
docs/         ROADMAP · HARNESS · MISSION · cards · issues · this file
```

## Boundaries (the short version)

- Never touch the `boris` repo. File issues; vendor the binary.
- Never reimplement Boris semantics in Swift.
- Never swallow diagnostics or exit codes.
- Never commit `SUPPORT-NOT-FOR-GITHUB/`, engine binaries, or
  `*.tar.gz`. Never `git add -A`.
- Never mutate the user's content tree except on an explicit save.

## Next work

[`cards/README.md`](cards/README.md) is the session board. Right now
the tracker is empty; the named-but-unscheduled candidates live in
[`ROADMAP.md`](ROADMAP.md) §3. Pick one, cut an issue draft, then a
card.
