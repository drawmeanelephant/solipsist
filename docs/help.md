# Solipsist Help

Solipsist is a native macOS workstation for [Boris](https://github.com/drawmeanelephant/boris), the deterministic Zig graph-native publication compiler.

## Spatial Layout

Accounts live in Settings. The main window is mailboxes, a reading place, and a drawer. Companion windows host surfaces Solipsist does not rewrite.

- **Settings → Sources**: The account book (`Solipsist → Settings…` or `⌘,`). Add local folders, clone git repositories (`File → Clone Repository…`), or connect GitHub accounts via OAuth device flow (tokens stored securely in Keychain). A source is a folder of Boris content, not a raw file tree. `File → Open…` (`⌘O`) and Open Recent write the same store. Try `Stunts/happy` first.
- **Mailboxes (Left)**: Each source is an account header in the sidebar outline.
  - **Local sources**: Pages (expanding to nested trunk subfolders from `graph.parent`), Outputs, Publish, Plan, Activity, and Content Audit.
  - **GitHub sources**: Pages and trunk subfolders, Outputs, Publish, Plan, Activity, Content Audit, plus **Remote** (branch status, ahead/behind tracking, commit/push/sync), **Issues** (open repository issues), and **Pull Requests** (open PRs and authoring).
  - Selecting an account header opens that source's Pages mailbox.
- **Reading (Center)**: The message list of the selected mailbox, plus a reading pane for the selected message. On Pages, pick a page to read it as a letter — `Served` (green capsule) when the live preview watch is bound to this source, `Foreign` (orange capsule) when preview serves another source, and a contract-backed summary when preview is down. The badge in the letter header and the `Preview is serving another source` hint keep the single-watch reuse honest. Use `Copy ID` / `Copy Path` / `Reveal in Finder` in the summary, and tap relation chips to resolve via the graph.
- **Problems as a place**: The problems list under the reading place is where coordinator jobs and the live A5 `validate --watch` daemon report exits and diagnostics. Rows show severity chips (error red / info secondary), code capsules, and middle-truncated `path:line:column`. Right-click for **Copy**, **Copy as Markdown**, **Open in Compose at line**, and **Reveal in Finder** — a broken `[[wikilink]]` click selects Pages + that page and opens Compose at the reported line.
- **Inspector Drawer (Right)**: Context-aware options, profile keys, page fields, target settings, branch status, and execution knobs of the current selection. The toolbar belt (`Plan` `⌘⇧L` / `Validate` `⌘⇧K` / `Build IR` `⌘B` / `Build All` `⌘⇧U`) and the status bar (`source · verb · exit · engine`, red on non-zero, hover shows duration / timings) mirror the **Boris** menu.

## Mailbox Surfaces & Workflows

- **Pages & Trunk Folders**: The Pages mailbox lists all publication pages. When the decoded graph contains trunk folders, Pages expands into nested subfolders. Selecting a trunk folder filters the letter list to that trunk and its descendants.
- **Outputs**: Inspect HTML build targets and editions (IR, RAG, Context). Select a target to view theme, layout, sitemap, RSS, and LLMs metadata in the drawer.
- **Publish**: Manage publication targets, including Standard.site and Nostr publisher configurations.
- **Plan & Activity**: Review publication build plans and coordinator job run histories.
- **Content Audit**: Run structure, integrity, and relation checks across the publication graph (such as unreferenced pages or missing parents).
- **Remote (GitHub)**: Displays working copy status, current branch, ahead/behind commit counts relative to upstream, and provides Sync, Commit, and Push actions.
- **Issues (GitHub)**: Lists open GitHub issues for the repository with links to view and manage them in the browser.
- **Pull Requests (GitHub)**: Lists open pull requests with draft status and branch heads, and provides a `New Pull Request…` toolbar action to push upstream and open the PR authoring flow.

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
| Preview | `⌘⇧P` | Open the Preview companion window (live preview via `watch --serve` with loopback URL validation and SSE reload). |
| Editor | `⌘⇧E` | Open the Editor companion window (token-isolated host for `boris-editor`). |
| Compose | `⌘⇧C` | Open the Compose window (native Markdown / Textile / Cooklang editor for the selected page; Oliver-powered preview; Save flows into the coordinator's validate gate). |
| Pages | `⌘1` | Jump the selected source's sidebar to the Pages mailbox. |
| Outputs | `⌘2` | Jump the selected source's sidebar to the Outputs mailbox. |
| Publish | `⌘3` | Jump the selected source's sidebar to the Publish mailbox. |
| Plan | `⌘4` | Jump the selected source's sidebar to the Plan mailbox. |
| Activity | `⌘5` | Jump the selected source's sidebar to the Activity mailbox. |
| Content Audit | `⌘6` | Jump the selected source's sidebar to the Content Audit mailbox. |
| Select Next Source | `⌘⌥→` | Cycle the sidebar selection to the next source (wraps). |
| Select Previous Source | `⌘⌥←` | Cycle the sidebar selection to the previous source (wraps). |

The sidebar also carries a **Filter folders** search field: it narrows trunk folders under Pages by title (case-insensitive) while typed, and resets when cleared. Right-clicking a source offers Reveal in Finder, Copy Path, and Sync Now (GitHub sources).

### Format

| Verb | Shortcut | Description |
| --- | --- | --- |
| Zoom In | `⌘+` | Grow the Compose buffer type one step (11–21 pt ladder). Applies to the buffer, typing attributes, and the gutter digits. |
| Zoom Out | `⌘-` | Shrink the Compose buffer type one step (11–21 pt ladder). |
| Actual Size | `⌘0` | Restore the Compose buffer's default 13 pt type. |
| Line Numbers | — | Toggle the Compose line-number gutter (checked by default). Hiding it collapses its reserved padding. |

### Help

| Verb | Shortcut | Description |
| --- | --- | --- |
| Solipsist Help | `⌘?` | Open this guide in the in-app Help window. |

## Companion Windows

- **Preview Companion (`⌘⇧P`)**: Live preview of the full site, powered by Boris engine A1 `--watch-json` / `serve-started` stream with loopback URL validation and Server-Sent Events (SSE `event: reload`). The reading pane reuses this same watch stream for the selected page without starting a duplicate subprocess.
- **Editor Companion (`⌘⇧E`)**: Token-isolated companion host for `boris-editor`. File → Edit Page opens it against the selected page with `open=` parameter targeting the page's source path.
- **Compose Window (`⌘⇧C`)**: Native compose surface for the selected page's source file — Markdown / Textile / Cooklang editing with heuristic highlighting, an Oliver-rendered preview split (live, debounced; Render Options mirror Oliver's `ParseOptions` — wikilinks, callouts, smart typography, footnotes, task lists, frontmatter policy, raw-HTML policy, XHTML profile), and save-triggered validate through the coordinator. The renderer binary is located via `SOLIPSIST_OLIVER_BIN` → app bundle → sibling of `boris` → dev checkouts. Language is auto-detected from the file; the picker overrides it per session.

For architecture and roadmap details, see [ROADMAP.md](https://github.com/drawmeanelephant/solipsist/blob/main/docs/ROADMAP.md).
