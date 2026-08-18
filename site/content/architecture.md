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
┌──────────────────┬─────────────────────────────┬──────────────────┐
│ SOURCES          │ PLAY                        │ DRAWER           │
│ Local / GitHub   │ Graph, outputs, activity,   │ Profile, page    │
│                  │ reports                     │ fields, options  │
└──────────────────┴─────────────────────────────┴──────────────────┘
Companion windows: Preview (watch --serve) · Editor (boris-editor)
```

## Engine Integration

- `BorisEngine` actor manages single-process execution and signal handling (`SIGTERM`).
- Contract models decode normative Boris JSON formats.
- `Coordinator` maps UI verbs to engine invocations, reporting timings and problems in real-time.

## Process boundaries

The subprocess boundary is a feature, not an accident:

- The `boris` binary ships inside the app (arm64, zero runtime deps) and runs only as an isolated subprocess — crash isolation and cancellation without ever hosting Zig in-process.
- Swift never reimplements compiler semantics. The JSON contracts (`manifest`, `graph`, `completion`, `build-report`, analysis reports) are the single source of truth; the app mirrors and renders them.
- Diagnostics and exit codes are surfaced, never silently swallowed.

These boundaries are the architectural form of the [[mission]]’s non-negotiables, and they are the reason the graph shown in the play list is the *real* graph from `graph.json` — not a Swift reconstruction.
