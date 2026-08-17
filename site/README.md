# Solipsist Project Site Content

This directory contains the content and publication profile for the public Solipsist documentation and project site, hosted at `https://solipsist.pages.dev`.

## Profile & Content

- `boris.json`: Plain static-site profile (schema version 1, target `site`, output `dist`, input `content`).
- `content/`: Closed-frontmatter Markdown pages (`index.md`, `mission.md`, `roadmap.md`, `architecture.md`, `dogfood.md`).

## Deployment to Cloudflare Pages

The site is built with Boris (`boris build --profile site/boris.json`) and published to Cloudflare Pages project `solipsist` (`solipsist.pages.dev`).

### CI / GitHub Actions Deployment

The `.github/workflows/deploy-site.yml` workflow automatically builds and deploys `site/dist/` to Cloudflare Pages on push to `main` when `site/**` changes, using the repository secrets:
- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`

### Manual Deployment

To compile and deploy locally:

```bash
# 1. Compile the site with Boris
cd site
../boris/zig-out/bin/boris build --profile boris.json

# 2. Deploy dist/ to Cloudflare Pages
npx wrangler pages deploy dist --project-name solipsist
```
