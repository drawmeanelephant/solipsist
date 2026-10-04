# Recipe-scale truth — #308

Issue: https://github.com/drawmeanelephant/solipsist/issues/308

## Scope

Remove Swift recipe scaling and fabricated inspector recipes. Graph
facets are read-only engine data. Failed subprocesses retain their exit
codes and diagnostics; launch and JSON decode failures propagate.

The archived `bf464a0` / Boris 0.8.1 binary is unavailable in this
environment. The installed engine is 0.8.2, not the pin. Disable app
scaling until the pinned invocation and response contract are verified,
rather than treating an unpinned probe as authority.

## Paths and gate

`Sources/Engine/`, `Sources/Inspector/`, recipe coordinator/menu paths in
`Sources/App/`, `Tests/ContractTests/`, Help and contract documentation.

Regressions cover nonzero exit, launch failure, cancellation, malformed
JSON, absent recipe facets, and unchanged authoritative data. Run the
contract suite, Debug app build, and lint. Never patch Boris or mutate
authored recipe content.
