# Solipsist — Mission

**What we're trying to do, in one page.** Companion to
[BORIS-CAPABILITIES.md](BORIS-CAPABILITIES.md) (what the engine can do) and
[PLAN-MAC-APP.md](PLAN-MAC-APP.md) (how we build the app).

---

## The one-liner

**Solipsist is a native macOS application that turns Boris — the
graph-native publication compiler — into a first-class desktop authoring,
preview, and publishing environment.**

## The engine we harness

Boris is **not a Markdown-to-HTML converter**. It is a compiler: Markdown
(or Textile, or Cooklang) in → a validated Trunk/Satellite content graph →
deterministic contracted projections (HTML, JSON IR, RAG packs, context
bundles, llms.txt, RSS, sitemap, and live publication targets — GitHub
Pages, Standard.site/AT Protocol, Nostr). Its identity, quoted from its own
`STATUS.md`:

> "Boris is a graph-native publication compiler with multiple targets.
> Markdown in, a validated Trunk/Satellite graph, then one or more
> contracted projections. HTML `dist/` is the default target, not the whole
> product."

**We harness the `afterparty` integration line — v0.8.1 candidate
(`boris/0.8.1`), NOT `main`.** `main` is frozen; `afterparty` is where
everything current lives (the command-based CLI, `validate`, `watch
--serve`, `--timings`, `--version`, completion IR, publication targets,
themes, and the compiler's own editor). The boris repo is read-only for us:
we vendor its binary and file issues against it, nothing more.

## Why a Mac app at all (when boris now ships its own editor)

Boris now contains `boris-editor`: a loopback Zig host + Svelte browser
shell with a problems panel, graph-aware completion, live preview, and
publication-profile management. That is a browser surface living in the
compiler repo. Solipsist is the complementary **native desktop citizen**:

- **Native file access** — sandboxed, security-scoped bookmarks; real Mac
  open/save semantics across every project folder.
- **Mac integration** — windows, menus, keyboard, notifications, pasteboard,
  drag-and-drop, Spotlight/Touch Bar/Shortcuts where they earn their keep.
- **A bundled, offline engine** — the `boris` binary ships inside the app
  (arm64, zero runtime deps); no server, no browser tab, no toolchain at
  runtime.
- **A publishing console** — GitHub Pages / Standard.site / Nostr workflows
  surfaced as native flows, not terminal commands.
- **No second stack** — the app never reimplements compiler semantics; it
  renders boris's JSON contracts (`manifest`, `graph`, `completion`,
  `build-report`, analysis reports) and drives `watch --serve` for preview.

## The non-negotiables

1. **Never touch the boris repo.** No commits, no edits, no pushes. Issues
   are drafted in `docs/issues/` and filed as GitHub issues — nothing more.
2. **Never reimplement Boris semantics in Swift.** The JSON contracts are
   the single source of truth; Swift only mirrors and renders them.
3. **Never silently ignore diagnostics or exit codes.** Surface them.
4. **The subprocess boundary is a feature.** Crash isolation, cancellation
   via `Process.terminationReason`, never in-process Zig.
5. **Never mutate the user's content tree** except as the direct result of
   an explicit save.

## Where we are

- **M1 done (verified):** app shell runs the bundled engine and decodes the
  JSON contracts end-to-end. That spike ran against **main v0.8.0**; the
  baseline is now **afterparty v0.8.1 candidate** (base IR schema `0.2.0`
  unchanged, so the existing decoders still apply).
- **Big afterparty windfalls for the app:** `watch --serve` (loopback HTTP +
  SSE reload — preview is engine-owned, not app-owned), `build --report`
  (machine HTML diagnostics with `compilerId`), `completion.json` (editor
  completion surface), `--version` / `--timings` (identity + machine
  timing), and real publication targets.
- **Next:** re-baseline the issue drafts against afterparty (several are
  already done — see the reconciliation in
  [ENGINE-WORK-AND-DESIGN.md](ENGINE-WORK-AND-DESIGN.md)), then M2 (project
  open + sidebar) on the new baseline.

## What success looks like

Open any folder of Boris content on a Mac → the sidebar shows the real
graph (trunks, satellites, relations) from `graph.json` → edits validate
live against the engine with precise diagnostics → preview reloads through
the engine's own loopback server → publish to GitHub Pages or the AT
Protocol with native auth, with the compiler's evidence chain (Proof Pack)
attached. All of it driven by the compiler's contracts; none of it by
scraped prose or reimplemented logic.
