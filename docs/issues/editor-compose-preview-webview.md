# Editor: Compose Preview — Replace NSAttributedString with WKWebView

**Track:** Compose depth / macOS native polish
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#230](https://github.com/drawmeanelephant/solipsist/issues/230)
**Lane:** `Sources/Compose/`

## Problem

The Compose preview pane renders HTML through
`NSAttributedString(data:options:.documentType:html)`, which has no CSS, no
JavaScript, no `<video>/<audio>/<iframe>`, blocks the main thread on large
documents, and renders unsandboxed in-process.

## Verified current state

`ComposePreviewView` (`Sources/Compose/ComposePreview.swift`) debounces
renders with a 300ms `.task(id:)` then calls the injected `MarkupRenderService`
(Oliver-backed) and hands the HTML string to `ComposeHTMLPreview`, an
`NSViewRepresentable` that sets the text on a non-editable `NSTextView` via
`NSAttributedString(data:options:.documentType:html)`. The render pipeline
(Oliver → HTML string) stays; only the host view changes.

## Scope

### Must land

- Replace `ComposeHTMLPreview`'s `NSTextView` with a **`WKWebView`** that
  renders the HTML fragment.
- **Theme CSS**: apply the canonical HTML target's theme CSS (resolved from
  the source's profile / `themes/` when present) as an **inlined `<style>`
  element in the fragment's `<head>`**. When no theme resolves, fall back to
  a minimal readable stylesheet. Do not build a theme picker.
- **Sandboxed rendering**:
  - non-persistent `WKWebsiteDataStore` (no disk cache);
  - a `WKNavigationDelegate` that cancels every navigation except the initial
    load;
  - loopback-only posture — no external network.
- **Preserve the existing 300ms debounce** (it lives in `ComposePreviewView`;
  do not move it).
- **Do not scroll to top on every re-render** — that is jarring while typing
  mid-file. A full reload resets scroll anyway; preserving position is a
  best-effort out-of-gate nicety, not a requirement.

### Nice-to-have (not gate)

- Scroll-position preservation across re-renders (minimal JS).
- Dark-mode support (system appearance + theme dark variant).
- Print (⌘P) from the preview.

### Must not land

- A second `WKWebView` session shared with the Preview companion (that is a
  separate watch server).
- An app-side HTTP server (D11: "no app-side HTTP server").
- A third-party rendering library.

## Design note — resolve the baseURL contradiction

The draft said "load with a loopback `baseURL`" **and** "no app-side HTTP
server". Those cannot both hold: a loopback baseURL makes relative URLs
resolve to `http://127.0.0.1/...`, which only works if something serves that
port. The clean resolution:

- **Inline the theme CSS as a `<style>` tag** — the fragment becomes
  self-contained, so styling needs no file or network access at all.
- **Relative image/media URLs in the content are out of scope for the compose
  preview.** Resolving them is the full-site Preview companion's job (it has
  the watch server). Declare it in the card so the worker does not chase it.
- Load the fragment with `loadHTMLString(_:baseURL: nil)` or a `data:` URL.
  Do **not** use a `file://` baseURL: in the sandbox, WebKit's web-content
  process may not hold the security-scoped extension for the user's folder,
  so file subresources silently fail. That is exactly why the CSS is inlined.

## Implementation sketch

1. Rewrite `ComposeHTMLPreview` as a `WKWebView` `NSViewRepresentable`:
   ```swift
   struct ComposeHTMLPreview: NSViewRepresentable {
       let html: String // fragment with theme <style> already inlined
       func makeNSView(context: Context) -> WKWebView {
           let config = WKWebViewConfiguration()
           config.websiteDataStore = .nonPersistent()
           let webView = WKWebView(frame: .zero, configuration: config)
           webView.navigationDelegate = context.coordinator
           return webView
       }
       func updateNSView(_ webView: WKWebView, context: Context) {
           webView.loadHTMLString(html, baseURL: nil)
       }
   }
   ```
2. `WKNavigationDelegate.decidePolicyFor` returns `.cancel` for every request
   after the initial load (and `.cancel` for any non-`about:`/`data:` scheme).
3. Build the full fragment before handing it to the view: wrap Oliver's HTML
   in `<html><head><style>…theme…</style></head><body>…</body></html>`, with
   the theme CSS read from the source's `themes/` (canonical target's theme)
   or the minimal fallback. This assembly is pure and unit-testable.
4. Keep `ComposePreviewView` unchanged except that `html` is now the wrapped
   fragment.

## Gate

Open a page in Compose → the preview renders styled HTML (theme CSS applied
when present) instead of unstyled text → typing re-renders after the 300ms
debounce without blocking the UI → clicking a link in the preview does not
navigate → switching pages does not leak the previous fragment →
`SKIP_EMBED_BORIS=1 make build` + `make test` green.

## Tests

- `testPreviewFragmentWrapsHTML` — the assembled fragment contains the theme
  `<style>` and the body content.
- `testPreviewThemeCSSFallback` — no theme → the minimal stylesheet is used.
- `testPreviewSandboxBlocksNavigation` — `decidePolicyFor` cancels a link
  click / external URL.
- Manual: large document renders without blocking; rapid re-renders do not
  leak memory; malformed HTML does not crash.

## Edge cases

- Empty HTML → blank page, not an error.
- Very large documents → WKWebView renders asynchronously; no main-thread
  block.
- Malformed HTML → WKWebView is forgiving; no crash.
- Page switch → the view is recreated per document; no retained reference to
  the previous fragment.
