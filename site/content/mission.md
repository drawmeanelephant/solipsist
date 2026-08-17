---
title: Mission
parent: index
status: published
---

# Mission

Solipsist is built to provide an uncompromising, native desktop harness for authoring, inspecting, coordinating, and broadcasting Boris-powered publications.

## Principles

1. **Never touch the compiler**: Boris remains a separate, deterministic compiler binary written in Zig.
2. **Decode versioned JSON contracts**: Every visual element derives from typed IR contracts (`manifest.json`, `graph.json`, `completion.json`, `build-report.json`).
3. **No third settings store**: The publication profile (`boris.json`) is the single source of truth for build configuration.
4. **Subprocess isolation**: Compiles and validation runs execute as supervised subprocesses with strict cancellation semantics.
