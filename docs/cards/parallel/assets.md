# Parallel — app icon and asset catalog

**Owns:** `Solipsist/Assets.xcassets` (or `Sources/Assets.xcassets`)
and the one `Project.yml` key that points at it
(`INFOPLIST` / `asset catalog` path). Do not otherwise edit
`Project.yml`.

## Do

1. Add an asset catalog with `AppIcon` for a macOS app.
2. A simple, original mark — not a copy of Apple’s, not a downloaded
   “AI whale”. Geometric, 1024 ready. If you cannot ship a real
   image, a solid SF-style vector exported to the required sizes is
   fine.
3. Wire `ASSETCATALOG_COMPILER_APPICON_NAME` if not already set.
4. No third-party icon packs with messy licenses.

## Gate

`make build` (local, with or without engine). The built app shows the
icon in Finder. Diff is the catalog + the one Project.yml line.
