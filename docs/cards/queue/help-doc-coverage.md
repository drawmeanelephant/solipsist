# Q25 — Help doc coverage audit

**Owns:** `docs/help.md`, and `Sources/App/Commands.swift` **read-only**
(flag anything you can't fix).

The shortcuts were corrected in #37 (`⌘⇧P`/`⌘⇧E`), but the bundled guide
should document **every** menu verb, not just the companion windows.
Audit `Sources/App/Commands.swift` against `docs/help.md`:

- Every `Button` with a `.keyboardShortcut` appears in the guide with the
  same key
- Plan / Validate / Build / Check / Impact / Stop are all listed with
  their `⌘`-equivalents
- File → Open… / New Project… are mentioned if present
- The Help window itself is documented (⌘? per Commands.swift)

Fix only `docs/help.md`. If a menu item is missing from the guide, add a
line; do not change `Commands.swift`.

Gate: every `.keyboardShortcut` in `Commands.swift` has a matching
documented entry in `docs/help.md`.
