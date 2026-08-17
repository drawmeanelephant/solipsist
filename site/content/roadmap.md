---
title: Roadmap
parent: index
status: published
---
# Roadmap

Solipsist is a **harness**, not a better compiler and not a Markdown
IDE. Boris stays a better Boris: we vendor the binary, file issues,
render contracts, and host the surfaces we will not rewrite.

## Where we are

| Milestone | Status |
|-----------|--------|
| **M0** Bootstrap | ✅ |
| **M1** Engine spike | ✅ — decodes the IR contracts |
| **M2** Chassis | ✅ — sources / play / drawer / companion slots |
| **P** Project subdomain | next (parallel) |
| **M3** Play & inspect | next |
| **M4** Coordinate | — |
| **M5** Preview | — |
| **M6** Author | — |
| **M7** Outputs | — |
| **M8** Publish | — |
| **M9** Ship | — |

## v1 must

- One-window Mail-grade chrome: sources, play, inspector drawer, real menus
- Local source via security-scoped bookmark
- Graph as a workable list — trunks, satellites, status, relations — from contracts
- The publication profile (`boris.json`) is the single source of truth
- Coordinator verbs: Plan, Validate, Build, Check, Impact, Stop — each a menu item
- Diagnostics as a place: clickable reports, not monospaced dumps
- Engine-owned preview via `watch --serve` + SSE
- A hosted editor: `boris-editor` in a companion window
- Outputs fan-out: every profile target and edition, isolated, reported
- A publication console: GitHub Pages, Standard.site, Nostr — secrets on stdin
- Sandboxed, bundled, pinned engine

## v1 must not

- A from-scratch native editor or frontmatter parser
- An app-side HTTP server or `file://` preview
- A graph algorithm in Swift
- Cloudflare / Vercel / Netlify as *in-app* deploy adapters
- Wasm or `compileBundle` *inside* Solipsist — subprocess isolation stays
- Theme *authoring* (selection only)

## The north star

Open a folder of Boris content → it appears as a **source** → the play
place shows the real graph from `graph.json` → the drawer shows the
profile and the selected page → Plan / Validate / Build surface every
diagnostic → Preview reloads through `watch --serve` → Edit opens
`boris-editor` → Publish runs GitHub Pages evidence, Standard.site, or
Nostr with the Proof Pack attached.

This project's own public face is a Cloudflare subdomain on Boris's
official Worker + Wasm embed host — stood up early, on the Free tier,
not as an in-app engine. Full detail lives in the repository
[ROADMAP.md](https://github.com/drawmeanelephant/solipsist/blob/main/docs/ROADMAP.md).
