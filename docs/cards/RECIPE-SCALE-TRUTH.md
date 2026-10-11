# Recipe-scale truth — #308

Issue: https://github.com/drawmeanelephant/solipsist/issues/308

## Scope

Remove Swift recipe scaling and fabricated inspector recipes. Graph
facets are read-only engine data. Failed subprocesses retain their exit
codes and diagnostics; launch and JSON decode failures propagate.

The pin moved to `3ab19ad` / Boris 0.8.2 and the contract is now
verified (`docs/ENGINE-CONTRACTS.md` §10): `recipe-scale --input DIR
--id PAGE --factor TEXT [--cooklang]` emits a `boris-recipe-scale` 0.2.0
envelope whose `quantity.amount` is `{class, original, scaled}` — a
different shape than the graph facet's string amount. The transport and
decoder are fixed; `RecipeScaleSupport.isAvailable` is live again.

## Paths and gate

`Sources/Engine/`, `Sources/Inspector/`, recipe coordinator/menu paths in
`Sources/App/`, `Tests/ContractTests/`, Help and contract documentation.

Regressions cover nonzero exit, launch failure, cancellation, malformed
JSON, absent recipe facets, and unchanged authoritative data. Run the
contract suite, Debug app build, and lint. Never patch Boris or mutate
authored recipe content.
