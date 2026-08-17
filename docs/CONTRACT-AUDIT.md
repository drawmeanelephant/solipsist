# Boris CLI Contract Audit — consumer view from Solipsist

**Date:** 2026-08-17
**Engine baseline:** boris v0.8.0 (`main` @ e65e674), IR schema `0.2.0`
**Method:** consumer-driven audit — *"if a separate macOS app treats boris as
a black-box compiler, where does the interface suck?"* Everything below was
verified empirically against the built binary, not assumed from source.

Companion to [ENGINE-WORK-AND-DESIGN.md](ENGINE-WORK-AND-DESIGN.md) (issues +
design decisions) and the ready-to-paste issue bodies in
[docs/issues/](issues/). This doc's job is the **bucketing**: what is
binary-friendly already (🟢), awkward but fixable (🟡), and an architectural
blocker (🔴). The 🔴 list is the gold — those are the issues we actually feed
back into Boris.

---

## The 15-category map

| # | Category | Verdict | Evidence (verified) | Issue |
|---|----------|---------|---------------------|-------|
| 1 | Invocation ergonomics | 🟢 | Typed flags, stable defaults, mode conflicts fail fast with exit 2; `--help` prints to **stderr** (unusual but consistent) | A4 |
| 2 | Machine-readable output | 🔴 | IR/RAG/context/check emit versioned JSON; **watch mode emits human prose only** — the app would scrape text | A1, A5 |
| 3 | Atomicity | 🟢 | IR: build-report written on failure, graph not published on failure. HTML: staged publish + atomic cache manifest. **Survives SIGKILL** (verified, see Kill section) | — |
| 4 | Incremental state | 🟡 | `.boris-cache/` lives inside the output dir; content-addressed, `format_version`-gated; app can invalidate by deleting it; **undocumented + no completion timestamp** | A6 |
| 5 | Path assumptions | 🟡 | HTML outputs confined to process **cwd** (path-boundary check; root collision is a distinct error); IR/RAG/context/report write anywhere — asymmetric and undocumented; symlinks under content root → `EIO` | A7 |
| 6 | Process lifecycle ("can I kill Boris?") | 🟢 | **Verified:** SIGTERM/SIGINT → graceful exit 0 ≤500ms with cleanup message; SIGKILL → no stage leftovers, last-good manifests intact, next build recovers; no orphan processes. Gap: behavior undocumented | A12 |
| 7 | Versioning | 🔴 | **No `--version` flag** (pre-build engine identity impossible); build-report lacks `compiler`; artifacts do carry `schemaVersion` + `compiler` (manifest/graph) | A2, A3 |
| 8 | Resource limits | 🟡 | `--jobs 1–64` parallel rendering; 500ms idle poll; OOM paths exist; huge/malformed inputs yield structured `EFRONTMATTER`/`EIO` diagnostics, not crashes. App-side: cap jobs + own timeout | — |
| 9 | Binary discovery in `.app` bundle | 🟢 | Solved app-side: `SOLIPSIST_BORIS_BIN` → bundle `Resources/boris` → dev checkout (`BorisBinary.swift`); static, zero-dep arm64 Mach-O | — |
| 10 | stdout/stderr discipline | 🟢 | **stdout is sacred** — empty on every success path; all progress/diagnostics/help/reports on stderr. One trap: `--report` help text claims "instead of stdout" (it defaults to stderr) | A4 |
| 11 | Determinism | 🟢 | Core promise, held: no timestamps/abs-paths/random ids in artifacts; sorted logs; byte-identical rebuilds (golden-tested) | — |
| 12 | Configuration discovery | 🟢 | Boris reads **no config file** — pure flags. Nothing to reverse-engineer; app owns project settings (D2) | — |
| 13 | Preview artifact set | 🟢 | HTML mode produces exactly the site tree + assets; not a web server. App serves `dist/` via local HTTP (D5). Gap: watch is HTML-only (no diagnostics-watch) | A5 |
| 14 | Editor integration (diagnostics) | 🟡 | Diagnostic objects have stable `severity, code, message, remediation, sourcePath, line, column, id` — but only via IR/check artifacts and **text-on-stderr during watch** | A1, A5 |
| 15 | Future compatibility | 🟢 | Every IR artifact carries `schemaVersion`; consumers gate on it (D8 policy). Engine pinned per app release (D7). Additive field tolerance confirmed | — |

