---
title: Solipsist
status: published
---

**Radio UserLand’s job in Mail’s body.**

Solipsist is a native macOS workstation for [Boris](https://github.com/drawmeanelephant/boris), the deterministic Zig graph-native publication compiler. Open a folder of Boris content, and the whole publishing loop — sources, graph, plan, build, preview, publish — lives in one Mail-grade window, driven by the compiler’s real contracts, never by a rewrite.

<div class="hero-actions">
  <a href="mission.html">Read the mission</a>
  <a href="roadmap.html">See the roadmap</a>
</div>

## What Solipsist gives you

<div class="feature-grid">
  <div class="feature-card">
    <h3>Mail-grade chrome</h3>
    <p>Sources on the left, the graph as a workable play list in the middle, the inspector drawer on the right — one window, real menus, real keyboard.</p>
  </div>
  <div class="feature-card">
    <h3>Subprocess isolation</h3>
    <p>Boris runs as an isolated subprocess. Compiler semantics are never reimplemented in Swift; the JSON contracts are the single source of truth.</p>
  </div>
  <div class="feature-card">
    <h3>Companion windows</h3>
    <p>Live preview powered by <code>watch --serve</code> and editing hosted in <code>boris-editor</code> — native shells around the engine’s own surfaces.</p>
  </div>
  <div class="feature-card">
    <h3>First-class verbs</h3>
    <p>Plan, Validate, Build, Check, Impact, and Stop are menu items, not terminal incantations — with diagnostics surfaced as a place, not a dump.</p>
  </div>
</div>

## A harness, not a rewrite

Boris is **not a Markdown-to-HTML converter**. It is a compiler: Markdown (or Textile, or Cooklang) in, a validated Trunk/Satellite content graph, deterministic contracted projections out. Solipsist never touches the compiler — it vendors the binary, renders the contracts, and hosts the surfaces the project will not rewrite. The non-negotiables that keep that boundary honest live in the [[mission]].

## Explore the project

- **[[mission]]** — why a native desktop citizen at all, and the five non-negotiables that keep the boundary honest.
- **[[architecture]]** — Swift 6 / SwiftUI chassis, the spatial model, and engine integration.
- **[[roadmap]]** — where we are, what v1 must (and must not) be, and the north star.
- **[[dogfood]]** — the Stunts: tiny Boris trees the app opens, inspects, and diagnoses.

The code is open on [GitHub](https://github.com/drawmeanelephant/solipsist). This site itself is a Boris publication — compiled by the very engine the app harnesses, and deployed to Cloudflare Pages.
