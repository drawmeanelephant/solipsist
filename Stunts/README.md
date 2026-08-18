# Stunt projects

Tiny Boris trees for Solipsist to open. Not product content. Not
checked-in `dist/` or `.boris/` — harvest those into
`Tests/Fixtures/` via `scripts/harvest-stunt-fixtures.sh` when you
have a kit binary.

| Stunt | What it is | Open in Solipsist as |
|-------|------------|----------------------|
| `dogfood/` | 45-page / 7-trunk M3 gate corpus, theme, `boris.json` | the **folder** (project root) |
| `happy/` | `boris init` shape: 3 pages, theme, `boris.json` | the **folder** (project root) |
| `broken-duplicate-id/` | two pages share an `id` → `EDUPLICATEID` | the folder |
| `broken-frontmatter/` | unknown key `category` → `EFRONTMATTER` | the folder (content root) |
| `broken-parent/` | `parent: does-not-exist` → `EPARENTMISSING` | the folder |
| `broken-textile/` | incomplete `"link":` → `ETEXTILE` | the folder |
| `broken-wikilink/` | `[[missing-page]]` → `EREFERENCEMISSING` | the folder |
| `cook-one/` | one `.cook` recipe | the folder; needs `--cooklang` later |
| `happy-textile/` | 2 `.textile` pages (`input_format: "textile"`) | the folder (project root) |

`dogfood` is the 45-page / 7-trunk M3 gate corpus. `happy` is the starter
dogfood. Broken stunts exist so Validate / Build IR have diagnostics to
show. Do not “fix” the broken ones.

## Manual check: D8 unknown-schemaVersion degrade (#56)

To see the D8 degrade banner in the play pane (unknown/newer
`schemaVersion` renders “Graph Unavailable” instead of a page list),
create a synthetic corpus in `/tmp` — it cannot be committed because
`.boris/` is gitignored (`Stunts/**/.boris/`), so a stunt can’t ship a
pre-baked graph:

```bash
mkdir -p /tmp/unknown-schema-corpus/content /tmp/unknown-schema-corpus/.boris
cp Stunts/happy/boris.json /tmp/unknown-schema-corpus/boris.json
printf -- '---\ntitle: Unknown Schema\n---\n\n# Unknown Schema\n' \
  > /tmp/unknown-schema-corpus/content/index.md
cat > /tmp/unknown-schema-corpus/.boris/graph.json <<'EOF'
{
  "schemaVersion": "0.9.9",
  "frozen": true,
  "nodes": [{"index": 0, "id": "index", "sourcePath": "index.md",
    "role": "trunk", "parent": null, "parentIndex": null,
    "title": "Unknown Schema", "status": "published",
    "tags": [], "bodyOffset": 60}],
  "edges": [], "reverseIndex": [], "nav": [], "relations": []
}
EOF
```

Then File → Open… that folder. The play pane must show **Graph
Unavailable** with `schemaVersion "0.9.9" is not a known IR version
(supported: 0.2.0, 0.3.0, 0.4.0). Refusing to render an unknown shape.`
and a Try Again button — never a page list. Covered headlessly by
`testSchemaPolicyUnknownVersion` in `ContractDecodeTests`; this corpus is
the manual, end-to-end confirmation. Opening `Stunts/happy` (0.3.0) in the
same build must still render its 3-page list normally.
