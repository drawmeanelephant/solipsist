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

Filed: A1/A14/A7/A5 → boris#644-#647. If you hit a new defect (exact
stderr, exit code, command line), write
`docs/issues/boris-A<N>-<slug>.md` in the same shape and open the
issue. Record the number at the top of the draft. The owner will get
it fixed.

Do **not** file: unifying `compiler`/`compiler_id`/`compilerId`,
library mode, relaxing editor CSP/token, shipping `boris-editor` in
the agent-pack, `plan --out`.

---

## Board — batch 1 all landed ✅

| # | Card | Status |
|---|------|--------|
| 0 | PR cop + file A1/A14/A7/A5 | rolling (boris#644-#647) |
| 1 | [contract-fixtures](contract-fixtures.md) | done (#8) |
| 2 | [preview-shell](preview-shell.md) | done (#9) |
| 3 | [editor-shell](editor-shell.md) | done (#23) |
| 4 | [lint](lint.md) | done (#24) |
| 5 | [assets](assets.md) | done (#27) |
| 6 | [P-subdomain](../P-subdomain.md) | ⛔ withdrawn — published on Cloudflare Pages instead (`https://solipsist.filed.fyi`); no Worker host |
| 7 | [help-sheet](help-sheet.md) | done (#29) |
| 8 | [dependabot](dependabot.md) | done (#21) |
| 9 | [issue-templates](issue-templates.md) | done (#22) |

New work lives in the [delegation queue](../queue/README.md) — batch 2
is landed. The queue is empty. Next pickable card is
[#78](https://github.com/drawmeanelephant/solipsist/issues/78) (ship,
build-lane only — not this lane).

Skip: fart app (`make fart` must keep failing). Skip GitHub-as-source.
Skip publication flows. Skip Wasm in the app.

When a card would need `BorisEngine` to grow a method, **stop** and
write a note on the PR — grind lane adds Engine methods.
