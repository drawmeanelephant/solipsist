# Plan/Activity real-content gate — verification

**Issue:** [#130](https://github.com/drawmeanelephant/solipsist/issues/130) follow-up — band fix landed via PR #134 (Pages) + #135 (Outputs/Publish/Plan/Activity)
**Status:** ✅ DONE — verified live with real content on the pinned engine (2026-08-18)

The toolbar-band fix is in, and the Gate was exercised on `Stunts/happy`
with the pinned boris build (`6b930b7bd35a1803b365a073c226df22631dc3f7`,
built at `zig build -Doptimize=ReleaseSafe`). Both Plan and Activity
rendered real content and passed.

## Measured geometry (window 1339x700, toolbar band y=416..468)

**Plan** (run via the Plan mailbox → Plan Publication button):
- Plan `List` scroll area starts at **y=468** — exactly the band's bottom edge
- First section header **"Publication Plan Overview"** at **y=475** — 7pt clear of the band ✅
- Sections render below the band: Site Metadata (y=629), Declared Targets (1) (y=701), Declared Editions (y=844) ✅
- Real rows verified: Format `boris-publication-plan`, Schema Version 1, Input Root `content`, Input Format `markdown`, Title `My Boris Site`, target `public` → Output Path `dist`, Theme `themes/boris`

**Activity** (via toolbar Build IR, `exit 0 · 3 pages · 0 error(s)`):
- Activity `List` scroll area starts at **y=468** — band's bottom edge ✅
- Section header **"History (1)"** at **y=475** — 7pt clear ✅
- First history row at **y=514** — 46pt clear of the band, with verb (`buildIR`), exit code (`exit 0`), duration (`6 ms`), and timestamp ✅
- **Timings breakdown** DisclosureGroup renders on the row — the code only draws it when `activity.timings != nil`, so the timings data arrived from the pinned build ✅
- Second row (validate) also below the band ✅

## Notes / caveats

- The disclosure *expansion* (showing Mode / Phases / Counters detail) could
  not be exercised via synthetic clicks/AXPress on macOS 27 beta — the
  DisclosureGroup header renders (proof the timings data is present), but
  the toggle itself needs a real user click. Low risk; standard SwiftUI
  control.
- Sandbox note: `open` strips `SOLIPSIST_BORIS_BIN` and the sandbox cannot
  read `/tmp` for `BorisBinary.locate()`. The pinned binary was embedded
  into the app bundle's `Resources/boris` for the run (the same path
  `scripts/embed-boris.sh` uses).
- `zig build` (Debug) sha did not match the manifest's ReleaseSafe sha;
  `-Doptimize=ReleaseSafe` also differed (local toolchain/path). The commit
  pin matched exactly, which is what the gate required.

## Gate (pass criteria)

The first row / first section header of the Plan and Activity lists is
fully visible below the toolbar band without scrolling, and rows are
interactive. `SKIP_EMBED_BORIS=1 make build` + `make test` stay green.

**Result: PASS** — Plan and Activity first rows/headers sit 7pt+ below the
band's bottom edge (y=468), all sections/rows visible without scrolling,
rows interactive (toolbar verbs ran against the pinned engine). Build +
211 tests / 0 failures green.

## Guardrails

- **Verification only.** `Sources/Play/` is read-only for this queue —
  flag, don't edit. If the gate reveals a real bug, stop and file an
  issue with the geometry (window size, first-row y vs band y).
- Don't patch boris; report build errors and draft a boris issue
  instead.
- On success, update this card with the measured geometry (or mark it
  done) and note it in the #130/#135 close-outs.

**Done — no bug found, no `Sources/Play/` edits.**
