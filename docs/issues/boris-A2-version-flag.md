# A2 — `--version` flag

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P0. Size: XS. Additive, read-only.

---

**Title:** Add `--version` flag (prints compiler id, exits 0)

## Summary

There is no way to ask the binary its own version. `manifest.json` carries
`compiler: boris/0.8.0`, but a consumer needs the engine version *before*
running a build — About screen, engine-update checks, and schema-compatibility
gating all want a one-shot answer.

## Proposal

`boris --version` prints the compiler id and exits 0:

```
$ boris --version
boris/0.8.0
```

- Printed to **stdout** (single line, no trailing prose) — the one deliberate
  use of stdout, so scripts can capture it cleanly.
- Exits **0** without scanning content or writing artifacts — same
  short-circuit rule as `--help` (exit-code contract rule 4 in
  `docs/contracts/diagnostics.md`).
- The value is already a constant: `pipeline.compiler_id` (`src/pipeline.zig`,
  `"boris/0.8.0"`). Decide explicitly whether `--version` prints the plain
  product id (`boris/0.8.0`) or the semantic-relations variant
  (`boris/0.8.0+semantic-relations`); recommend the plain compiler id.

## Optional follow-up (separate concern, not required for this issue)

A machine-readable form for consumers that also need the IR schema version for
gating:

```
$ boris --version --json
{"compiler":"boris/0.8.0","version":"0.8.0","ir_schema_version":"0.2.0"}
```

Add only if there's appetite — the plain `--version` is the complete minimal
ask.

## Why this is not a compromise

A standard, read-only flag. Zero impact on compilation, determinism, exit
codes, or any artifact. Note that `boris package` already writes
`MACHINE-READABLE-VERSION.json`, but that requires running a package build;
`--version` is the cheap, standard path.

## Testing

- CLI parse test: `--version` parses as a standalone flag and short-circuits
  (no content scan).
- Run test: stdout is exactly `boris/0.8.0\n`, exit 0, no artifacts written.
- Help text updated to list `--version` next to `-h, --help`.

## Acceptance criteria

- [ ] `boris --version` prints `boris/<version>` on stdout and exits 0.
- [ ] No content is scanned and no artifacts are written.
- [ ] `--version` appears in `--help`.
