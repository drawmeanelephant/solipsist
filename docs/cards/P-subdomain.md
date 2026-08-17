# Card P — Project subdomain

**Milestone:** P (parallel, start now)
**Lane:** `site/` in this repo. Operator glue only.
**Do not touch:** `Sources/`, `Spike/`, `Project.yml`, the boris git repo.

## Why

We do not have full GitHub access. Solipsist still needs a public URL
that is itself a Boris publication. Boris already ships the host:

- `hosts/cloudflare-worker/` — `POST /compile`, limits, R2
- `boris-embed-small.wasm` — `compileBundle` in the isolate
- Workers Free — module ~331 KiB gzip; warm compile measured under 10 ms

This is **not** a `publication.target` and **not** Wasm inside the Mac app.

## Do

1. Add `site/content/` — a small Solipsist site (index, what it is, link
   to the mission). Closed frontmatter. Markdown only. Keep it well
   under Worker limits (128 files, 2 MiB source).
2. Consume the official host from a **read-only** afterparty checkout
   (`../boris/hosts/cloudflare-worker` or the `fresh` worktree). Do not
   fork compile/Wasm. Copy-wasm + wrangler deploy as the boris README
   says.
3. Serve the compiled HTML on a custom subdomain. The official worker
   uploads to R2 on success; it does not have to be the public GET. A
   thin GET (same worker extra route, or Workers static/R2) is allowed
   **in this repo** under `site/`. Do not reimplement parse/graph/render.
4. Record the subdomain, account, bucket name, and the exact deploy
   commands in `site/README.md`. Trusted authors only.

## Do not

- `zig` embed into Solipsist.app
- Add `"cloudflare"` to any publication profile
- Use `#300` / `boris-job-runner` / Containers
- Serve generated pages as application UI
- Commit secrets, wrangler state, or R2 credentials

## Facts

- Failed validation → no R2 upload, no successful claims (host README).
- Trap WASI imports; do not enable Cloudflare’s experimental WASI FS.
- Local no-credentials check: `node hosts/cloudflare-worker/test.mjs`
  from the boris checkout after `zig build`.
- GitHub Pages remains the *in-app* M8 target. This card does not
  implement Pages.

## Gate

`https://<subdomain>/` returns a Boris-built Solipsist index page,
produced through the Worker + Wasm path, with no GitHub in the publish
step. `site/README.md` is enough for the next person to redeploy.
