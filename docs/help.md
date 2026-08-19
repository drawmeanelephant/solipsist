# Solipsist Help

Solipsist is a native macOS workstation for [Boris](https://github.com/drawmeanelephant/boris), the deterministic Zig graph-native publication compiler.

## Spatial Layout

Accounts live in Settings. The main window is mailboxes, a reading place, and a drawer. Companion windows host surfaces Solipsist does not rewrite.

- **Settings → Sources**: The account book. Add, relocate, and remove local folders (`Solipsist → Settings…`). A source is a folder of Boris content, not a file tree. `File → Open…` (`⌘O`) and Open Recent write the same store. Try `Stunts/happy` first.
- **Mailboxes (Left)**: Each source is an account header. Under it: Pages, Outputs, Publish, Plan, Activity, and Content Audit. Selecting a header opens that source's Pages mailbox.
- **Reading (Center)**: The message list of the selected mailbox, plus a reading pane for the selected message. On Pages, pick a page to read it as a letter (the served page when Preview is up; a contract summary when it is not). The problems list under the reading place is where every coordinator job reports its exit and diagnostics.
- **Inspector Drawer (Right)**: Options, profile keys, page fields, and execution knobs of the current selection.

## Menu Reference

Every menu verb and keyboard shortcut:

### File

| Verb | Shortcut | Description |
| --- | --- | --- |
| New Project… | `⌘N` | Initialize a new Boris project in a folder (`boris init`) and add it as a source. |
| Open… | `⌘O` | Open a Boris publication folder as a source. Same store as Settings → Sources. |
| Clone Repository… | — | Clone a git URL into a chosen folder and add the result as a Local source. Also in Settings → Sources. |
| Open Recent | — | Re-open a folder from the system recent-documents list. Shows No Recent Folders when empty. Clear Menu wipes the list. |
| Relocate Source… | — | Point an unreachable source at its new folder (enabled when the selected source is stale). Also in Settings → Sources. |
| Remove Source | — | Remove the currently selected source from the workspace (enabled when a source is selected). Also in Settings → Sources. |
| Edit Page | — | Open the hosted Editor companion against the selected page (enabled when a page is selected). |

### Boris

| Verb | Shortcut | Description |
| --- | --- | --- |
| Plan | `⌘⇧L` | Run the Boris plan step to preview output targets. |
| Validate | `⌘⇧K` | Validate publication structure and HTML output. |
| Build IR | `⌘B` | Compile documents into the deterministic IR graph. |
| Build HTML | `⌘⇧B` | Build the HTML distribution from the IR graph. |
| Build All | `⌘⇧U` | Fan out every HTML target and edition in the publication profile. |
| Build This | — | Build the selected HTML target or edition (Outputs mailbox). |
| Check | — | Run static documentation intelligence and reference checks. |
| Impact | — | Analyze ripple effects of node changes across the graph (enabled when a page is selected). |
| Recipe Scale | — | Scale the selected Cooklang page (`boris recipe-scale`; enabled when a page is selected). |
| Publish to Standard.site | — | Prompt for an app password (stdin), `login --app-password`, then `publish`. Optional Keychain remember. |
| Verify Standard.site | — | Verify the current Standard.site publication (`boris standard-site verify`). |
| Standard.site Records | — | List Standard.site records for the publication profile. |
| Standard.site Sessions | — | List Standard.site login sessions. |
| Standard.site Smoke Test | — | Run the Standard.site smoke check. |
| Logout Standard.site | — | End the Standard.site session. |
| Publish to Nostr… | — | Prompt for nsec/hex (stdin), then `nostr plan` → `sign --key-stdin` → `publish`. Optional Keychain remember. |
| Package Archive | — | Build a `boris package` archive (`packages/`, checksums, machine-readable version). |
| Export Source RAG… | — | Run `boris-source-rag` to pack project source files for LLM upload into `source-rag/`, then reveal it in Finder. |
| Stop | `⌘.` | Cancel the running job (SIGTERM, then SIGKILL after 2s). With no job, stops preview watch. Tree-writing jobs freeze watch until they finish. |

### View

| Verb | Shortcut | Description |
| --- | --- | --- |
| Show Inspector, Hide Inspector | `⌥⌘0` | Toggle the Inspector drawer on the right. |
| Preview | `⌘⇧P` | Open the Preview companion window (live preview via `watch --serve` with loopback URL validation). |
| Editor | `⌘⇧E` | Open the Editor companion window (token-isolated host for `boris-editor`). |
| Compose | `⌘⇧C` | Open the Compose window (native Markdown / Textile / Cooklang editor for the selected page; Oliver-powered preview; Save flows into the coordinator's validate gate). |

### Help

| Verb | Shortcut | Description |
| --- | --- | --- |
| Solipsist Help | `⌘?` | Open this guide in the in-app Help window. |

## Companion Windows

- **Preview Companion (`⌘⇧P`)**: Live preview of the full site, powered by `watch --serve` with loopback URL validation. The reading pane reuses this same watch for the selected page; it does not start a second one.
- **Editor Companion (`⌘⇧E`)**: Token-isolated companion host for `boris-editor`. File → Edit Page opens it against the selected page.
- **Compose Window (`⌘⇧C`)**: Native compose surface for the selected page's source file — Markdown / Textile / Cooklang editing with heuristic highlighting, an Oliver-rendered preview split (live, debounced; Render Options mirror Oliver's `ParseOptions` — wikilinks, callouts, smart typography, footnotes, task lists, frontmatter policy, raw-HTML policy, XHTML profile), and save-triggered validate through the coordinator. The renderer binary is located via `SOLIPSIST_OLIVER_BIN` → app bundle → sibling of `boris` → dev checkouts. Language is auto-detected from the file; the picker overrides it per session.

For architecture and roadmap details, see [ROADMAP.md](https://github.com/drawmeanelephant/solipsist/blob/main/docs/ROADMAP.md).
