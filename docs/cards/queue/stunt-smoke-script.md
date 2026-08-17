# Q1 — Stunt smoke script

**Owns:** `scripts/stunt-smoke.sh` only.

Run kit `boris` against `Stunts/happy` (IR + validate + plan) and
assert happy IR `ok: true`, broken-frontmatter `EFRONTMATTER`,
broken-parent `EPARENTMISSING`. Skip with exit 0 if no binary.
Do not write into Stunts. Gate: script exits 0 with kit present.
