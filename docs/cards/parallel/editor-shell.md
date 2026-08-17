# Parallel — Editor companion shell

**Owns:** `Sources/Companions/Editor/`
**Do not touch:** `Engine/`, `Play/`, `Inspector/`. Do not spawn
`boris-editor`.

## Why

Same split as Preview. A14 will pin
`BORIS_EDITOR_URL=http://127.0.0.1:<port>/#token=…`. You parse that
line and load it. Grind lane will spawn the host later.

## Do

1. `EditorWindow`: WKWebView + a field that accepts a full
   `BORIS_EDITOR_URL=…` line *or* the raw URL.
2. Parser: prefix optional, URL must be `http://127.0.0.1:<port>/`
   with a `#token=` fragment of hex. Reject anything else.
3. Load that URL. Do not put the token into query or logs.
4. Empty state: selected source title + “Editor host is not running.”
5. Unit-test the parser in `Tests/` only if the fixtures card already
   added a test target; otherwise a small `EditorURL` type in
   `Companions/Editor/` with a comment is enough.

## Gate

Paste a well-formed `BORIS_EDITOR_URL=` → WebView navigates to that
loopback URL. Bad input is refused. No `Process`. Diff only under
`Sources/Companions/Editor/` (+ a test file if the target exists).
