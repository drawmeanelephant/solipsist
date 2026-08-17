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

| ID | Card | Owns |
|----|------|------|
| Q0 | [file-boris-issues](file-boris-issues.md) | `docs/issues/` headers |
| Q1 | [stunt-smoke-script](stunt-smoke-script.md) | `scripts/stunt-smoke.sh` |
| Q2 | [preview-shell](../parallel/preview-shell.md) | `Companions/Preview/` |
| Q3 | [editor-shell](../parallel/editor-shell.md) | `Companions/Editor/` |
| Q4 | [lint](../parallel/lint.md) | lint configs + CI job |
| Q5 | [assets](../parallel/assets.md) | asset catalog |
| Q6 | [help-sheet](../parallel/help-sheet.md) | `docs/help.md` |
| Q7 | [dependabot](../parallel/dependabot.md) | `.github/dependabot.yml` |
| Q8 | [issue-templates](../parallel/issue-templates.md) | `.github/ISSUE_TEMPLATE/` |
| Q9 | [stunt-duplicate-id](stunt-duplicate-id.md) | `Stunts/broken-duplicate-id/` |
| Q10 | [stunt-wikilink](stunt-wikilink.md) | `Stunts/broken-wikilink/` |
| Q11 | [cook-stunt-ir](cook-stunt-ir.md) | `Stunts/cook-one/` + fixture |
| Q12 | [fixture-check-report](fixture-check-report.md) | `Tests/Fixtures/check-happy/` |
| Q13 | [about-window](about-window.md) | `Sources/App/AboutWindow.swift` only |
| Q14 | [statusbar-exit-color](statusbar-exit-color.md) | note only if Coordinator already owns it — **skip if M4-coordinate unmerged** |
| Q15 | [p-subdomain](../P-subdomain.md) | `site/` |
| Q16 | [testdata-wrapper](testdata-wrapper.md) | `scripts/stunt-from-testdata.sh` |
| Q17 | [gitignore-stunts](gitignore-stunts.md) | `.gitignore` only extra lines |
| Q18 | [readme-stunts](readme-stunts.md) | `README.md` one paragraph |
| Q19 | [pr-cop](pr-cop.md) | no source |

Pick the lowest unused ID. Stay in that card’s paths.
