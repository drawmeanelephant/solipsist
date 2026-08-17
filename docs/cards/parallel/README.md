# Parallel lane — stay busy, stay out of the way

For the external agent (PR cop + background cards). The grind lane
owns Play, Inspector, Engine, Models, Spike, and `MainWindow`. You do
not.

先读这个。**禁止**改这些路径：

- `Sources/Play/`
- `Sources/Inspector/`
- `Sources/Engine/`
- `Sources/Models/`
- `Spike/`
- `Sources/Chrome/MainWindow.swift`
- `Sources/Chrome/InspectorDrawer.swift`
- `Sources/Workspace/`（除了只读）
- 任何 `boris` 仓库（只提 issue，禁止 PR / 禁止改代码）

可以改：`Sources/Companions/`、`Tests/`、`site/`、`.github/`（在现有
CI 上加 job，不要拆 `spike`/`app`）、`scripts/`（不要改
`embed-boris.sh` 的搜索顺序）、`docs/cards/parallel/`、
`docs/issues/` 新草稿。

每个 card 一个 branch / worktree，对 **`main`** 开 PR。不要
`git add -A`。不要提交 `SUPPORT-NOT-FOR-GITHUB/`。

---

## Standing job — PR cop

You own the open PRs against `main`. Grind lane will keep shipping
new ones.

1. Rebase onto `origin/main` when CI is stale or the branch drifted.
2. Do not merge red CI. Do not bypass branch protection.
3. Stacked PRs: merge the base first (`#2` engine, then retarget
   inspector `#3` onto `main`). Play `#5` is independent.
4. If GitHub 5xx, wait and retry. Do not force-push `main`.
5. Review comments that are factual (wrong path, failed gate) get a
   fixup commit. Taste arguments leave for the grind lane.

## Standing job — Boris issues

Anything the compiler does wrong or underspecifies is a **draft in
`docs/issues/`**, then a GitHub issue on `drawmeanelephant/boris`.
Never a patch to boris.

File these first (bodies are ready):

1. [A1](../../issues/boris-A1-watch-events.md) `--watch-json` + `serve-started`
2. [A14](../../issues/boris-A14-editor-launch-contract.md) editor URL + SIGTERM
3. [A7](../../issues/boris-A7-workspace-rule.md) containment docs

Then A5 as a **discussion**, not a patch.

If you hit a new defect (exact stderr, exit code, command line), write
`docs/issues/boris-A<N>-<slug>.md` in the same shape and open the
issue. Record the number at the top of the draft. The owner will get
it fixed.

Do **not** file: unifying `compiler`/`compiler_id`/`compilerId`,
library mode, relaxing editor CSP/token, shipping `boris-editor` in
the agent-pack, `plan --out`.

---

## Board (pick from the top when idle)

| # | Card | Owns | Gate |
|---|------|------|------|
| 0 | PR cop + file A1/A14/A7 | `docs/issues/` headers only | issues exist on boris; PRs green or restacked |
| 1 | [contract-fixtures](contract-fixtures.md) | `Tests/`, `Project.yml` test target only | `xcodebuild` test target decodes checked-in JSON |
| 2 | [preview-shell](preview-shell.md) | `Sources/Companions/Preview/` | Preview window loads a typed URL; no `Process` |
| 3 | [editor-shell](editor-shell.md) | `Sources/Companions/Editor/` | Parses `BORIS_EDITOR_URL=`; no spawn |
| 4 | [lint](lint.md) | `.swiftformat` / `.swiftlint.yml`, CI job `lint` | lint job on PRs; no mass reformat of grind paths in the same PR |
| 5 | [assets](assets.md) | `Sources/Assets.xcassets` or `Solipsist/Assets.xcassets` | app has an icon; `make build` still works |
| 6 | [P-subdomain](../P-subdomain.md) | `site/` | public URL, no GitHub required |
| 7 | [help-sheet](help-sheet.md) | `docs/help.md` + Help menu opening it | Help → Solipsist Help shows the sheet |
| 8 | [dependabot](dependabot.md) | `.github/dependabot.yml` | weekly Actions bumps |
| 9 | [issue-templates](issue-templates.md) | `.github/ISSUE_TEMPLATE/` | bug + boris-relay templates |

Skip: fart app (`make fart` must keep failing). Skip GitHub-as-source.
Skip publication flows. Skip Wasm in the app.

When a card would need `BorisEngine` to grow a method, **stop** and
write a note on the PR — grind lane adds Engine methods.
