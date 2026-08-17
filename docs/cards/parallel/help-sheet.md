# Parallel — Help sheet

**Owns:** `docs/help.md` and `Sources/App/` **only if** you add a
`CommandGroup` in `Commands.swift` that opens the file. Do not
restructure `SolipsistApp` or `MainWindow`.

## Do

1. `docs/help.md` — short: what the three columns are, File → Open,
   View → Preview / Editor / Inspector, where diagnostics will live,
   link to ROADMAP.
2. Help menu item “Solipsist Help” opens that markdown in a small
   `Window` or `NSWorkspace` to the file in the bundle. Prefer a
   bundled resource over a web URL.
3. If bundling requires a `Project.yml` resources entry, add only
   that.

## Gate

Help → Solipsist Help shows the sheet. `make build`. No Play /
Inspector / Engine diffs.
