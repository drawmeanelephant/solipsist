# Boris issues (consumer access)

Ready-to-paste drafts. File on `drawmeanelephant/boris`. Never open a
PR against boris from this repo.

**Already merged on afterparty** (in the `6b930b7` kit pin):

- A3 [boris#638](https://github.com/drawmeanelephant/boris/issues/638) → [#643](https://github.com/drawmeanelephant/boris/pull/643)
- A4 [boris#639](https://github.com/drawmeanelephant/boris/issues/639) → [#642](https://github.com/drawmeanelephant/boris/pull/642)
- A13 [boris#640](https://github.com/drawmeanelephant/boris/issues/640) → [#641](https://github.com/drawmeanelephant/boris/pull/641)
- A1 [boris#644](https://github.com/drawmeanelephant/boris/issues/644) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A14 [boris#645](https://github.com/drawmeanelephant/boris/issues/645) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A7 [boris#646](https://github.com/drawmeanelephant/boris/issues/646) → [#648](https://github.com/drawmeanelephant/boris/pull/648)

**Filed (2026-08-17):**

- A5 [boris#647](https://github.com/drawmeanelephant/boris/issues/647) — RFC, filed as an issue (Discussions disabled on the repo). Still open; no fixing PR yet.

**Filed (2026-08-18):**

- A15 [boris#649](https://github.com/drawmeanelephant/boris/issues/649) — optional `#token=…&open=<project-relative path>` fragment. Afterparty's Svelte shell still reads only `token` (`URLSearchParams` on the hash) and opens files via `POST /api/files/open`. Extra fragment keys are ignored today. Solipsist appends `open=` from the selected page's `sourcePath` (mapped `index.md` → `content/index.md`, same rules as `file_api.validatePath`) so Edit Page lands on the file when A15 ships. Do not invent a different query/fragment.

**File next:** none.

Do not ask: unifying `compiler` field names, library mode, relaxing
editor token/CSP, shipping `boris-editor` in the agent-pack.
