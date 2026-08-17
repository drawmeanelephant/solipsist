# Parallel — Preview companion shell

**Owns:** `Sources/Companions/Preview/`
**Do not touch:** `Engine/`, `Play/`, `Inspector/`, `Workspace/`.

## Why

Preview is a companion window. The grind lane will later give
`BorisEngine.previewStart/Stop`. You build the *window* so that
method has somewhere to land.

## Do

1. `PreviewWindow` is a `WKWebView` plus a slim toolbar: URL field,
   Reload, Open in Browser.
2. It reads `WorkspaceStore.selection` only to show *which* source is
   selected (title / path). It does not start `boris`.
3. Until Engine grows preview, the web view loads `about:blank` and
   the toolbar lets a human paste `http://127.0.0.1:<port>/__boris/`.
   Validate loopback only (`127.0.0.1` / `localhost`). Refuse anything
   else.
4. Menu item already exists (View → Preview). Keep it.
5. No `Process`. No stderr regex. When grind adds `serve-started` /
   `previewStart`, they will set the URL. Leave a single
   `func loadPreview(url: URL)` on the view for them.

## Gate

`make build`. Open Preview with no source → empty state. With a
source → name shown, paste a loopback URL → WKWebView loads it.
Non-loopback paste is rejected. Diff is only under
`Sources/Companions/Preview/`.
