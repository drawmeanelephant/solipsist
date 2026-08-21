# Boris issues (consumer access)

Ready-to-paste drafts. File on `drawmeanelephant/boris`. Never open a
PR against boris from this repo.

**Already merged on afterparty** (in the `bf464a0` kit pin):

- A3 [boris#638](https://github.com/drawmeanelephant/boris/issues/638) → [#643](https://github.com/drawmeanelephant/boris/pull/643)
- A4 [boris#639](https://github.com/drawmeanelephant/boris/issues/639) → [#642](https://github.com/drawmeanelephant/boris/pull/642)
- A13 [boris#640](https://github.com/drawmeanelephant/boris/issues/640) → [#641](https://github.com/drawmeanelephant/boris/pull/641)
- A1 [boris#644](https://github.com/drawmeanelephant/boris/issues/644) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A14 [boris#645](https://github.com/drawmeanelephant/boris/issues/645) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A7 [boris#646](https://github.com/drawmeanelephant/boris/issues/646) → [#648](https://github.com/drawmeanelephant/boris/pull/648)
- A15 [boris#649](https://github.com/drawmeanelephant/boris/issues/649) → [#650](https://github.com/drawmeanelephant/boris/pull/650) — optional `#token=…&open=<project-relative path>` fragment; the shell opens that author-owned file on launch (UI-only; the host still prints the token-only launch line). Solipsist's `EditorURL.opening` already appends `open=` from `sourcePath` — #160 verified and closed (PR #198).
- A5 [boris#647](https://github.com/drawmeanelephant/boris/issues/647) → [#651](https://github.com/drawmeanelephant/boris/pull/651) — zero-write validation daemon under `validate --watch` (the RFC merged). Consumed as [#161](https://github.com/drawmeanelephant/solipsist/issues/161) (PR [#199](https://github.com/drawmeanelephant/solipsist/pull/199)); the contract is probed and recorded in [`docs/ENGINE-CONTRACTS.md`](../ENGINE-CONTRACTS.md) §1.

**Filed (2026-08-18):**

**File next:** none.

---

## Solipsist issue drafts (not boris)

The `editor-*.md` files below are **Solipsist** issue drafts for milestone 10
(macOS native editor improvements, #225–#238) — they file on
`drawmeanelephant/solipsist`, never on boris. Each carries its issue number
(children reference their tracker, #236); `Current state` is fact-checked
against the code it names, each has a `Gate`, and the cards are cut so no
two touch the same lane in the same PR.

| Draft | Issue | Lane |
|-------|-------|------|
| [Find & Replace](editor-compose-find-replace.md) | [#225](https://github.com/drawmeanelephant/solipsist/issues/225) | `Sources/Compose/` |
| [Line Numbers Gutter](editor-compose-line-numbers.md) | [#226](https://github.com/drawmeanelephant/solipsist/issues/226) | `Sources/Compose/` |
| [Split Pane Resize + Auto-Save](editor-compose-split-resize.md) | [#227](https://github.com/drawmeanelephant/solipsist/issues/227) | `Sources/Compose/` |
| [Status Bar — Cursor + Word Count](editor-compose-status-bar.md) | [#228](https://github.com/drawmeanelephant/solipsist/issues/228) | `Sources/Compose/` |
| [Tab Key — Indent 2 Spaces](editor-compose-tab-key.md) | [#229](https://github.com/drawmeanelephant/solipsist/issues/229) | `Sources/Compose/` |
| [Preview WKWebView](editor-compose-preview-webview.md) | [#230](https://github.com/drawmeanelephant/solipsist/issues/230) | `Sources/Compose/` |
| [Toolbar Save Suspends Watch](editor-compose-toolbar-save-tree-write.md) | [#231](https://github.com/drawmeanelephant/solipsist/issues/231) | `Sources/Compose/` |
| [Editor Auto-Reconnect](editor-companion-reconnect.md) | [#232](https://github.com/drawmeanelephant/solipsist/issues/232) | `Sources/Companions/Editor/` |
| [Pages List Keyboard Nav](editor-reading-keyboard-nav.md) | [#233](https://github.com/drawmeanelephant/solipsist/issues/233) | `Sources/Play/Local/` |
| [Preview Pinch-to-Zoom](editor-preview-zoom.md) | [#234](https://github.com/drawmeanelephant/solipsist/issues/234) | `Sources/Companions/Preview/` |
| [Highlighting Edge Cases](editor-compose-highlight-edge-cases.md) | [#235](https://github.com/drawmeanelephant/solipsist/issues/235) | `Sources/Compose/` |
| [Accessibility (tracker)](editor-compose-accessibility.md) | [#236](https://github.com/drawmeanelephant/solipsist/issues/236) | design — five child issues below |
| [A-1 Compose toolbar + diagnostics](editor-accessibility-compose-toolbar.md) | [#239](https://github.com/drawmeanelephant/solipsist/issues/239) | `Sources/Compose/` |
| [A-2 Reading pane header](editor-accessibility-reading-header.md) | [#240](https://github.com/drawmeanelephant/solipsist/issues/240) | `Sources/Play/Local/` |
| [A-3 Preview toolbar](editor-accessibility-preview-toolbar.md) | [#241](https://github.com/drawmeanelephant/solipsist/issues/241) | `Sources/Companions/Preview/` |
| [A-4 Editor toolbar](editor-accessibility-editor-toolbar.md) | [#242](https://github.com/drawmeanelephant/solipsist/issues/242) | `Sources/Companions/Editor/` |
| [A-5 Mailbox sidebar counts](editor-accessibility-sidebar-counts.md) | [#243](https://github.com/drawmeanelephant/solipsist/issues/243) | `Sources/Chrome/` |
| [Editor UX Polish](editor-companion-ux-polish.md) | [#237](https://github.com/drawmeanelephant/solipsist/issues/237) | `Sources/Companions/Editor/` |
| [Go to Line (⌘L)](editor-compose-go-to-line.md) | [#238](https://github.com/drawmeanelephant/solipsist/issues/238) | `Sources/Compose/` |

Status (2026-08-21): all five accessibility children merged — #243 (PR
#244), #239 (PR #247), #240 (PR #249), #241 (PR #251), #242 (PR #252).
#236 tracker closed.

Do not ask: unifying `compiler` field names, library mode, relaxing
editor token/CSP, shipping `boris-editor` in the agent-pack.
