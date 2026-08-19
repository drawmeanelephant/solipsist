# Card LATER-2 — Source-RAG export

**Issue:** [#166](https://github.com/drawmeanelephant/solipsist/issues/166)
· **Lane:** export / menu. One worktree, one PR against `main`; branch
suggestion `export/source-rag`.

## Owns

- The menu verb (File → Export → Source RAG…, or an Outputs / Activity
  action)
- Finder reveal / open of the produced pack
- Binary locate/embed for `boris-source-rag` — a **separate kit binary**,
  not the embedded `boris`

## Do

1. **Probe first — already done.** The probed contract is recorded in
   `docs/ENGINE-CONTRACTS.md` §9 (PR #168); the short version is on
   [#166](https://github.com/drawmeanelephant/solipsist/issues/166#issuecomment-5341401629):
   flags, verified exit codes 0/2/3, output tree, manifest shapes,
   `--pack-by=tool`.
2. Add the menu verb that runs the tool against the selected source.
3. Reveal `--out` in Finder (or open `INDEX.md`).
4. Same process seam: the coordinator's single `Process?` slot, surface
   exit codes.

## Do not

- Reimplement packing in Swift.
- Conflate with the M7 `--rag` edition row (already in `OutputsPane`).
- Touch `Sources/Engine/**` beyond an additive, single-owner change
  (future lanes #160/#161 own the boundary).

## Gate

Menu verb produces the pack, Finder reveals it, non-zero exit surfaces.
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
