# Solipsist — Mission

**What we're trying to do, in one page.** Companion to
[BORIS-CAPABILITIES.md](BORIS-CAPABILITIES.md) (what the engine can do) and
[ROADMAP.md](ROADMAP.md) (goals and milestones).

---

## The one-liner

**Solipsist is a native Mac harness for Boris:** Radio UserLand’s job in
Mail’s body. It turns the graph-native publication compiler into a
one-window workstation for sources (in Settings), mailboxes, a reading
place, inspection, preview, and broadcast — and it refuses to invent
anything the HIG or a Boris contract already named.

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

- **M0–M11 landed.** Spike, chassis, list, verbs, preview/editor,
  outputs, publish family, first-run, filter, profile 1:1,
  `recipe-scale`, ship pipeline (#78), Mail body
  ([#98](https://github.com/drawmeanelephant/solipsist/issues/98) —
  Settings, mailboxes, reading, compose #106), prove (#123).
  Remaining **ship** is Apple-account only (#110 / #111).
  Next **product cut:** M12 clone
  ([#131](https://github.com/drawmeanelephant/solipsist/issues/131)).
  Then M13 graph folders and M14 watch contract. Sequence:
  [ROADMAP.md](ROADMAP.md) §8.
- **Engine baseline:** afterparty `boris/0.8.1`. Kit pin `bf464a0`
  (contains A1/A14/A7 + A3/A4/A13 + A15 `open=` + A5 `validate --watch`).
- Roadmap **P** is withdrawn — the public site ships via Cloudflare
  Pages (`site/`).

## What success looks like

Open any folder of Boris content on a Mac — or clone a URL into one
— → it is a **source** in Settings → it appears as an account with
mailboxes (Pages folders from the graph) → the reading place shows
the graph as messages and a pane for the selected page → the
drawer shows the profile and that page → Plan / Validate / Build
surface every diagnostic → Preview reloads through `watch --serve`
(A1 events, not a port regex) → Edit hosts `boris-editor` →
Compose is the native buffer → publish to GitHub Pages,
Standard.site, or Nostr with the Proof Pack attached. All of it
driven by the compiler's contracts; none of it by scraped prose or
reimplemented logic.
