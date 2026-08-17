# Solipsist

A native **macOS Swift/SwiftUI application** wrapping
[Boris](https://github.com/drawmeanelephant/boris) — the deterministic Zig
documentation compiler — as its engine: author, validate, preview, and
publish Boris content sites from a desktop app.

**Status:** M1 — engine spike. The app shell runs the bundled `boris` binary
and decodes its JSON contracts (`build-report.json`, `manifest.json`,
`graph.json`, and the `check`/`impact` analysis reports). See
[docs/PLAN-MAC-APP.md](docs/PLAN-MAC-APP.md) for the full plan.

## Layout

```
Sources/
  App/        SwiftUI app shell (entry point, minimal UI)
  Models/     Codable mirrors of the Boris JSON contracts (shared)
  Engine/     Boris subprocess layer: binary location, runner, engine actor
Spike/        M1 CLI spike that runs the engine and prints decoded results
scripts/      embed-boris.sh — builds the engine and bundles it
Project.yml   XcodeGen spec (generates Solipsist.xcodeproj)
docs/         PLAN-MAC-APP.md (architecture + milestones)
```

The `boris` checkout must be present next to this repo at `../boris`
(`BORIS_REPO_DIR` overrides it).

## Prerequisites

- macOS 14+ (arm64)
- Xcode 16+ (tested with Xcode 27 / Swift 6)
- Zig 0.16+ and CMake — only to *build* the engine binary; the shipped app
  embeds the compiled binary and needs none of this at runtime
- XcodeGen — vendored automatically into `.tools/` (no global install)

## Commands

```bash
make tools      # vendor XcodeGen 2.46.0 into .tools/
make generate   # generate Solipsist.xcodeproj from Project.yml
make build      # build the app (bundles the boris binary)
make run-spike  # build + run the M1 engine spike against ../boris/content
```

The spike locates the engine via `SOLIPSIST_BORIS_BIN`, the app bundle, or
`../boris/zig-out/bin/boris`. In the app, use *Open Content Folder…* to pick
a content root (the folder you would pass to Boris as `--input`).
