# M11 — Prove the Mail body (tracker)

**Milestone:** M11 · **Lane:** design (this file) + two child cards.
Does **not** own `Sources/` except the children.

Parent issue:
[#123](https://github.com/drawmeanelephant/solipsist/issues/123).
[#110](https://github.com/drawmeanelephant/solipsist/issues/110) /
[#111](https://github.com/drawmeanelephant/solipsist/issues/111)
stay ship. They do not expand into this.

## Why

M10 shipped the Mail shape. Help still describes a source list and
play tabs. Tests are contract decodes plus selection rules — nothing
asserts the letter URL, and there is no XCUI target. First-run copy
and empty states were written for the flatter chassis.

This milestone is **prove**, not **invent**. No new Boris surface. No
compose depth. No GitHub source. No Apple notarize.

## Children

| Card | Issue | Lane | Gate (short) |
|------|-------|------|----------------|
| [M11-1 Chrome](M11-chrome-audit.md) | [#124](https://github.com/drawmeanelephant/solipsist/issues/124) | Chrome / help | Help + empty states describe the window that ships; menus match |
| [M11-2 Tests](M11-test-pass.md) | [#125](https://github.com/drawmeanelephant/solipsist/issues/125) | Tests | Help-vs-Commands test; reading-page URL; no XCUI required |

They can run in parallel: 11-1 owns `docs/help.md` + empty-state
copy; 11-2 owns `Tests/` and small extractable helpers. If 11-2
needs a URL helper that lives next to Play, extract it — do not
rewrite `ReadingPane`.

## Not this tracker

- #110 / #111 (Apple account)
- Compose depth (diagnostics, bundle `oliver`)
- GitHub as a source
- EventSource on the letter (named Later; D-S11)
- Width-adaptive list-beside-letter (named Later)
- Nested trunk mailboxes
- A from-scratch XCUI suite
- Growing `MainWindow` into a dump

## Gate

A person who has never seen this repo can launch, add `Stunts/happy`
from Settings or Open…, pick Pages, select a page, see a letter or
summary, run Validate, and read Help that matches those nouns.
`SKIP_EMBED_BORIS=1 make build` + `make test` green. Help-vs-Commands
test fails if a shortcut is undocumented.
