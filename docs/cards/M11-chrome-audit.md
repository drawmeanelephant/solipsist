# Card M11-1 — Chrome and Help audit

**Milestone:** M11 · **Issue:**
[#124](https://github.com/drawmeanelephant/solipsist/issues/124) ·
**Lane:** Chrome / help. One worktree, one PR against `main`; branch
suggestion `feat/m11-chrome-audit`.

## Owns

- `docs/help.md` (and the in-app Help window only if it is a
  straight bind of that file)
- Empty-state / first-run copy in `Sources/Chrome/` and
  `Sources/Play/Local/` **copy only**
- Accessibility labels on mailbox rows / reading empty states if
  they are missing
- `docs/HARNESS.md` §7 “what ships today” if it still describes
  the pre-M10 window

## Do not touch

- `Sources/Engine/**`
- `Sources/Compose/**` internals
- `Sources/Companions/Editor/**` internals
- Coordinator / publish
- `Project.yml`
- #110 / #111 paths

## Why

`docs/help.md` still says “Sources (Left)” and “Play (Center): Pages,
Outputs, and Publish tabs.” That is the M3 window. Mail-body chrome
without Mail-body Help is a lie. Empty states that say “select a
source to view its publication” are the same lie.

## Do

1. Rewrite the spatial section: Settings → Sources, mailbox sidebar,
   reading place, drawer, Preview / Editor companions, Compose
   window. Use the nouns HARNESS §2 uses.
2. Audit `Commands.swift` against Help. Every menu verb and every
   `.keyboardShortcut` gets a row. File → Edit Page, Compose `⌘⇧C`,
   mailbox language. Do not invent shortcuts.
3. First-run / No Sources / No Pages / unreachable source copy:
   point at Settings or Open… and `Stunts/happy`. Do not say “play
   tabs.”
4. Mailbox rows and reading empty states: a VoiceOver label if the
   control is otherwise silent. Do not restyle the window.
5. Leave EventSource-on-the-letter and the wide split **out**. Those
   are Later (M10-DESIGN D-S11 / rejected alternative 6–7).

## Do not

- Add a feature so Help has something to say.
- Restack the reading pane.
- Touch Engine or start a second watch.

## Gate

Open Help in the app. It describes mailboxes, the reading place,
Edit Page, and Compose. A new user sees empty-state copy that
matches. `SKIP_EMBED_BORIS=1 make build` + `make test` green.
