# Solipsist Help

Solipsist is a native macOS workstation for [Boris](https://github.com/drawmeanelephant/boris), the deterministic Zig graph-native publication compiler.

## Spatial Layout

Solipsist organizes its workspace into a three-column spatial model:

- **Sources (Left)**: Switch between opened Boris publication folders (`File -> Open...` or `⌘O`) and dogfood test corpora under `Stunts/`.
- **Play (Center)**: Displays publication pages, node graph relationships, and generated artifacts derived from compiler contracts.
- **Inspector Drawer (Right)**: Inspect publication configuration (`boris.json`), page frontmatter completion index (`completion.json`), and execution options.

## Coordinator Verbs

Execute compiler tasks directly from the menu:

- **Plan**: Run Boris plan step to preview output targets.
- **Validate**: Validate publication structure and HTML output.
- **Build**: Compile documents into deterministic IR graph and HTML distribution.
- **Check**: Run static documentation intelligence and reference checks.
- **Impact**: Analyze ripple effects of node changes across the graph.
- **Stop (`⌘.`)**: Terminate any currently running compiler subprocess.

## Companion Windows

- **Preview Companion (`⌘⇧P`)**: Live preview powered by `watch --serve` with loopback URL validation.
- **Editor Companion (`⌘⇧E`)**: Token-isolated companion host for `boris-editor`.

For architecture and roadmap details, see [ROADMAP.md](https://github.com/drawmeanelephant/solipsist/blob/main/docs/ROADMAP.md).
