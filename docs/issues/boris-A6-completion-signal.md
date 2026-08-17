# A6 — HTML build-completion signal (`.boris-cache/manifest.json` as the marker)

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: S. Additive fields + documentation.

---

**Title:** Document `.boris-cache/manifest.json` as the HTML build-completion contract; add `completed_at` + `page_count`

## Summary

Boris's core promise is deterministic, **atomic** builds: a consumer should
never have to wonder whether an output tree is complete. IR mode makes that
observable — `build-report.json` is published on every build, success *and*
failure. HTML mode makes it observable only by accident. A one-shot HTML
build returns exit code + stderr prose; the durable record of what was built
lives in `.boris-cache/manifest.json` — an artifact already listed in
`--help`, already written atomically on success only, but **undocumented and
missing the two fields that make it consumable as a completion signal**.

Any tool that drives HTML builds — incremental deploy scripts that need "the
exact set of changed pages since last build", editors that reload previews,
CI that wants a parseable build record — currently has to poll mtimes and
reverse-engineer the manifest format. The manifest is already a public
artifact; the ask is to make it a *contract*.

## Verified behavior

- Plain `boris --html` (no `--incremental`, no `--watch`) writes **no**
  `.boris-cache/` directory at all.
- `--incremental` / `--watch` atomically write `<dist>/.boris-cache/manifest.json`
  (plus `heading-harvest.json`) via the staged publish path
  (`createFileAtomic` in `src/compile.zig` ~line 2044).
- A **failed** incremental build leaves the existing manifest **untouched**
  (verified: mtime and bytes unchanged). Only a successful publish replaces
  it — so its presence/mtime is already a genuine "last successful build"
  marker, not a "last attempt" marker. That is a real, testable guarantee
  that simply isn't written down.

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

1. **Document the manifest as the normative completion contract.** New
   `docs/contracts/cache-manifest.md` (or a section in `html-output.md`)
   stating: written atomically on successful incremental/watch publish only;
   never rewritten on failure; consumers treat replacement as the completion
   signal; and the `fingerprint` diff between consecutive manifests is the
   exact changed-page set — which makes targeted, incremental deploys and
   preview reloads a pure read of a JSON file.
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
the manifest-as-contract covers the completion/change-detection need today.

## Why this is a strong decision for boris

It makes atomicity *observable*: the guarantee "a successful build is
atomically published" becomes a documented, field-complete, machine-readable
record instead of a property consumers must discover by experiment. It costs
two metadata fields on an internal cache file, changes no HTML output, and
unlocks a legitimate class of consumers (incremental deployers, preview
tools) that today either poll the filesystem or re-run full builds.

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
      completion contract and the fingerprint-diff changed-page rule.
