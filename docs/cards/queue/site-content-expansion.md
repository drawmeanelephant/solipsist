# Q23 — Site content expansion

**Owns:** `site/` only.

The P-subdomain (card 6 / Q15) landed the site skeleton: `README.md`,
`boris.json`, and a `content/` tree. Expand the public content so the
subdomain has real pages when we deploy:

- A mission page (draw from `docs/MISSION.md`)
- A roadmap page (draw from `docs/ROADMAP.md`, milestones + status table)
- A dogfood page pointing at `Stunts/happy` content
- Link the pages from `site/content/` index

**Do not** add a `"cloudflare"` publication target, Wasm wiring, or any
deploy adapter — `boris.json` stays a plain static-site profile. Deploy
(Cloudflare/wrangler) is not this card; it stays with the owners.

Gate: `boris.json` still a plain profile (no `cloudflare` string), pages
exist under `site/content/`, `make build` unaffected.
