# Boris issues (consumer access)

Ready-to-paste drafts. File on `drawmeanelephant/boris`. Never open a
PR against boris from this repo.

**Already merged on afterparty** (in the `bf464a0` kit pin):

- A3 [boris#638](https://github.com/drawmeanelephant/boris/issues/638) → [#643](https://github.com/drawmeanelephant/boris/pull/643)
- A4 [boris#639](https://github.com/drawmeanelephant/boris/issues/639) → [#642](https://github.com/drawmeanelephant/boris/pull/642)
- A13 [boris#640](https://github.com/drawmeanelephant/boris/issues/640) → [#641](https://github.com/drawmeanelephant/boris/pull/641)
- A1 [boris#644](https://github.com/drawmeanelephant/boris/issues/644) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A14 [boris#645](https://github.com/drawmeanelephant/boris/issues/645) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A7 [boris#646](https://github.com/drawmeanelephant/boris/issues/646) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A15 [boris#649](https://github.com/drawmeanelephant/boris/issues/649) → [#650](https://github.com/drawmeanelephant/boris/pull/650) — optional `#token=…&open=<project-relative path>` fragment; the shell opens that author-owned file on launch (UI-only; the host still prints the token-only launch line). Solipsist's `EditorURL.opening` already appends `open=` from `sourcePath` — #160 is verify-only.
- A5 [boris#647](https://github.com/drawmeanelephant/boris/issues/647) → [#651](https://github.com/drawmeanelephant/boris/pull/651) — zero-write validation daemon under `validate --watch` (the RFC merged). Consumption design: [`docs/ENGINE-CONTRACTS.md`](../ENGINE-CONTRACTS.md) §1 (unprobed — re-probe before trusting).

**Filed (2026-08-18):**

**File next:** none.

Do not ask: unifying `compiler` field names, library mode, relaxing
editor token/CSP, shipping `boris-editor` in the agent-pack.
