# Card — Siri drafts posts (App Intents + Foundation Models) ✅

**Milestone:** M18 · **Lane:** `Sources/Intents/` (+ compose save seam).
macOS 27 only: deployment target moves to 27.0 in the same PR.

**Landed** — PR [#294](https://github.com/drawmeanelephant/solipsist/pull/294).
Journal-schema `DraftPostIntent` + on-device FoundationModels
session; File → New Draft with Apple Intelligence…; macOS 27 target.

The new Siri speaks App Intents — SiriKit is dead, so an intent is the
only door. The on-device model drafts; **compose stays the review
surface**; nothing touches the content tree until an explicit ⌘S.

## Owns

- `Sources/Intents/StagedPostDraft.swift` — plain staged data + slug +
  canonical frontmatter assembly (`ComposeFrontmatter.apply`)
- `Sources/Intents/DraftRouter.swift` — deferred-delivery handoff
  (same pattern as `AppDelegate.openFolder`)
- `Sources/Intents/PostDraftEngine.swift` — FoundationModels session,
  guided generation, typed unavailability errors
- `Sources/Intents/DraftPostIntent.swift` — `DraftPostIntent` +
  `AppShortcutsProvider` (“Draft a post in Solipsist …”); adopts the
  journal-domain **`createEntry` schema** (`@AppIntent(schema:)`) so
  Apple Intelligence routes entry requests here; `supportedModes =
  [.foreground]` (openAppWhenRun is deprecated since macOS 26); the
  File-menu path donates via `donateQuietly()` so suggestions track
  real usage
- `StagedDraftEntity` / `StagedDraftQuery` — the schema-required
  journal entity; transient by design, resolves nothing after the fact
- `Sources/Intents/PostDraftPrompt.swift` — File-menu topic prompt
- File verb in `Commands.swift`; compose staged-draft mode + save panel

## Boundaries honored

1. **No boris repo touch, no semantics reimplemented** — frontmatter is
   emitted through the repo's own closed-key emitter; `id` / `parent` /
   `status` are left absent for the author's front-matter pane.
2. **Boundary 4** — staging is memory-only; Save routes through
   `ComposeSaveFlow` exactly like every other write.
3. **Boundary 3** — model unavailable / failed = alert, never silent.
4. Subprocess boundary untouched; the model call is not a Boris verb.

## Do not

- Let Siri write files directly (no autosave path)
- Invent frontmatter keys or graph semantics to make drafting easier
- Put an HTTP model client in the app (on-device model only)
- Grow `MainWindow` for this

## Gate

“Hey Siri, draft a post in Solipsist about …” → Solipsist comes
forward, Compose shows an untitled buffer with assembled frontmatter,
status bar says *edited*; ⌘S asks where to save; cancel keeps the
staged buffer. Same flow from `File → New Draft with Apple
Intelligence…`. Apple Intelligence off → alert names it.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
