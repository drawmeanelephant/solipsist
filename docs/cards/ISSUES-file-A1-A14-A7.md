# Card — File remaining Boris issues

**Lane:** paste into GitHub on `drawmeanelephant/boris`. No `Sources/`
edits. Do not commit to the boris repo; do not open a PR.

GitHub was down. Drafts are ready. Bodies are the source of truth:

1. [A1](../issues/boris-A1-watch-events.md) — `--watch-json` +
   `serve-started` (port/url/helper). Flagship.
2. [A14](../issues/boris-A14-editor-launch-contract.md) — pin
   `BORIS_EDITOR_URL=`; SIGTERM/SIGINT exit 0. No CSP/token change.
3. [A7](../issues/boris-A7-workspace-rule.md) — document containment +
   IR absolute-`--out` quirk.

Then, as a **discussion**, not a patch: [A5](../issues/boris-A5-check-watch-rfc.md).

## Do not file

Unifying `compiler` field names, library mode, relaxing editor
security, agent-pack shipping `boris-editor`, `plan --out`.

## Gate

Three issues exist on boris with the draft titles. Record the numbers
at the top of each draft and in `docs/issues/README.md`, same way
A3/A4/A13 are recorded (`#638/#639/#640`, merged `#643/#642/#641`).
