# A6 — HTML build-completion signal (`.boris-cache/manifest.json` as the marker)

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: S. Additive fields + documentation.

---

**Title:** Document `.boris-cache/manifest.json` as the HTML build-completion marker; add `completed_at` + `page_count`

## Summary

IR mode publishes `build-report.json` on every build — success *and* failure —
so a consumer gets a durable, parseable result artifact. HTML mode publishes
nothing comparable: a one-shot HTML build returns only an exit code and
stderr prose. A tool driving `boris` as a subprocess (a GUI preview, an
editor plugin) wants a deterministic "build finished, here are the results"
signal to know when to reload and which pages changed.

The good news: for incremental/watch builds, a completion marker already
exists de facto — it's just undocumented and missing two convenience fields.

## Verified behavior

- Plain `boris --html` (no `--incremental`, no `--watch`) writes **no**
  `.boris-cache/` directory at all.
- `--incremental` / `--watch` atomically write `<dist>/.boris-cache/manifest.json`
  (plus `heading-harvest.json`) via the staged publish path
  (`createFileAtomic` in `src/compile.zig` ~line 2044).
- A **failed** incremental build leaves the existing manifest **untouched**
  (verified: mtime and bytes unchanged). Only a successful publish replaces
  it — so its presence/mtime is already a genuine "last successful build"
  marker, not a "last attempt" marker.

Current shape (no timestamp, no summary):

```json
{
  "format_version": "boris-cache-v2-layout-rules",
  "entries": [
    {
      "entity_id": "agents/antigravity",
      "fingerprint": "bb01cd92…",
      "output_path": "agents/antigravity.html",
      "selected_layout": "layouts/main.html",
      "output_size": 9724,
      "output_digest": "a3649e09…"
    }
  ]
}
```

## Proposal

1. **Document the manifest as the normative completion marker.** New
   `docs/contracts/cache-manifest.md` (or a section in `html-output.md`)
   stating: written atomically on successful incremental/watch publish only;
   never rewritten on failure; consumers treat replacement as the completion
   signal; and the `fingerprint` diff between consecutive manifests is the
   exact changed-page set (enabling targeted preview reloads).
2. **Add two additive fields** so consumers don't poll mtimes or count
   entries:
   - `"completed_at": <unix_ms>` — wall-clock completion time of the publish
     (ephemeral metadata; fine in a cache file, unlike content artifacts).
   - `"page_count": <int>` — number of entries.
   Recommended placement: directly after `format_version`, before `entries`
   (keeps the big array last). Key order is asserted by existing tests, so
   pick one placement and make it stable.
3. **Note for consumers:** run with `--incremental` (or `--watch`) to receive
   the marker. `--incremental` is byte-identical output — free for one-shot
   builders that want the signal.

## Alternative (bigger, overlaps A5)

Publish a `build-report.json`-shaped completion report in HTML mode
(`ok` / `errorCount` / `diagnostics`). This additionally gives structured
diagnostics on failure — but it changes the HTML artifact set, overlaps the
A5 diagnostics work, and is a larger surface. Keep it as a follow-up;
the manifest-as-marker covers the reload/completion need today.

## Why this is not a compromise

The manifest already exists and is already atomic-on-success; we're asking to
document that contract and add two metadata fields to a cache file. HTML
outputs remain byte-identical. No exit-code, determinism, or artifact changes.

## Testing

- Existing incremental tests already assert manifest presence/content
  (`src/compile.zig` tests, `layout_select_hostile_test.zig` lines 664+).
- Add: a failed incremental build leaves the previous manifest
  byte-identical; goldens updated for `completed_at` + `page_count`.
- Note the existing test comment at `compile.zig` ~5466 ("Non-incremental
  builds do not write `.boris-cache/manifest.json`") — that behavior stays.

## Acceptance criteria

- [ ] `.boris-cache/manifest.json` carries `completed_at` + `page_count`
      after `format_version` on successful incremental/watch builds.
- [ ] Failed builds never rewrite the manifest (documented + tested).
- [ ] `docs/contracts/cache-manifest.md` (or equivalent) specifies the
      completion-marker contract and the fingerprint-diff changed-page rule.
