# Solipsist Help

Solipsist is a native macOS workstation for [Boris](https://github.com/drawmeanelephant/boris), the deterministic Zig graph-native publication compiler.

## Layout & Workflow

Solipsist organizes your workspace into three primary columns:

- **Sources (Left)**: Your publication repositories and content trees, accessed via security-scoped bookmarks. Use **File → Open…** (`⌘O`) to add a content folder.
- **Play (Middle)**: The publication graph rendered as a structured list of trunks and satellites from `graph.json`. Selection here updates the current noun.
- **Inspector (Right)**: Contextual metadata for the selection:
  - **Profile Section**: Direct, 1:1 view over `boris.json` (site URL, title, input format, publication targets). Saving writes the file.
  - **Page Section**: Entity id, parent, status, tags, relations, and layout slots from `completion.json`.
  - **Execution Section**: Local performance preferences (`jobs`, `incremental`, `quiet`) persisted in user defaults.

## Verbs & Diagnostics

The **Boris** menu provides coordinator verbs:
- **Plan**: Lint and declare profile targets (`boris plan --profile`).
- **Validate**: Artifact-free publication validation with structured report decoding.
- **Build IR**: Compile intermediate representation artifacts (`manifest.json`, `graph.json`, `completion.json`).
- **Build HTML**: Compile static HTML distribution.
- **Check**: Run documentation intelligence and unreferenced page analysis.
- **Impact**: Analyze ripple effects of changes to the selected page.
- **Stop**: Interrupt currently running engine subprocess with `SIGTERM`.

Diagnostics, warnings, and errors appear in the **Problems Pane** at the bottom of the Play column and are color-coded by exit code in the status bar.

## Companion Windows

- **Preview** (**View → Preview**, `⌥⌘P`): Companion web view hosting live Boris `watch --serve` previews.
- **Editor** (**View → Editor**, `⌥⌘E`): Companion web view hosting Boris editor tokens.
- **About Solipsist** (**Solipsist → About Solipsist**): Displays app version and active Boris engine location.

For architectural decisions and milestone details, see [ROADMAP.md](ROADMAP.md) and [HARNESS.md](HARNESS.md).
