# Delegation queue

Work that can run **without GitHub web** and **without the grind
lane**. One card = one worktree = one PR against `main`.

Open `Stunts/happy` in Solipsist as the default dogfood.

## Forbidden paths (grind / already in flight)

`Sources/Play/` · `Sources/Inspector/` · `Sources/Engine/` ·
`Sources/Models/` · `Spike/` · `Sources/Chrome/MainWindow.swift` ·
`Sources/Chrome/InspectorDrawer.swift` · `Sources/App/Coordinator.swift`
· `Sources/App/Commands.swift` · the `boris` git repo.

If you need a new engine method, stop and leave a note. If Boris
misbehaves, draft `docs/issues/boris-A<N>-*.md` — do not patch boris.

## Queue

Status legend: **open** · **in flight** (PR open) · **done** (merged — do not pick).

| ID | Card | Owns | Status |
|----|------|------|--------|
| Q0 | [file-boris-issues](file-boris-issues.md) | `docs/issues/` headers | rolling (A1/A14/A7 filed; A5 via #32) |
| Q1 | [stunt-smoke-script](stunt-smoke-script.md) | `scripts/stunt-smoke.sh` | done (#26) |
| Q2 | [preview-shell](../parallel/preview-shell.md) | `Companions/Preview/` | done (#9) |
| Q3 | [editor-shell](../parallel/editor-shell.md) | `Companions/Editor/` | done (#23) |
| Q4 | [lint](../parallel/lint.md) | lint configs + CI job | in flight — PR #24 |
| Q5 | [assets](../parallel/assets.md) | asset catalog | done (#27) |
| Q6 | [help-sheet](../parallel/help-sheet.md) | `docs/help.md` | done (#29) |
| Q7 | [dependabot](../parallel/dependabot.md) | `.github/dependabot.yml` | done (#21) |
| Q8 | [issue-templates](../parallel/issue-templates.md) | `.github/ISSUE_TEMPLATE/` | done (#22) |
| Q9 | [stunt-duplicate-id](stunt-duplicate-id.md) | `Stunts/broken-duplicate-id/` | done (#26) |
| Q10 | [stunt-wikilink](stunt-wikilink.md) | `Stunts/broken-wikilink/` | done (#26) |
| Q11 | [cook-stunt-ir](cook-stunt-ir.md) | `Stunts/cook-one/` + fixture | done (#26) |
| Q12 | [fixture-check-report](fixture-check-report.md) | `Tests/Fixtures/check-happy/` | done (#26) |
| Q13 | [about-window](about-window.md) | `Sources/App/AboutWindow.swift` only | **open** |
| Q14 | [statusbar-exit-color](statusbar-exit-color.md) | note only if Coordinator already owns it — **skip if M4-coordinate unmerged** | **open** |
| Q15 | [p-subdomain](../P-subdomain.md) | `site/` | done (#28) |
| Q16 | [testdata-wrapper](testdata-wrapper.md) | `scripts/stunt-from-testdata.sh` | done (#26) |
| Q17 | [gitignore-stunts](gitignore-stunts.md) | `.gitignore` only extra lines | done (#26) |
| Q18 | [readme-stunts](readme-stunts.md) | `README.md` one paragraph | done (#26) |
| Q19 | [pr-cop](pr-cop.md) | no source | done (#25, #31) |

Pick the lowest **open** ID (next: Q13, then Q14). Stay in that card’s paths.
