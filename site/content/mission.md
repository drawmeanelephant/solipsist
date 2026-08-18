---
title: Mission
parent: index
status: published
tags: [mission]
---

# Mission

**Solipsist is Radio UserLand’s job in Mail’s body**: a native Mac harness that turns the graph-native publication compiler into a one-window workstation for sources, play, inspection, preview, and broadcast — and refuses to invent anything the HIG or a Boris contract already named.

## The engine we harness

Boris is **not a Markdown-to-HTML converter**. It is a compiler: Markdown (or Textile, or Cooklang) in → a validated Trunk/Satellite content graph → deterministic contracted projections (HTML, JSON IR, RAG packs, context bundles, llms.txt, RSS, sitemap, and live publication targets). Solipsist harnesses the `afterparty` integration line — `boris/0.8.1` — and never touches the compiler itself.

## Why a Mac app at all

Boris ships its own browser-based editor. Solipsist is the complementary **native desktop citizen**:

- **Native file access** — sandboxed, security-scoped bookmarks; real Mac open/save semantics across every project folder.
- **Mac integration** — windows, menus, keyboard, notifications, pasteboard, drag-and-drop.
- **A bundled, offline engine** — the `boris` binary ships inside the app (arm64, zero runtime deps); no server, no browser tab, no toolchain at runtime.
- **A publishing console** — GitHub Pages / Standard.site / Nostr workflows surfaced as native flows, not terminal commands.
- **No second stack** — the app never reimplements compiler semantics; it renders Boris’s JSON contracts (`manifest`, `graph`, `completion`, `build-report`, analysis reports) and drives `watch --serve` for preview.

## The non-negotiables

1. **Never touch the boris repo.** No commits, no edits, no pushes.
2. **Never reimplement Boris semantics in Swift.** The JSON contracts are the single source of truth; Swift only mirrors and renders them.
3. **Never silently ignore diagnostics or exit codes.** Surface them.
4. **The subprocess boundary is a feature.** Crash isolation, cancellation, never in-process Zig.
5. **Never mutate the user’s content tree** except as the direct result of an explicit save.

## Where we are

M0–M8 gates and the depth batch (first-run, filter, profile 1:1, publish family) are in. Next is a clean-Mac ship — see [[roadmap]].