---

## 🔴 Architectural blockers (the gold)

Three places where Solipsist would otherwise have to **parse human output,
depend on filesystem voodoo, or duplicate Boris's internal logic**:

1. **Watch mode speaks prose, not events.** `boris --watch` prints
   `watch: changed paths detected: …` / `watch: rebuild succeeded.` /
   `error: rebuild failed: …` to stderr and nothing machine-readable
   anywhere. A live-preview + problems-panel app *must* have typed lifecycle
   events with structured diagnostics. → **A1** (`--watch-json` NDJSON
   events) and **A5** (diagnostics-watch for non-HTML modes). Until A1 lands,
   D10's stopgap parser + `.boris-cache/manifest.json` ground truth is the
   bridge.

2. **One-shot HTML builds return exit code + prose, nothing else.** IR mode
   publishes `build-report.json` on success *and* failure; HTML mode
   publishes no result artifact at all. The completion signal exists de
   facto (atomic cache manifest, written on success only — verified) but is
   undocumented and lacks a timestamp. → **A6**.

3. **The app can't ask the binary who it is.** No `--version` (pre-build),
   and `build-report.json` — the artifact decoded on every build, including
   failures — omits `compiler`. → **A2**, **A3**.

## 🟡 Awkward but fixable

- `--help` on stderr; watch line grammar unspecified; `--report` help text
  lies about stdout (→ A4).
- Cache manifest undocumented; no `completed_at`/`page_count` (→ A6).
- Workspace containment asymmetry undocumented (→ A7).
- Signal/cancel behavior undocumented (→ A12).
- Multi-target watch + IR/RAG conflicts are usage errors (exit 2) — fine,
  but a consumer discovers them by trial; help text already covers it.

## 🟢 Binary-friendly already (no work needed)

Deterministic, timestamp-free artifacts · sacred stdout · stable documented
exit codes (0/1/2/3) · structured diagnostics with stable codes and source
locations · atomic IR + HTML publication that survives SIGKILL · graceful
watch shutdown (verified) · cwd-containment of HTML outputs · `schemaVersion`
on every IR artifact · zero runtime deps for a signed bundle.

---

## Deep dive: "Can I kill Boris?" (the user-asked question)

**Verdict: yes — cleanly.** Verified empirically this session:

| Action | Result |
|--------|--------|
| `SIGTERM` on idle watcher | Exit **0**, prints `watch: received shutdown signal, cleaning resources...`, gone within one idle poll (≤500ms) |
| `SIGINT` on idle watcher | Same: exit 0, cleanup message |
| `SIGTERM`/`SIGINT` mid-rebuild | Latch is checked between loop iterations, so the in-flight rebuild **completes first**, then shutdown — a cancelled build never publishes a partial tree |
| `SIGKILL` (unavoidable) | Process dies instantly; **no `.boris-stage` leftovers**; last-good `.boris-cache/manifest.json` intact in both targets; the next build recovers cleanly |
| Orphan processes | None observed in any test |

**How the app consumes this:** Swift `Process` gives `terminationReason`
(`.exit` vs `.uncaughtSignal`) + `terminationStatus`. A signal-terminated
watch process ⇒ *user cancelled* — deterministic, no parsing. The one
residual gap is that none of this is *documented* as a contract (→ A12). The
app should still enforce its own timeout + SIGKILL escalation as a belt-and-
braces layer (the subprocess boundary makes that safe by construction).

---

## Next actions

1. File the 🔴 set: **A1** (flagship), **A2** + **A3** (tiny), then the 🟡
   docs: **A4**, **A6**, **A7**, **A12**.
2. App-side: D10 stopgap parser + `.boris-cache/manifest.json` ground truth
   so preview works before A1 lands; enforce app-side timeout/cancel
   (terminationReason-based) per the Kill findings.
3. Lock D7 (pinned engine commit) — versioning is a 🔴 only because the app
   can't *ask*; pinning + `schemaVersion` gating covers the rest.
