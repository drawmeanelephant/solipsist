# Solipsist Help

Solipsist is a native macOS workstation for [Boris](https://github.com/drawmeanelephant/boris), the deterministic Zig graph-native publication compiler.

## Spatial Layout

Solipsist organizes its workspace into a three-column spatial model:

- **Sources (Left)**: Switch between opened Boris publication folders (`File → Open…` or `⌘O`) and dogfood test corpora under `Stunts/`.
- **Play (Center)**: Pages, Outputs, and Publish tabs. The problems list under play is where every coordinator job reports its exit and diagnostics.
- **Inspector Drawer (Right)**: Inspect publication configuration (`boris.json`), page frontmatter completion index (`completion.json`), and execution options.

## Menu Reference

Every menu verb and keyboard shortcut:

### File

| Verb | Shortcut | Description |
| --- | --- | --- |
| New Project… | `⌘N` | Initialize a new Boris project in a folder (`boris init`) and add it as a source. |
| Open… | `⌘O` | Open a Boris publication folder as a source. |
| Remove Source | — | Remove the currently selected source from the workspace (enabled when a source is selected). |

### Boris

| Verb | Shortcut | Description |
| --- | --- | --- |
| Plan | `⌘⇧L` | Run the Boris plan step to preview output targets. |
| Validate | `⌘⇧K` | Validate publication structure and HTML output. |
| Build IR | `⌘B` | Compile documents into the deterministic IR graph. |
| Build HTML | `⌘⇧B` | Build the HTML distribution from the IR graph. |
| Build All | `⌘⇧U` | Fan out every HTML target and edition in the publication profile. |
| Build This | — | Build the selected HTML target or edition (Outputs tab). |
| Check | — | Run static documentation intelligence and reference checks. |
| Impact | — | Analyze ripple effects of node changes across the graph (enabled when a page is selected). |
| Publish to Standard.site | — | Run `boris standard-site publish` for the selected source. |
| Publish to Nostr… | — | Run `boris nostr plan` for the selected source (sign/publish is not wired yet). |
| Stop | `⌘.` | Cancel the running job (SIGTERM, then SIGKILL after 2s). With no job, stops preview watch. Tree-writing jobs freeze watch until they finish. |

### View

| Verb | Shortcut | Description |
| --- | --- | --- |
| Show/Hide Inspector | `⌥⌘0` | Toggle the Inspector drawer on the right. |
| Preview | `⌘⇧P` | Open the Preview companion window (live preview via `watch --serve` with loopback URL validation). |
| Editor | `⌘⇧E` | Open the Editor companion window (token-isolated host for `boris-editor`). |

### Help

| Verb | Shortcut | Description |
| --- | --- | --- |
| Solipsist Help | `⌘?` | Open this guide in the in-app Help window. |

## Companion Windows

- **Preview Companion (`⌘⇧P`)**: Live preview powered by `watch --serve` with loopback URL validation.
- **Editor Companion (`⌘⇧E`)**: Token-isolated companion host for `boris-editor`.

For architecture and roadmap details, see [ROADMAP.md](https://github.com/drawmeanelephant/solipsist/blob/main/docs/ROADMAP.md).
