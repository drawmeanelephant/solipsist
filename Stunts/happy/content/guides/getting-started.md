---
title: Getting Started
parent: index
tags: [guides]
---

# Getting Started

A page is one Markdown file with YAML frontmatter. The frontmatter
`id` is derived from the path unless you write one; `title`, `tags`,
and `parent` shape the graph.

## Add a page

Create `content/guides/example.md`:

```markdown
---
title: Example
parent: index
tags: [guides]
---

# Example

Hello from [[index]].
```

Rebuild with `boris --input content --html-dir dist --theme themes/boris`
and the page appears in the nav forest, the breadcrumb chain, and the
frozen graph.

## Frontmatter at a glance

- `title` — page title (`{{title}}`, search, and metadata).
- `parent` — entity id of the structural parent (this page lives under
  `index`).
- `tags` — free-form list rendered into page metadata.
- `relations` — semantic edges such as `[relates_to=target]`; see
  [semantic relations](https://github.com/drawmeanelephant/boris/blob/afterparty/docs/contracts/semantic-relations.md).

A wiki link `[[getting-started]]` is a real graph edge: a link to a
missing page fails the build instead of rendering as dead prose.
