# Editor: Compose Toolbar Save Must Suspend Preview Watch

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#231](https://github.com/drawmeanelephant/solipsist/issues/231)
**Lane:** `Sources/Compose/`

## Problem

The toolbar Save button writes the file **before** the preview watch is
suspended, so Boris can read a partially-written file and trigger a rebuild
mid-write. The fix is a one-line change: route the toolbar through the
window's save flow instead of saving directly.

## Verified current state (read these two files before changing anything)

`Sources/Compose/ComposeEditorView.swift` — the toolbar Save button:

```swift
Button {
    do {
        saveError = nil
        if try document.save() {
            onSave?()
        }
    } catch {
        saveError = error.localizedDescription
    }
} label: {
    Label("Save", systemImage: "square.and.arrow.down")
}
.keyboardShortcut("s", modifiers: .command)
.disabled(!document.isDirty)
```

`Sources/Compose/ComposeWindow.swift` — the host wires `onSave: save`, and
`save()` is the correct tree-writing flow:

```swift
private func save() {
    saveStatus = nil
    do {
        runtime.coordinator.beginTreeWrite()
        defer { runtime.coordinator.endTreeWrite() }
        guard try document.save() else { return }
        runtime.coordinator.noteSave()
        saveStatus = "Saved · queued validate"
    } catch {
        saveStatus = error.localizedDescription
    }
}
```

**The bug, precisely:** the toolbar calls `document.save()` first — an
**unsuspended** write — then calls `onSave?()` → `save()`, which suspends the
watch and calls `document.save()` again (a no-op because `isDirty` is already
false). So today the file is written exactly once, but **outside** the
`beginTreeWrite()` / `endTreeWrite()` window. The window's own `save()` is
already correct; only the toolbar bypasses it.

## Scope

### Must land

- The toolbar Save button must **not** call `document.save()` directly. It
  calls `onSave?()` only, which flows through `ComposeWindow.save()` and the
  `beginTreeWrite()` / `endTreeWrite()` window:
  ```swift
  Button {
      onSave?()
  } label: {
      Label("Save", systemImage: "square.and.arrow.down")
  }
  .keyboardShortcut("s", modifiers: .command)
  .disabled(!document.isDirty)
  ```
- **Error surfacing moves.** Today the toolbar catches save errors into
  `saveError` (inline red text). Routing through `save()` moves failures to
  `saveStatus` in the status bar, which already renders red on failure
  (`ComposeWindow.statusBar`). Decide one surface and remove the other —
  `saveStatus` is the single source of truth; delete the toolbar's `saveError`
  state and its red text.
- Toolbar Save stays disabled when `!document.isDirty` (already true — keep).

### Must not land

- A second `beginTreeWrite()` / `endTreeWrite()` pair (one pair in `save()`
  is correct; nested pairs are redundant).

## Gate

With a Compose document open and the preview watch running, click the toolbar
Save → the file is written **exactly once**, inside
`beginTreeWrite()`/`endTreeWrite()` (assert via the coordinator's tree-write
state during the write) → `noteSave()` is queued → the watch does not rebuild
mid-write → save errors appear in the status bar. `SKIP_EMBED_BORIS=1 make
build` + `make test` green.

## Tests

- `testToolbarSaveWritesInsideTreeWrite` — the save path calls
  `beginTreeWrite()` before the write and `endTreeWrite()` after.
- `testToolbarSaveWritesOnce` — `document.save()` runs exactly once per Save
  (no double write).
- `testToolbarSaveQueuesValidation` — `noteSave()` is called after the write.

## Edge cases

- Watch already suspended → `beginTreeWrite()` is idempotent; no failure.
- No watch running → `beginTreeWrite()` is a no-op; no failure.
- Write fails → the `defer` in `save()` guarantees `endTreeWrite()` runs; the
  error shows in `saveStatus`.
