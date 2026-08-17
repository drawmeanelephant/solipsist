# A3 — Compiler identity in the IR `build-report.json` (and the field-name zoo)

> **Filed: [boris#638](https://github.com/drawmeanelephant/boris/issues/638)**
> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P1. Size: XS. Additive field — no shape changes.
> **Rebaselined against afterparty v0.8.1.** The sharpening: afterparty's
> new `html-build-report-0.1.0` **has** the field; the IR
> `build-report.json` still **doesn't** — and the field has three different
> names across artifacts.

---

**Title:** Add compiler identity to IR `build-report.json`; consider unifying the field name

## Summary

Boris's machine artifacts are consistent about one thing: they say who made
them. On afterparty every artifact carries the compiler id — under three
different field names:

| Artifact | Field | Value (verified) |
|----------|-------|------------------|
| `manifest.json` | `compiler` | `boris/0.8.1` |
| `graph.json` | `compiler` | `boris/0.8.1` |
| `completion.json` | `compiler_id` | `boris/0.8.1` |
| `html-build-report-0.1.0` (`build --report`) | `compilerId` | `boris/0.8.1` |
| **IR `build-report.json`** | **—** | **absent (verified)** |

Two problems:

1. **The IR build-report omits identity entirely** — and it is the artifact
   written on *every* IR build, including failures, where identity matters
   most: a tool reading diagnostics wants to know *which compiler produced
   this* — the engine it shipped, or a newer/older one that changed behavior
   between versions. Every other artifact answers; this one is mute.
2. **The name is different everywhere it exists** — `compiler`,
   `compiler_id`, `compilerId`. Consumers cannot write one path to the
   identity; they must special-case per artifact. For a contract family that
   prides itself on uniformity, that is the kind of drift that hardens into
   a permanent ABI wart.

## Proposal

1. **Add the field to IR `build-report.json`**, immediately after
   `schemaVersion`, using the same helper the other IR artifacts use
   (`artifactCompilerId`), so it is *by construction identical* to
   `manifest.json`'s value (including the `+`-suffixed semantic/Cooklang
   variants when present):

   ```json
   {
     "schemaVersion": "0.2.0",
     "compiler": "boris/0.8.1",
     "ok": true,
     "contentRoot": "content",
     "outDir": ".boris",
     "pageCount": 25,
     "errorCount": 0,
     "diagnostics": []
   }
   ```

2. **Decide the field name deliberately** — recommend unifying on
   `compiler` (the name the two core IR artifacts already use) everywhere,
   or on `compilerId` (the name the HTML report uses) everywhere. Either
   choice is fine; the triplicate is not. If renaming existing fields is
   too disruptive, at minimum document the per-artifact names as a table in
   `docs/contracts/` so consumers can key off one lookup.

3. **No `schemaVersion` bump** for the additive IR field (consumers already
   parse with `ignore_unknown_fields` tolerance). A name unification that
   *renames* existing fields would be a separate, versioned decision.

## Why this is a strong decision for boris

- The consistency argument is now sharper than ever: on a single build,
  boris emits four identity-bearing artifacts and one mute one. Restoring
  uniformity at the failure artifact is a one-field change in an existing
  renderer; no behavior, exit-code, or determinism impact.
- The naming zoo is exactly the kind of thing a contract-first project
  should kill while it is still three artifacts wide, not thirty.
- It hardens the version-skew story: a consumer can now assert
  `build-report.compiler == manifest.compiler` on every run, including
  failed ones.

## Testing

- Update build-report goldens (success + failure) to include the field.
- Add an assertion that `build-report.compiler` equals `manifest.compiler`
  on a shared run.
- Extend the existing `test-version-pin` recipe to cover the IR
  build-report (it already covers manifest + completion).

## Acceptance criteria

- [ ] IR `build-report.json` (success and failure) carries the compiler id,
      matching `manifest.json`'s value on the same run.
- [ ] A decision recorded on the field name (unify vs document-as-is).
- [ ] Existing IR artifacts otherwise byte-identical.
