# A3 — `compiler` field in `build-report.json`

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Additive field — no shape changes.

---

**Title:** Add `compiler` to `build-report.json` (mirror `manifest.json`)

## Summary

`build-report.json` is the artifact a consumer decodes on **every** IR build —
including failed ones, where it carries the diagnostics. But it is the only
machine artifact that doesn't say *which engine* produced it:

| Artifact | Has `compiler`? |
|----------|-----------------|
| `manifest.json` | ✅ `"compiler": "boris/0.8.0"` (field 2, after `schemaVersion`) |
| `graph.json` | ✅ |
| `check` / `impact` analysis report | ✅ |
| `build-report.json` | ❌ |

On a failed build — precisely the case where an app wants to know "was this
produced by the engine I shipped, or a newer/older one?" — the report is
silent. Schema-compatibility gating (does this report's `schemaVersion` belong
to the compiler we expect?) has nothing to key on.

## Proposal

Add one field to `renderBuildReport` (`src/ir_emit.zig`), immediately after
`schemaVersion`, mirroring `manifest.json`'s field order:

```json
{
  "schemaVersion": "0.2.0",
  "compiler": "boris/0.8.0",
  "ok": true,
  "contentRoot": "content",
  "outDir": ".boris",
  "pageCount": 45,
  "errorCount": 0,
  "diagnostics": []
}
```

- Value comes from the existing `artifactCompilerId(result, versions)`
  helper — the same call `renderManifest` and `renderGraph` use — so the
  field is **by construction identical** to `manifest.json`'s `compiler`
  (including the `boris/0.8.0+semantic-relations` variant when semantic
  relations are present). Consumers can rely on the invariant
  `build-report.compiler == manifest.compiler`.
- `schemaVersion` bump: **recommend no bump.** The field is additive and the
  IR shape is unchanged; consumers already parse with
  `ignore_unknown_fields`-style tolerance (e.g. `ParsedCacheManifest` in
  `src/compile.zig`). Final call is yours — an additive-field bump would be
  defensible, just costly for every downstream consumer.

## Why this is not a compromise

One already-computed field, added in an existing renderer, on a
Boris-versioned artifact. No behavior, exit-code, or determinism change; the
golden-output updates are mechanical.

## Testing

- Update build-report goldens (success + failure) to include `compiler`.
- Add an assertion that `build-report.compiler` equals `manifest.compiler`
  on a shared run (the consistency invariant above).

## Acceptance criteria

- [ ] `build-report.json` (success and failure) contains `compiler` as field
      2, matching `manifest.json`'s value on the same run.
- [ ] Existing IR artifacts otherwise byte-identical.
