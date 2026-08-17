# Solipsist Project Subdomain (Card P)

This directory contains the source content and operator glue for the public Solipsist project site hosted on Cloudflare Workers + R2 via the official Boris Wasm embed host.

## Architecture

Boris ships an official Cloudflare Worker embed host (`hosts/cloudflare-worker/` in the Boris repository) that consumes `boris-embed-small.wasm` to compile source bundles directly in a Cloudflare Worker isolate on the Workers Free tier.

- **Host role**: `POST /compile` accepts source files, runs `compileBundle` inside the Wasm isolate, and uploads successful builds to R2 (`ARTIFACTS` bucket).
- **Public serving**: A thin GET handler serves the static HTML artifacts from R2 over the custom subdomain `solipsist.drawmeanelephant.dev`.

## Deploy Instructions

### Prerequisites
- Node.js 18+
- Wrangler CLI (`npm install -g wrangler`)
- Access to Cloudflare account with R2 bucket configured

### 1. Build and Prepare Engine Wasm
From a read-only checkout of `drawmeanelephant/boris`:
```bash
cd /path/to/boris
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
cp zig-out/bin/boris-embed-small.wasm hosts/cloudflare-worker/
```

### 2. Test Locally
```bash
cd /path/to/boris/hosts/cloudflare-worker
node test.mjs
```

### 3. Deploy Worker
```bash
npx wrangler deploy
```

### 4. Publish Site Content
Post the `site/content/` files as a bundle to the worker endpoint or sync via Boris profile publishing.

## Boundary Notes
- Solipsist desktop app does **not** embed Wasm or run Cloudflare deploy adapters inside the macOS client.
- Subdomain hosting is project infrastructure, not application UI.
