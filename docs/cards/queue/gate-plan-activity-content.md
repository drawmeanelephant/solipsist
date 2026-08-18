# Plan/Activity real-content gate — verification

**Issue:** [#130](https://github.com/drawmeanelephant/solipsist/issues/130) follow-up — band fix landed via PR #134 (Pages) + #135 (Outputs/Publish/Plan/Activity)
**Status:** open · code merged · verification gap

The toolbar-band fix is in, but the Gate was only exercised on
`Stunts/happy` with no plan and no activity history: **Outputs** and
**Publish** were verified live (first section header below the band),
while **Plan** and **Activity** only ever rendered their empty states.
Their lists carry the same `.safeAreaPadding(.top, toolbarBand)` inset
but have never been gate-checked with real content.

## Why the gate still matters

- **Plan** renders a multi-section `List` (overview / site metadata /
  publication declaration / declared targets / editions) only when a
  plan exists. With content, the first section header must sit below
  the floating glass toolbar band, not under it.
- **Activity** renders history rows only after the coordinator has run
  a job. With history, the first row must sit below the band and rows
  must expand (Timings breakdown).

## Steps

1. Build the engine at the pin (same as
   `vendor/boris-agent-kit/MANIFEST.json`):
   ```bash
   git clone https://github.com/drawmeanelephant/boris.git ../boris
   cd ../boris
   git checkout 6b930b7bd35a1803b365a073c226df22631dc3f7
   zig build
   ```
2. Build & launch the app:
   ```bash
   SKIP_EMBED_BORIS=1 make build
   SOLIPSIST_BORIS_BIN=$PWD/../boris/zig-out/bin/boris \
     open build/Build/Products/Debug/Solipsist.app
   ```
3. Open `Stunts/happy`, select **Plan** in the sidebar, and run Plan
   (Publish pane → Plan button, or the toolbar) so a plan exists.
   Confirm:
   - the Plan `List` renders with "Publication Plan Overview" first;
   - the first section header starts at the **bottom edge** of the
     floating glass toolbar band — not underneath it;
   - rows scroll under the band and stay interactive.
4. Select **Activity**, then run any verb (Validate / Build IR / Plan).
   Confirm:
   - history rows render with the verb, exit code, and timestamp;
   - the first row starts below the band;
   - a row expands to show "Timings breakdown".

## Gate (pass criteria)

The first row / first section header of the Plan and Activity lists is
fully visible below the toolbar band without scrolling, and rows are
interactive. `SKIP_EMBED_BORIS=1 make build` + `make test` stay green.

## Guardrails

- **Verification only.** `Sources/Play/` is read-only for this queue —
  flag, don't edit. If the gate reveals a real bug, stop and file an
  issue with the geometry (window size, first-row y vs band y).
- Don't patch boris; report build errors and draft a boris issue
  instead.
- On success, update this card with the measured geometry (or mark it
  done) and note it in the #130/#135 close-outs.
