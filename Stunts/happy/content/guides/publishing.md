---
title: Publishing
parent: index
tags: [guides]
relations: [relates_to=guides/getting-started]
---

# Publishing

Boris treats the deployment URL as publication truth, not an incidental
detail. The starter profile declares one public HTML target:

```json
{
  "format": "boris-publication-profile",
  "schema_version": 1,
  "input": "content",
  "targets": [
    { "name": "public", "output": "dist", "public": true, "theme": "themes/boris" }
  ]
}
```

Inspect the normalized plan before publishing:

```text
boris plan --profile boris.json
boris standard-site plan --profile standard-site.json
```

The official GitHub Pages workflow (see the repository's
`docs/github-pages.md`) builds a verified target: it resolves the Pages
location from `actions/configure-pages`, fails on any URL projection
that disagrees with it, uploads only inventory-verified files, and
retains a separate evidence artifact. Atmosphere publication uses
`standard-site.json`: replace the obviously-fake DID and URL
before `standard-site publish`. This starter page is related to
[[guides/getting-started]] so the semantic graph has an edge to inspect.
