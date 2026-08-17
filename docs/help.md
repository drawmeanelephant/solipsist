# Solipsist Help

Solipsist is a native macOS workstation for [Boris](https://github.com/drawmeanelephant/boris), the deterministic Zig graph-native publication compiler.

## Spatial Layout

Solipsist organizes its workspace into a three-column spatial model:

- **Sources (Left)**: Switch between opened Boris publication folders (`File → Open…` or `⌘O`) and dogfood test corpora under `Stunts/`.
- **Play (Center)**: Displays publication pages, node graph relationships, and generated artifacts derived from compiler contracts.
- **Inspector Drawer (Right)**: Inspect publication configuration (`boris.json`), page frontmatter completion index (`completion.json`), and execution options.

## Menu Reference

Every menu verb and keyboard shortcut:

### File

| Verb | Shortcut | Description |
| --- | --- | --- |
| Open… | `⌘O` | Open a Boris publication folder as a source. |
| Remove Source | — | Remove the currently selected source from the workspace (enabled when a source is selected). |

### Boris

| Verb | Shortcut | Description |
| --- | --- | --- |
| Plan | `⌘⇧L` | Run the Boris plan step to preview output targets. |
| Validate | `⌘⇧K` | Validate publication structure and HTML output. |
| Build IR | `⌘B` | Compile documents into the deterministic IR graph. |
| Build HTML | `⌘⇧B` | Build the HTML distribution from the IR graph. |
| Check | — | Run static documentation intelligence and reference checks. |
| Impact | — | Analyze ripple effects of node changes across the graph (enabled when a page is selected). |
| Stop | `⌘.` | Terminate any currently running compiler subprocess. |

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
