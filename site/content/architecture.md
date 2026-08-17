---
title: Architecture
parent: index
status: published
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
