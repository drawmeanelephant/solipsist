---
title: Architecture
parent: index
status: published
tags: [architecture]
---

# Architecture

Solipsist is built in Swift 6 with SwiftUI for macOS 14+.

## Spatial Model

```
Settings → Sources (the account book)

┌──────────────────┬─────────────────────────────┬──────────────────┐
│ MAILBOXES        │ READING                     │ DRAWER           │
│ Source as        │ Message list + reading      │ Profile, page    │
│ account header   │ pane for the selected page  │ fields, options  │
└──────────────────┴─────────────────────────────┴──────────────────┘
Companion windows: Preview (full site) · Editor (boris-editor)
```

M2–M8 shipped a flatter cut (source list + tabbed play). M10 is the
recut to the diagram above.

## Engine Integration

- `BorisEngine` actor manages single-process execution and signal handling (`SIGTERM`).
- Contract models decode normative Boris JSON formats.
- `Coordinator` maps UI verbs to engine invocations, reporting timings and problems in real-time.

## Process boundaries

The subprocess boundary is a feature, not an accident:

- The `boris` binary ships inside the app (arm64, zero runtime deps) and runs only as an isolated subprocess — crash isolation and cancellation without ever hosting Zig in-process.
- Swift never reimplements compiler semantics. The JSON contracts (`manifest`, `graph`, `completion`, `build-report`, analysis reports) are the single source of truth; the app mirrors and renders them.
- Diagnostics and exit codes are surfaced, never silently swallowed.

These boundaries are the architectural form of the [[mission]]’s non-negotiables, and they are the reason the graph shown in the reading place is the *real* graph from `graph.json` — not a Swift reconstruction.
