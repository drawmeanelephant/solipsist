# Parallel — format and lint

**Owns:** `.swiftformat`, `.swiftlint.yml`, CI job `lint`,
`.swiftformatignore` / exclude lists.
**Do not** reformat `Sources/Play`, `Inspector`, `Engine`, `Models`,
or `Spike` in the same PR as adding the tool. Exclusions first.

## Do

1. SwiftFormat + SwiftLint configs that match Swift 6 / the existing
   style (4-space, no forced unwrap crusades).
2. Exclude the grind paths listed above until those PRs merge; then
   a *follow-up* PR may format them alone.
3. CI job `lint` on `macos-15` or `ubuntu-latest` (lint only). Do not
   make `lint` required until it is green on `main`.
4. `make lint` locally.

## Gate

`make lint` passes on `main` as it stands (because grind paths are
excluded). A new file under `Companions/` would be linted.
