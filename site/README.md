# Solipsist Project Site Content

This directory contains the content and plain publication profile for the public Solipsist documentation and project site.

## Profile & Content

- `boris.json`: Plain static-site profile (schema version 1, target `site`, output `dist`, input `content`).
- `content/`: Closed-frontmatter Markdown pages (`index.md`, `mission.md`, `architecture.md`).

## Operator Deployment

Solipsist does not build publication targets or embed cloud adapters into the desktop application binary. Publication to the project subdomain (`solipsist.drawmeanelephant.dev`) is operated via the Boris Cloudflare Worker embed host (`hosts/cloudflare-worker/` in the Boris repository) consuming `boris-embed-small.wasm`.
