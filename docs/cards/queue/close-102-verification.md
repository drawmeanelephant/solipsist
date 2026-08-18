# Close #102 — verification findings

**Issue:** [#102](https://github.com/drawmeanelephant/solipsist/issues/102) (M10-4 "editor from the selected page")
**Status:** closed · code merged (PR #118) · follow-up in `feat/editor-open-page`

The live Gate was blocked on a `boris` + `boris-editor` pair in this
checkout. Fact-check against afterparty `editor/` (same pin as
`vendor/boris-agent-kit/MANIFEST.json`) found two leftovers the Gate
would have hit.

## Findings

1. **DIR was the content tree.** `EditorServer` launched
   `boris-editor <contentRoot>`. Afterparty `project.discover` requires
   a `content/` directory *under* DIR, so `Stunts/happy/content` fails
   with "has no content directory". DIR is now the project folder
   (`workingDirectory`).
2. **`EditorURL.parse` rejected a second fragment key.** The Svelte
   shell reads the hash with `URLSearchParams` and takes only `token`;
   extra keys are ignored. A15 ([boris#649](https://github.com/drawmeanelephant/boris/issues/649))
   proposes `#token=…&open=<project-relative path>`. The parser now
   matches `URLSearchParams`, and Edit Page appends `open=` from the
   selected `sourcePath` (`index.md` → `content/index.md`, same rules
   as `file_api.validatePath`). Today's shell ignores `open=`; when A15
   ships, Edit Page lands on the file.

## Lane split (close-out)

- **#100** — toolbar gate + `sourcePath` on the noun type
- **#101** — double-click / Return gestures + `noun.sourcePath` write (PR #113)
- **#102** — `File → Edit Page` verb + editor header (title + sourcePath) + nav chrome (PR #118)
- **A15** — `boris#649` filed upstream; Solipsist consumes `open=` and
  does not invent a different query/fragment

## Still true from the original Gate

Link-out, paste-`BORIS_EDITOR_URL=`, Restart Host, and SIGTERM on
close are unchanged. `SKIP_EMBED_BORIS=1 make build` + `make test`
must stay green on the follow-up.
