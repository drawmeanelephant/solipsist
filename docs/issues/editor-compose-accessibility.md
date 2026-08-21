# Editor: Accessibility — VoiceOver + Keyboard Across Editor Surfaces (tracker)

**Track:** macOS native polish / accessibility
**Milestone:** 10 — macOS native editor improvements (post-M17 polish)
**Issue:** [#236](https://github.com/drawmeanelephant/solipsist/issues/236) (tracker)
**Lane:** design (this file) + five child issues. Does **not** own
`Sources/`. Children do.

## Why

VoiceOver support is missing in five **disjoint** places: the Compose toolbar
and diagnostics pane, the reading-pane header, the Preview toolbar, the
Editor toolbar, and the mailbox sidebar counts. They share a goal (macOS
accessibility) but own separate files in separate lanes, so one issue cannot
be worked in one worktree. Split like M13 (#142) / M14 (#143): this is the
tracker; each child is one lane, one worktree, one PR.

## Children

All five are independent — no child consumes another's file, state, or
selection. They can run in five worktrees at once.

| Child | Issue | Lane | Status | Gate (short) |
|-------|-------|------|--------|----------------|
| [A-1 Compose toolbar + diagnostics](editor-accessibility-compose-toolbar.md) | [#239](https://github.com/drawmeanelephant/solipsist/issues/239) | Compose | ✅ merged (PR #247) | Language picker label + hints + diagnostics rows |
| [A-2 Reading pane header](editor-accessibility-reading-header.md) | [#240](https://github.com/drawmeanelephant/solipsist/issues/240) | Reading | ⬜ not covered | header announces title + caption as one element |
| [A-3 Preview toolbar](editor-accessibility-preview-toolbar.md) | [#241](https://github.com/drawmeanelephant/solipsist/issues/241) | Preview companion | ⬜ not covered | URL / reload / open-in-browser labeled |
| [A-4 Editor toolbar](editor-accessibility-editor-toolbar.md) | [#242](https://github.com/drawmeanelephant/solipsist/issues/242) | Editor companion | ⬜ not covered | URL / connect / restart / nav / phase labeled |
| [A-5 Mailbox sidebar counts](editor-accessibility-sidebar-counts.md) | [#243](https://github.com/drawmeanelephant/solipsist/issues/243) | Mailboxes | ✅ merged (PR #244) | Pages + trunk rows announce counts from the stored graph |

Filed 2026-08-21 as #239–#243 (milestone 10). **Status as of 2026-08-21:**
#243 landed (merged in PR #244) and #239 landed (merged in PR #247);
#240/#241/#242 are untouched and pickable as-is. Close this tracker when
all five land.

## Shared nice-to-haves (not assigned — later)

- VoiceOver rotor (headings / links / lines) in the Compose editor.
- Dynamic Type scaling of the editor's monospaced font.
- High-contrast pass on the highlighter palette (WCAG AA).
- Switch Control reachability audit.

## Must not land (any child)

- A separate accessibility mode (accessibility is part of the main UI, not a
  toggle).
- A third-party accessibility library.
- New count plumbing for Outputs / Activity (the sidebar does not hold that
  data today).

## Gate (whole)

With all five children landed, VoiceOver (⌘F5) can navigate the Compose
window, both companions, and the sidebar without visual assistance: the
Language picker announces the current language and every toolbar control
announces a hint, a diagnostics row announces "Error on line 12: …", the
reading header announces title + caption as one element, and the Pages / trunk
rows announce item counts that update when the graph rebuilds (landed, #243).
`SKIP_EMBED_BORIS=1 make build` + `make test` green.
