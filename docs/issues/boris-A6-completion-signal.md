# A6 — The incremental changed-page contract: document `.boris-cache/manifest.json`

> **Ready-to-paste GitHub issue for the boris repo.**
> Priority: P2. Size: XS. Documentation only.
> **Rebaselined against afterparty v0.8.1.** The original ask — "HTML builds
> have no machine result artifact" — is **solved** by `build --report PATH`
> (`html-build-report-0.1.0`, written on success and failure). What remains
> is the narrower, still-open question below. If boris considers the cache
> manifest an internal detail, this issue can be closed as won't-do; it is
> filed because the manifest is already a public artifact (listed in
> `--help`).

---

**Title:** Document `.boris-cache/manifest.json` as the incremental changed-page contract

## Summary

Incremental HTML builds (and watch) atomically write
`<target-dir>/.boris-cache/manifest.json` — a public artifact, already
listed in `--help` under "HTML artifacts (success)". It is the only
machine-readable record of *what an incremental build actually did*: per-page
`entity_id`, content `fingerprint`, `output_path`, and `output_digest`.
Verified behavior:

- Written **only on successful publish** — a failed incremental build leaves
  the previous manifest byte-identical, so its replacement is a genuine
  "last successful build" marker, not a "last attempt" marker.
- The **`fingerprint` diff between consecutive manifests is exactly the
  changed-page set** — content-addressed, deterministic, sorted.

That makes it the natural basis for consumers that need change attribution
from one-shot incremental builds: incremental deployers ("which pages
changed since the last successful build?"), preview reloaders, and
incremental-export tools. But it is undocumented: nothing states the
completion-marker guarantee, the fingerprint-diff rule, or the manifest's
format versioning (`boris-cache-v2-layout-rules`).

## Proposal

1. **Document the contract** — a short section in
   `docs/contracts/html-output.md` (or a `cache-manifest.md`): written
   atomically on successful incremental/watch publish only; never rewritten
   on failure; replacement = completion marker; `fingerprint` diff =
   changed-page set; `format_version` gating (a bumped version forces a
   cold rebuild — consumers must tolerate that).
2. **Optionally** add `"page_count"` after `format_version` so consumers
   don't count entries; `completed_at` is explicitly *not* requested
   (boris artifacts avoid timestamps, and mtime-on-replacement already
   works for polling consumers).

## Why this is a strong decision for boris

It converts an already-public, already-reliable artifact into a documented
promise — the same "atomicity made observable" move the IR path gets from
`build-report.json`, for the incremental path. No behavior change; the
fingerprint semantics already exist and are tested. Low value if nobody
consumes incremental builds programmatically; real value for the
incremental-deploy and preview-tooling classes that do.

## Acceptance criteria

- [ ] `docs/contracts/html-output.md` (or equivalent) documents the
      completion-marker guarantee, the fingerprint-diff changed-page rule,
      and `format_version` gating.
