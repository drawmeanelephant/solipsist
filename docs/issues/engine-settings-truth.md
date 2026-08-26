# Engine Settings Tell the Truth — drop the dead binary pickers, hard-gate the embedded engines

**Track:** Ship posture / Settings honesty
**Milestone:** Post-M17 polish
**Issue:** [#292](https://github.com/drawmeanelephant/solipsist/issues/292)
**Lane:** `Sources/App/Settings/EngineSettingsPane.swift` + the three locators + release gate

Sibling of banal#209 ("Bundle Oliver and Boris inside the app for sandbox
self-containment"). Solipsist already did the bundling half (M9, #78):
boris, oliver, and the companion tools are lipo'd universal, hardened-
runtime-signed, and embedded at `Contents/Resources/`. What we never
revisited is the UI and the release gate around that decision — and both
now promise things the shipped app cannot do.

## Problem

Three problems, one root cause: the pre-M9 world (locate a binary from
the host) is still visible in surfaces that the M9 world (bundle
everything, sandbox everything) has made dead or dangerous.

1. **The pickers cannot work in the shipped build.**
   Settings → Engine offers "Choose Custom Boris… / Oliver… / Editor…"
   (`EngineSettingsPane.swift:80-97, 123-138, 164-179`). The app runs
   under `com.apple.security.app-sandbox` (`Solipsist.entitlements:5`);
   App Sandbox denies exec of any binary outside our own bundle, so a
   user-picked engine fails with EPERM in exactly the build where a
   consumer would try it. Developer plumbing posing as a consumer
   setting.
2. **A stale preference shadows the working embedded engine.**
   All three locators read a `custom*BinaryPath` default *first*
   (`BorisBinary.swift:20-23`, `OliverBinary.swift:22-25`,
   `EditorServerFactory.swift:33-36`). A path saved under an older
   build (or by a curious user pointing at a random file) silently
   outranks the signed, universal engine we ship. Same trap shape as
   banal#202 ("CI-green, machine-specific").
3. **The release gate trusts boris but winks at everything else.**
   `release-notarize.yml:176-180` exits 1 when `Resources/boris` is
   missing; oliver and the four companions only get a WARNING
   (`:185-193`), and `embed-boris.sh:183` treats missing oliver as a
   notice. Under sandbox there is no fallback to warn about:
   a Finder-launched release never inherits `SOLIPSIST_OLIVER_BIN`
   (launchd strips shell env; `open` strips it too), so a bundle that
   ships without oliver is silently-broken compose preview with no
   recourse. That is precisely the gap banal#209 exists to close on
   their side; we closed the bundling but left the gate soft.

## Verified current state

- Pickers + "Reset" buttons: `EngineSettingsPane.swift:80-97` (boris),
  `:123-138` (oliver), `:164-179` (editor); `NSOpenPanel` helper at
  `:222-232`; in-app search-order explainer lists "Settings Custom
  Preference" as step 1 (`:184-216`).
- Custom-pref first rung: `BorisBinary.swift:20-23`,
  `OliverBinary.swift:22-25`, `EditorServerFactory.swift:33-36`.
  Grep confirms nothing else reads the three defaults keys; **no test
  references them**.
- Env rung: `SOLIPSIST_BORIS_BIN` / `SOLIPSIST_OLIVER_BIN` /
  `SOLIPSIST_BORIS_EDITOR_BIN`. Used by CI
  (`ci.yml:61`), scripts (`embed-boris.sh`, `harvest-stunt-fixtures.sh`,
  `stunt-smoke.sh`), and the non-sandboxed test host. Keep.
- Embedded binaries land in `Contents/Resources/` (not Helpers) via
  xcodegen phase → `embed-boris.sh`; companions embedded alongside:
  boris-editor, boris-package, boris-source-rag, boris-content-audit.
- Release inspection: boris = hard fail + `lipo -info` + `--version`;
  companions = WARNING only (`release-notarize.yml:174-193`).
- `README.md:58-60` already documents the honest order (env → bundle →
  dev checkouts) with no mention of the pref — the docs got the memo,
  the code and UI didn't.

## Scope

### Must land

- **Remove the three pickers and Reset buttons** from
  `EngineSettingsPane`. The pane becomes status-only: green/red dot +
  version, resolved path, origin line ("Embedded in Solipsist.app
  bundle", etc.). Keep `originDescription` minus the custom-path case.
- **Remove the `custom*BinaryPath` first rung** from all three locators.
  Search order collapses to: env override → bundled `Resources/…` /
  sibling-of-boris → dev checkouts. Delete the three keys from
  preferences on launch so stale values don't linger as zombies
  (`UserDefaults.removeObject`, one-time, cheap, silent).
- **Update the in-app explainer** (`searchStep` list): renumber, drop
  the Settings rung.
- **Hard-gate the release bundle:** in `release-notarize.yml`, require
  `Resources/oliver` and all four companions to exist (exit 1, matching
  boris), and `lipo -info` each one — every embedded engine must be
  arm64 + x86_64 or the release does not ship.
- **Doc updates, same change:** `docs/SHIP-HARDENING.md` §2 (search
  precedence drops the env-only caveat stays; note pickers removed),
  `docs/issues/README.md` index row.

### Must not land

- Do not remove the env-var overrides — CI, scripts, and the test host
  depend on them (`make test` must stay green with zero embedding).
- Do not remove the dev-checkout candidates — ad-hoc dev builds with
  `SKIP_EMBED_BORIS=1` rely on kit/sibling resolution.
- Do not move binaries from `Resources/` to `Contents/Helpers/` — churn
  with no functional win under our signing setup.
- Do not add a hidden DEBUG-only picker. Env vars are the developer
  escape hatch; two escape hatches is how we got here.

## Gate

1. Signed sandboxed release build: Settings → Engine shows status only;
   engine resolves to `Contents/Resources/boris`; origin reads
   "Embedded". No NSOpenPanel anywhere in the pane.
2. Negative test: strip `Resources/oliver` from a staged release app →
   the workflow's inspect step exits 1. Same for any companion.
3. Stale-defaults test: set `customBorisBinaryPath` to a bogus
   executable path, launch, confirm the app runs the embedded engine
   and the key is gone after first launch.
4. `SKIP_EMBED_BORIS=1 make build` + `make test` green (locators still
   resolve via env/dev candidates in the unsandboxed test host).

## Edge cases

- `BorisBinary.locate(environment:)` keeps its injectable signature —
  tests and previews pass explicit environments; only the UserDefaults
  read disappears.
- The editor locator's sibling-of-boris rung
  (`EditorServerFactory.swift:43-46`) already covers the embedded layout
  (boris-editor sits next to boris in Resources); verify the Bundle.main
  fallback behind it stays for standalone launches.
- Ad-hoc dev builds (no Developer ID): codesign of embedded copies falls
  back to `-` in embed-boris.sh — unchanged by this card; the workflow's
  spctl gate already skips those correctly.
