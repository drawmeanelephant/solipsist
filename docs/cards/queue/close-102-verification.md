# Close #102 — verify the editor gate, then close

**Issue:** [#102](https://github.com/drawmeanelephant/solipsist/issues/102) (M10-4 "editor from the selected page")
**Status:** code merged (PR #118) · CI green · **hands-on Gate NOT yet verified**
**Blocked on:** a live `boris` engine binary — none exists in this checkout.

## Context (what is already done)

- `File → Edit Page` (enabled when `store.selection.canEditPage`) — merged.
- Editor header shows the selected page title + `sourcePath` — merged.
- Editor nav chrome (back/forward/reload, phase indicator, Restart Host) — merged.
- Double-click / Return gestures + `noun.sourcePath` write — landed via **#101** (PR #113).
- Toolbar page-gating — landed via #100.
- Build + `make test` (199 tests) green on `main`.

**What remains is the card Gate, run live, then the close ceremony.** Do not change code unless the Gate reveals a real bug — if it does, stop and report it (the queue's forbidden paths are `Sources/Play/`, `Inspector/`, `Engine/`, `Models/`, `Commands.swift`, `MainWindow.swift`, `Workspace/`, `embed-boris.sh`).

## Prerequisites

macOS 26+ host (dev box is macOS 27) · Xcode 26/27 · Zig 0.16+ · node/npm (for the Svelte shell).

## Step 1 — Build the engine + editor host at the pinned commit

Pin: `6b930b7bd35a1803b365a073c226df22631dc3f7` (also in `vendor/boris-agent-kit/MANIFEST.json`).

```bash
git clone https://github.com/drawmeanelephant/boris.git ../boris
cd ../boris
git checkout 6b930b7bd35a1803b365a073c226df22631dc3f7
zig build                                  # engine  -> zig-out/bin/boris
zig build --build-file editor/build.zig    # host    -> boris-editor binary
cd editor/ui && npm ci && npm run build    # Svelte shell
cd ../..
```

Both binaries should end up in `../boris/zig-out/bin/` (siblings), so the app finds
`boris-editor` next to `boris`. If the editor host lands elsewhere, set
`SOLIPSIST_BORIS_EDITOR_BIN` to its absolute path.

## Step 2 — Build and launch the app

```bash
SKIP_EMBED_BORIS=1 make build
SOLIPSIST_BORIS_BIN=$PWD/../boris/zig-out/bin/boris \
SOLIPSIST_BORIS_EDITOR_BIN=$PWD/../boris/zig-out/bin/boris-editor \
  open build/Build/Products/Debug/Solipsist.app
```

Engine search order: `SOLIPSIST_BORIS_BIN` → app bundle → `SUPPORT-NOT-FOR-GITHUB/…`
→ `../boris/zig-out/bin/boris`. Editor binary: `SOLIPSIST_BORIS_EDITOR_BIN` →
sibling of the engine → app bundle.

## Step 3 — Verify the Gate (from `docs/cards/M10-editor-wiring.md`)

1. **File → Open…** `Stunts/happy`. Pages render (engine builds the graph).
2. **Select a page** →
   - `File → Edit Page` opens the editor companion window.
   - The window header shows the page **title** and its **sourcePath**.
   - **Double-click** a row and press **Return** also open the editor (#101 behavior).
3. **No page selected / no source** → `Edit Page` is disabled.
4. Inside the editor:
   - link-out still works (WKWebView/CSP fallback).
   - paste-`BORIS_EDITOR_URL=` fallback still connects.
   - **Restart Host** re-spawns the host and reconnects.
5. Close the editor → the host process is SIGTERM'd.

## Step 4 — Close out

Post a comment on #102 summarizing the final lane split, then close it if the Gate
passed:

- **#100** — toolbar gate + `sourcePath` on the noun type
- **#101** — double-click / Return gestures + `noun.sourcePath` write (PR #113)
- **#102** — `File → Edit Page` verb + editor header (title + sourcePath) + nav chrome (PR #118)
- **A15** — editor open-file deep link deliberately **not** drafted per M10-4; `boris#649`
  filed upstream for a later milestone.

## Acceptance checklist

- [ ] `../boris` at pin builds; `boris` + `boris-editor` binaries exist
- [ ] App launches against `Stunts/happy` and Pages render
- [ ] `Edit Page` opens the editor with page title + `sourcePath` in the header
- [ ] `Edit Page` disabled when no page is selected
- [ ] double-click and Return open the editor
- [ ] link-out, paste fallback, and Restart Host behave
- [ ] `SKIP_EMBED_BORIS=1 make build` + `make test` green on the final tree
- [ ] #102 closed with the summary comment

## Gotchas

- First `zig build` takes a few minutes.
- If the pinned commit fails to build with the local Zig, report the exact error —
  **do not patch boris** (draft `docs/issues/boris-A<N>-*.md` instead).
- macOS floor is **26.0** (Liquid Glass); the `xcode-27` CI runner is macOS 26.5.2.
