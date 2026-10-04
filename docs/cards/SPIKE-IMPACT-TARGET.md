# Spike impact target and controlled failures — #311

Issue: https://github.com/drawmeanelephant/solipsist/issues/311

## Scope and gate

Choose the default impact page from the graph Boris returned, or validate
an explicit ID. Report empty/missing graphs, failed commands, missing or
malformed reports, and early watch exits without Swift fatal-error traps.
Keep subprocess diagnostics and nonzero exits. Bound watch readiness and
shutdown waits; only successful probes print `SPIKE OK`.

`boris-spike [content-root] [impact-page-id]` accepts the optional ID.
Make equivalents are `SPIKE_CONTENT` and `SPIKE_PAGE`.

Paths: `Spike/`, analysis report/error transport and watch snapshots in
`Sources/Engine/`, `Tests/ContractTests/`, `Tests/Spike/`, `Project.yml`,
Makefile, and the existing spike CI job.

Run contract regressions, `make test-spike`, and live smoke tests against
temporary copies of namespaced and `getting-started` corpora. The local
engine is unpinned Boris 0.8.2; report that limitation. The existing CI
spike job builds `bf464a0` / Boris 0.8.1 and exercises the pin. Never patch
Boris or run build/watch against a user's original content tree.
