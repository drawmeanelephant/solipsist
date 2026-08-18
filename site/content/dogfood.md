---
title: Dogfooding
parent: index
status: published
tags: [dogfooding]
---

# Dogfooding

Solipsist’s test corpora — the **Stunts** — are tiny Boris trees used to open, inspect, and diagnose. They live in the repository under `Stunts/` and double as the app’s default demo content.

## The happy path: `Stunts/happy`

`happy/` is the shape `boris init` creates: a trunk page, two guides beneath it, wiki links between them, a starter theme, and a `boris.json` publication profile. Open the folder in Solipsist and the play place lists the three pages from `graph.json`; select one and the drawer shows its completion-backed fields.

## The broken stunts

Broken stunts exist so Validate / Build IR have diagnostics to show — do not “fix” them:

| Stunt | What breaks |
|-------|-------------|
| `broken-frontmatter/` | unknown key `category` → `EFRONTMATTER` |
| `broken-parent/` | `parent: does-not-exist` → `EPARENTMISSING` |
| `broken-wikilink/` | link to a missing page → `EREFERENCEMISSING` |
| `broken-duplicate-id/` | two pages with the same id → `EDUPLICATEID` |
| `broken-textile/` | incomplete `"link":` → `ETEXTILE` |

## Other corpora

- `happy-textile/` — two `.textile` pages under the bounded Textile compatibility subset (`input_format: "textile"`)
- `cook-one/` — one `.cook` recipe for Cooklang handling

See [Stunts/README.md](https://github.com/drawmeanelephant/solipsist/blob/main/Stunts/README.md) in the repository for the full table and harvesting instructions.
