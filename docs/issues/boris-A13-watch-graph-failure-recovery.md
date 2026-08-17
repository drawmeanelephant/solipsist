# A13 — watch: graph-validation failures kill the watcher instead of being recoverable

> **Filed: [boris#640](https://github.com/drawmeanelephant/boris/issues/640)**
> Priority: P0. Size: S. Bug — contradicts the documented recoverable-failure
> contract. Found by probing the agent-kit binary (`boris/0.8.1`, Darwin-arm64,
> commit `b82e9e2`), not from the original A-list.

---

## Summary

`boris watch` exits on a graph-validation failure during a rebuild,
contradicting `docs/contracts/watch-mode.md` §5, which says content
validation failures keep the watcher alive for correction.

## Repro

```bash
boris init site && cd site
boris watch --serve --input content --html-dir dist --theme themes/boris &
# initial build succeeds; watcher starts
printf -- '---\nid: index\ntitle: Dup\n---\n\n# Dup\n' > content/dup.md
```

Observed:

```
watch: changed paths detected:
  - dup.md
watch: triggering incremental rebuild...
error: EDUPLICATEID: index.md:1:1: duplicate id "index" (also dup.md) [...]
error: rebuild failed with unrecoverable I/O error: GraphValidationFailed
```

The process **exits with code 1** and the preview server dies.

## Contrast (correct, recoverable path)

An invalid-frontmatter file in the same position prints
`error: rebuild failed: ParseFailed. Waiting for correction...` and the
watcher stays alive, recovering when the file is fixed.

## Likely root cause

The watcher's rebuild-failure mapping treats `GraphValidationFailed` as an
unrecoverable I/O-class error instead of a recoverable content failure.
`ParseFailed` routes to the recoverable path; `GraphValidationFailed` does
not.

## Acceptance criteria

- [ ] A duplicate-id (or other `GraphValidationFailed`) rebuild prints the
      diagnostic and keeps the watcher alive, awaiting correction.
- [ ] Fixing the content then recovers without a restart.
- [ ] Last-good HTML output remains served throughout.
- [ ] Unrecoverable I/O failures (missing content root, etc.) still exit.
