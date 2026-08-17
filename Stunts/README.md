# Stunt projects

Tiny Boris trees for Solipsist to open. Not product content. Not
checked-in `dist/` or `.boris/` — harvest those into
`Tests/Fixtures/` via `scripts/harvest-stunt-fixtures.sh` when you
have a kit binary.

| Stunt | What it is | Open in Solipsist as |
|-------|------------|----------------------|
| `happy/` | `boris init` shape: 3 pages, theme, `boris.json` | the **folder** (project root) |
| `broken-frontmatter/` | unknown key `category` → `EFRONTMATTER` | the folder (content root) |
| `broken-parent/` | `parent: does-not-exist` → `EPARENTMISSING` | the folder |
| `broken-textile/` | incomplete `"link":` → `ETEXTILE` | the folder |
| `cook-one/` | one `.cook` recipe | the folder; needs `--cooklang` later |
| `happy-textile/` | 2 `.textile` pages (`input_format: "textile"`) | the folder (project root) |

Happy is the default dogfood. Broken stunts exist so Validate / Build
IR have diagnostics to show. Do not “fix” the broken ones.
