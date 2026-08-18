# Card M11-2 — Test pass

**Milestone:** M11 · **Issue:**
[#125](https://github.com/drawmeanelephant/solipsist/issues/125) ·
**Lane:** Tests. One worktree, one PR against `main`; branch
suggestion `feat/m11-test-pass`.

## Owns

- `Tests/ContractTests/` (new files + extensions)
- A small helper extracted from Play / Preview **only if** the URL
  rule is currently an inline string and cannot be tested otherwise
- `docs/help.md` **read-only** (the help-vs-commands test reads it)

## Do not touch

- `Sources/Chrome/MainWindow.swift`
- `Sources/Engine/**` beyond calling existing types
- `Sources/Compose/**` (already has contract tests)
- `Project.yml` — no XCUI target
- Help copy (M11-1)

## Why

`make test` decodes contracts and checks `WorkspaceSelection` rules.
The letter URL (`/{graph node id}.html`) is a Solipsist rule with no
test. Help vs `Commands.swift` was a one-shot queue card (Q25) and
drifted the moment M10 landed. There is no XCUI target; do not add
one for this gate.

## Do

1. **Reading URL.** Test the page-letter mapping: helper origin +
   `/{id}.html`, including an id with a slash (`recipe/soup` must
   not become a stem-swap of `sourcePath`). Put the rule in a
   Foundation type if it is not already (`PreviewURL` or a sibling).
2. **Help vs Commands.** A test that every `.keyboardShortcut` and
   every `Button(` title in `Sources/App/Commands.swift` appears in
   `docs/help.md`. Fail loud. Read files from the repo root; do not
   import SwiftUI into the assertion beyond what ContractTests
   already allow.
3. **Mailbox display.** If `WorkspaceMailbox.display` / unknown →
   Pages-without-rewrite is not fully covered, finish that file.
   Do not add `WorkspaceStore` to the test target.
4. Keep tests runnable as `make test` with no boris binary.

## Do not

- Stand up XCUI / `SolipsistUITests`.
- Hit the network or spawn `boris`.
- Rewrite ReadingPane to make it “more testable.”
- Duplicate Compose highlighter tests.

## Gate

`make test` includes a failing-if-undocumented help audit and a
reading-URL case for a slashed id. `SKIP_EMBED_BORIS=1 make build`
green. No new test target.
