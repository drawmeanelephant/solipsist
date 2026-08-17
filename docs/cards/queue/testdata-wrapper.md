# Q16 — testdata wrapper

**Owns:** `scripts/stunt-from-testdata.sh`.

If `boris-testdata` exists next to the kit `boris`, generate a 4-page
`readme-realistic-v1` tree into `/tmp` (never into git) and print the
path. `--force` not on a repo path. Gate: script runs or exits 0 with
“no testdata binary”.
