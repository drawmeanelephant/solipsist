# Compose buffer source identity — #309

Issue: https://github.com/drawmeanelephant/solipsist/issues/309

## Scope

Bind each loaded Compose buffer to its source ID, resolved workspace and
content roots, and graph-owned file path. Observe source relocation as
well as page selection. Preserve the old document and bookmark access
until a replacement loads successfully.

Dirty switches offer Save / Discard / Cancel. Save and delayed validation
use the buffer's owning source, not the current sidebar selection. Show
the owning source and file in the Compose window, including when the
source is removed or a switch is cancelled.

## Paths

`Sources/Compose/`, source-bound save routing in
`Sources/App/Coordinator.swift`, `Tests/ContractTests/`, `Tests/Native/`,
`Project.yml`.
GitHub manual-command eligibility (#310) is out of scope.

## Gate

Equal page nouns in distinct sources, relocation, clean and dirty
switches, failed loads/saves, removal, and source-bound validation have
regressions. Run ContractTests, an app build, and lint. Verify the native
source-switch workflow using temporary copies only.

The native window and delayed-validation smoke uses two temporary
publications, an isolated defaults suite, and a stub subprocess that
records its arguments. After building the Debug app, run:

```bash
bash Tests/Native/run-compose-source-switch-smoke.sh
```

This requires macOS 27 and a GUI session. It never opens the user's
sources, invokes a remote GitHub verb, or uses the real Boris/Oliver
engines.
