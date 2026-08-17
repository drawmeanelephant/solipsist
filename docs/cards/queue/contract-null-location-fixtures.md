# Q21 — Contract fixtures: null-location diagnostics

**Owns:** `Tests/Fixtures/`, `Tests/ContractTests/ContractDecodeTests.swift`,
and `Sources/Models/` decode types only if a field is missing.

M4's gate says the problems list must stay clickable when
`sourcePath`/`line`/`column` are **null** — Boris reports them as optional.
Today the fixtures only cover non-null diagnostics (broken-frontmatter,
broken-parent, broken-duplicate-id, broken-wikilink).

Add a fixture (e.g. `Tests/Fixtures/broken-null-locations/build-report.json`)
with a mix of diagnostics where some or all of `sourcePath`, `line`,
`column` are null, plus decode tests asserting they decode to `nil` and
the report still decodes `ok == false` with the right `code`.

If the decode model forces non-optional location fields, fix the model
(optional) — `Models/` is only readable otherwise, so flag it in the PR
if the change looks like it reaches beyond the fixture.

Gate: `make test` — new fixture decodes, nulls stay null.
