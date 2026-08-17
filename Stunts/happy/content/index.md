---
title: My Boris Site
tags: [home]
---

# Welcome

This is a fresh [Boris](https://github.com/drawmeanelephant/boris)
documentation site. It already has a page graph: this trunk page,
two guides beneath it, wiki links between them, and one semantic
relation.

Start here:

- [[guides/getting-started]] — add your own pages and watch the graph grow.
- [[guides/publishing]] — turn the site into a verified publication.

## Anatomy of this starter

The tree `boris init` created:

```text
content/
  index.md                    trunk page (this one)
  guides/getting-started.md   satellite, parent: index
  guides/publishing.md        satellite, parent: index
themes/boris/                 starter theme (closed layout slots)
boris.json                    publication profile (GitHub Pages)
standard-site.json            Atmosphere profile (edit the fake DID/URL)
```
