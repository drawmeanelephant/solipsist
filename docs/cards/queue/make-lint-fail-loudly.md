# Q22 — `make lint` fails loudly without tools

**Owns:** `Makefile` lint target only.

The CI lint job now installs swiftformat/swiftlint and runs
`swiftformat --lint .` + `swiftlint --strict` — but the local `make lint`
target still has the old fake fallback: when the tools are missing it
prints "Lint configs OK" and exits 0. That is a fake gate and must die.

Make `make lint`:
- exit non-zero with a clear "install swiftformat and swiftlint"
  message when either tool is missing, **or**
- install them via `brew install swiftformat swiftlint` and run both
  checks (match CI exactly).

Do not touch `ci.yml`. Do not reformat files — configs already exist and
pass in CI.

Gate: `make lint` with tools missing exits non-zero; with tools present it
runs both checks exactly as CI does.
