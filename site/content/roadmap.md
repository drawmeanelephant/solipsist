---
title: Roadmap
parent: index
status: published
tags: [roadmap]
---

# Roadmap

Solipsist is a **harness**, not a better compiler and not a Markdown IDE. Boris stays a better Boris: we vendor the binary, file issues, render contracts, and host the surfaces we will not rewrite.

## Where we are

M0–M8 **gates** and the depth batch exist: first-run, filter, plan as
a document, profile 1:1, `recipe-scale`, the rest of `standard-site`,
readable proof. Remaining **ship** work is a notarized DMG on a clean
Mac. Remaining **product** cut is the Mail body: sources in Settings,
a mailbox sidebar, a reading pane.

| Track | Status |
|-------|--------|
| M0–M8 gates | landed |
| P Project subdomain | withdrawn — this site is Cloudflare Pages |
| Usability | landed — first-run, status, problem → page |
| Play / inspector / publish depth | landed |
| M9 Ship | open — notarized DMG on a clean Mac |
| M10 Mail body | planned — Settings, mailboxes, reading pane ([#98](https://github.com/drawmeanelephant/solipsist/issues/98)) |

## v1 must

- One-window Mail-grade chrome: Settings for sources, mailboxes, reading pane, inspector drawer, real menus
- Local source via security-scoped bookmark — the first account, added in Settings
- Graph as a workable list — trunks, satellites, status, relations — from contracts
- The publication profile (`boris.json`) is the single source of truth
- Coordinator verbs: Plan, Validate, Build, Check, Impact, Stop — each a menu item
- Diagnostics as a place: clickable reports, not monospaced dumps
- Engine-owned preview via `watch --serve` + SSE
- A hosted editor: `boris-editor` in a companion window, opened from the selected page
- Outputs fan-out: every profile target and edition, isolated, reported
- A publication console: GitHub Pages, Standard.site, Nostr — secrets on stdin
- Sandboxed, bundled, pinned engine

## v1 must not

- A frontmatter parser, a graph algorithm, or a homegrown Markdown renderer
- A Finder clone of the content tree
- A native editor *instead of* hosting `boris-editor` (named later: buffer + save + problems)
- An app-side HTTP server or `file://` preview
- Cloudflare / Vercel / Netlify as *in-app* deploy adapters
- Wasm or `compileBundle` *inside* Solipsist — subprocess isolation stays
- Theme *authoring* (selection only)

## The north star

Open a folder of Boris content → it is a **source** in Settings → it appears as an account with mailboxes → the reading place shows the graph as messages and a pane for the selected page → the drawer shows the profile and that page → Plan / Validate / Build surface every diagnostic → Preview reloads through `watch --serve` → Edit opens `boris-editor` → Publish runs GitHub Pages evidence, Standard.site, or Nostr with the Proof Pack attached.

This project’s own public face is a Cloudflare subdomain on Boris’s official Worker + Wasm embed host — stood up early, on the Free tier, not as an in-app engine. Full detail lives in the repository [ROADMAP.md](https://github.com/drawmeanelephant/solipsist/blob/main/docs/ROADMAP.md).
