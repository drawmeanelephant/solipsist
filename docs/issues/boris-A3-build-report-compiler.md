# A3 — `compiler` field in `build-report.json`

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Additive field — no shape changes.

---

**Title:** Add `compiler` to `build-report.json` (artifact-identity consistency)

## Summary

Boris's machine artifacts are consistent about one thing: they say who made
them. `manifest.json`, `graph.json`, and the `check`/`impact` analysis report
all carry a `compiler` id. **`build-report.json` is the single exception** —
and it's the artifact written on *every* build, including failures:

| Artifact | Has `compiler`? |
|----------|-----------------|
| `manifest.json` | ✅ `"compiler": "boris/0.8.0"` (field 2, after `schemaVersion`) |
| `graph.json` | ✅ |
| `check` / `impact` analysis report | ✅ |
| `build-report.json` | ❌ |

The failure case is precisely where identity matters most: a build report
with diagnostics is read by a tool that wants to know *which compiler
produced this* — the engine it shipped, or a newer/older one that changed
behavior between versions. Without the field, the report's `schemaVersion` is
floating: the consumer has to guess whether the schema it's reading belongs
to the compiler it expected. This is a one-field hole in an otherwise
uniform identity contract.

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

## Why this is a strong decision for boris

One already-computed field, added in an existing renderer, restoring a
uniform property across every machine artifact. No behavior, exit-code, or
determinism change; the golden-output updates are mechanical. It hardens the
identity contract at the exact point (failure reports) where version skew is
most likely to be diagnosed.

## Testing

- Update build-report goldens (success + failure) to include `compiler`.
- Add an assertion that `build-report.compiler` equals `manifest.compiler`
  on a shared run (the consistency invariant above).

## Acceptance criteria

- [ ] `build-report.json` (success and failure) contains `compiler` as field
      2, matching `manifest.json`'s value on the same run.
- [ ] Existing IR artifacts otherwise byte-identical.
