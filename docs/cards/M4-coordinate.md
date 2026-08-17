# Card M4 — Coordinator UI

**Milestone:** M4 (the verbs). Engine S0 is already on `main`.
**Lane:** `Sources/App/` (Commands, Coordinator), `Sources/Play/Local/`
(activity / problems), small additive Engine (`interrupt`, optional
`--report` on HTML). `Sources/Workspace/Local/` for shared root helpers.
**Do not touch:** `Inspector/`, `Companions/`, `Spike/`.

## Gate

With a local source selected, File/Boris menu: Plan, Validate, Build IR,
Build HTML, Check, Impact (page selected), Stop. Problems pane lists
`--report` diagnostics (or check findings). Every exit code is visible
in the status bar. `make build` succeeds.
