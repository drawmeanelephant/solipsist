---
title: Solipsist
status: published
---

**Radio UserLand’s job in Mail’s body.**

Solipsist is a native macOS workstation for [Boris](https://drawmeanelephant.github.io/boris/), the deterministic Zig graph-native publication compiler. Open a folder of Boris content, and the whole publishing loop — sources, graph, plan, build, preview, publish — lives in one Mail-grade window, driven by the compiler’s real contracts, never by a rewrite.

<div class="hero-actions">
  <a href="mission.html">Read the mission</a>
  <a href="roadmap.html">See the roadmap</a>
</div>

## What Solipsist gives you

<div class="feature-grid">
  <div class="feature-card">
    <h3>Mail-grade chrome</h3>
    <p>Sources in Settings, mailboxes on the left, a reading pane in the middle, the inspector drawer on the right — one window, real menus, real keyboard.</p>
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

## The stack

Solipsist is the top of a three-project stack. Each project has its own docs site and repository:

| Project | What it is | Docs | Code |
|---------|------------|------|------|
| **Oliver** | Freestanding Zig markup library — Markdown, Textile, and Cooklang into a typed document and deterministic HTML. Library, CLI, and C ABI. | [Oliver docs](https://drawmeanelephant.github.io/oliver/) | [GitHub](https://github.com/drawmeanelephant/oliver) |
| **Boris** | Graph-native publication compiler built on Oliver — Markdown into a validated Trunk/Satellite graph, then HTML, JSON IR, RAG packs, and publication targets. | [Boris docs](https://drawmeanelephant.github.io/boris/) | [GitHub](https://github.com/drawmeanelephant/boris) |
| **Solipsist** | Native macOS workstation that drives Boris as a subprocess — this site. | [Solipsist docs](index.html) | [GitHub](https://github.com/drawmeanelephant/solipsist) |

Want to write a site from the command line? Start with [Getting started](https://drawmeanelephant.github.io/boris/getting-started.html) in the Boris docs. Want a markup library to embed? Read the [Oliver docs](https://drawmeanelephant.github.io/oliver/). Want a Mac app around the whole loop? Keep reading here.

## Explore the project

- **[[mission]]** — why a native desktop citizen at all, and the five non-negotiables that keep the boundary honest.
- **[[architecture]]** — Swift 6 / SwiftUI chassis, the spatial model, and engine integration.
- **[[roadmap]]** — where we are, what v1 must (and must not) be, and the north star.
- **[[dogfood]]** — the Stunts: tiny Boris trees the app opens, inspects, and diagnoses.

The code is open on [GitHub](https://github.com/drawmeanelephant/solipsist). This site itself is a Boris publication — compiled by the very engine the app harnesses, and deployed to Cloudflare Pages.
