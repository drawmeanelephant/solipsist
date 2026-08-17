# Delegation queue

Work that can run **without GitHub web** and **without the grind
lane**. One card = one worktree = one PR against `main`.

Open `Stunts/happy` in Solipsist as the default dogfood.

## Forbidden paths (grind / already in flight)

`Sources/Play/` · `Sources/Inspector/` · `Sources/Engine/` ·
`Sources/Models/` (read-only — flag, don't edit) · `Spike/` ·
`Sources/Chrome/MainWindow.swift` · `Sources/Chrome/InspectorDrawer.swift`
· `Sources/App/Coordinator.swift` · `Sources/App/Commands.swift` ·
`Sources/Workspace/` · `scripts/embed-boris.sh` (search order) · the
`boris` git repo.

If you need a new engine method, stop and leave a note. If Boris
misbehaves, draft `docs/issues/boris-A<N>-*.md` — do not patch boris.

## Queue

Status legend: **open** · **in flight** (PR open) · **done** (merged — do not pick).

### Batch 1 (all merged)

| ID | Card | Owns | Status |
|----|------|------|--------|
| Q0 | [file-boris-issues](file-boris-issues.md) | `docs/issues/` headers | rolling (A1/A14/A7/A5 filed) |
| Q1 | [stunt-smoke-script](stunt-smoke-script.md) | `scripts/stunt-smoke.sh` | done (#26) |
| Q2 | [preview-shell](../parallel/preview-shell.md) | `Companions/Preview/` | done (#9) |
| Q3 | [editor-shell](../parallel/editor-shell.md) | `Companions/Editor/` | done (#23) |
| Q4 | [lint](../parallel/lint.md) | lint configs + CI job | done (#24) |
| Q5 | [assets](../parallel/assets.md) | asset catalog | done (#27) |
| Q6 | [help-sheet](../parallel/help-sheet.md) | `docs/help.md` | done (#29) |
| Q7 | [dependabot](../parallel/dependabot.md) | `.github/dependabot.yml` | done (#21) |
| Q8 | [issue-templates](../parallel/issue-templates.md) | `.github/ISSUE_TEMPLATE/` | done (#22) |
| Q9 | [stunt-duplicate-id](stunt-duplicate-id.md) | `Stunts/broken-duplicate-id/` | done (#26) |
| Q10 | [stunt-wikilink](stunt-wikilink.md) | `Stunts/broken-wikilink/` | done (#26) |
| Q11 | [cook-stunt-ir](cook-stunt-ir.md) | `Stunts/cook-one/` + fixture | done (#26) |
| Q12 | [fixture-check-report](fixture-check-report.md) | `Tests/Fixtures/check-happy/` | done (#26) |
| Q15 | [p-subdomain](../P-subdomain.md) | `site/` | done (#28) |
| Q16 | [testdata-wrapper](testdata-wrapper.md) | `scripts/stunt-from-testdata.sh` | done (#26) |
| Q17 | [gitignore-stunts](gitignore-stunts.md) | `.gitignore` only extra lines | done (#26) |
| Q18 | [readme-stunts](readme-stunts.md) | `README.md` one paragraph | done (#26) |
| Q19 | [pr-cop](pr-cop.md) | no source | done (#25, #31) |

### Batch 2

| ID | Card | Owns | Status |
|----|------|------|--------|
| Q13 | [about-window](about-window.md) | `Sources/App/AboutWindow.swift` + one `Window` in `SolipsistApp.swift` | done (#46) |
| Q20 | [companion-url-tests](companion-url-tests.md) | `Tests/` + read-only extraction in `Companions/` | done (#47) |
| Q21 | [contract-null-locations](contract-null-location-fixtures.md) | `Tests/Fixtures/` + `ContractDecodeTests` | done (#51) |
| Q22 | [make-lint-fails-loudly](make-lint-fail-loudly.md) | `Makefile` lint target only | done (#52) |
| Q23 | [site-content-expansion](site-content-expansion.md) | `site/` only | done (#49) |
| Q24 | [stunt-textile-corpus](stunt-textile-corpus.md) | `Stunts/` + `Tests/Fixtures/` | done (#50) |
| Q25 | [help-doc-coverage](help-doc-coverage.md) | `docs/help.md` only | done (#48) |

### Retired

| ID | Card | Why |
|----|------|-----|
| Q14 | statusbar-exit-color | Owns `Sources/Chrome/MainWindow.swift`, which is on this queue's own forbidden list. Grind lane owns the status bar — do not pick. |

No open batch-2 cards remain — batch 2 is fully landed. Check batch 3 in the issue tracker before picking.
