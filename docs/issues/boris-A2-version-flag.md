# A2 — `--version` flag — WITHDRAWN (already shipped on afterparty)

> **Do not file.** This draft was written against boris `main` v0.8.0, which
> had no version query. The afterparty line (v0.8.1 candidate) already
> implements it. Kept as a record so nobody re-files it.

---

**Original ask:** `boris --version` prints the compiler id and exits 0.

**Shipped evidence (afterparty, verified 2026-08-17):**

- `boris --version` → `boris/0.8.1`, exit 0, no content scan; `-V` alias.
- Documented in `docs/contracts/cli.md` § Version query.
- Pinned by the `zig build test-version-pin` black-box test: must print
  exactly `pipeline.compiler_id`, and real artifact sets (plain, Cooklang,
  semantic-relations corpora) must record the base or `+`-suffixed variant
  id in `manifest.json` and `completion.json`; a tampered id is rejected.

**Also shipped alongside (related asks):**

- **A8 (`boris init`)** — `boris init [DIR]` exists (starter site + theme +
  publication profile; refuses to clobber non-empty dirs). Withdrawn.
- **A9 (check exit-code granularity)** — the recommended opt-in landed:
  `check` exits 0 with findings by default; `--fail-on-unreferenced`
  → exit 1 for CI. Withdrawn.

**What this taught us:** before filing anything against boris, verify
against the **afterparty** line — `main` is frozen and trails the real
surface by hundreds of commits.
