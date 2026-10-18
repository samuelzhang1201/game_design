# CI/CD Procedure 项目 CI/CD 流程说明

Each PR delivers one independently testable step, owned by its implementation session and sole Review session. Review fixes in-scope findings and merges only after every required check passes on the current HEAD. Follow `.codex/harness.md` for ownership and handoff.

每个 PR 只有一个可独立验证的小步骤，由实施和唯一 Review 两个 session 负责。Review 修复范围内问题，在当前 HEAD 的全部必需检查通过后直接合并。

## What runs 自动选择

`.github/workflows/tests.yml` runs on PRs against `main` and manual dispatch, without rerunning on merge. `harness-checks` always validates hook behavior, selector behavior, runner failure gates, shell/config syntax and guide caps. Pure guidance/harness changes start no Godot process.

工作流在面向 `main` 的 PR 和手动触发时运行。专用检查始终运行；仅文档或 harness 改动不启动 Godot。

`tools/select_gut_tests.py` compares the base commit with the checked-out tree, including deletions and both sides of renames. `tests/categories.json` is the ordered content manifest: expensive content overrides functional subsystem patterns. Functional suites retain single-formula, hand-computed, local save and short deterministic contracts even when they use balance tables or a campaign fixture. Mixed clearance/raid/siege scenario suites opt in as whole files because they also play extended campaign loops; their assertions remain intact. New long campaign/outcome sweeps belong in an opt-in category; new unclassified test directories fail closed.

选择器比较基准提交与当前工作树，包含删除及重命名前后的路径。分类按测试内容和子系统；公式、局部存档和短确定性测试保留在功能类别，新增长战役或调参扫描必须显式归入可选类别。

Known UI/map/ledger/war-room source paths select their functional consumers and bridges. Engine, shared fixtures, runtime prose (`RANDOM_EVENTS.md`, `game_story/`), CSV/data, assets, runner/selector changes and unknown runtime paths conservatively select all functional categories. A changed test selects its category, including a deleted test's surviving neighbors. Ordinary documentation and `.codex/` harness files need no GUT. Categories run sorted scripts together, preserving the map hover/picker setup order. This is category routing, not a transitive dependency graph.

已知展示子系统只选相关消费者；引擎、共享夹具、运行时叙事、CSV、资源和未知运行时路径保守选择全部功能类别。测试文件的修改或删除选择它所属的类别。普通文档和 `.codex/` 改动只跑专用检查。

Ordinary runs exclude `llm`, `simulation`, `gameplay` and `balance`. Dedicated LLM files remain on disk until HARNESS.3; runtime LLM code is unchanged. The 24-month conduct replay is in `tests/simulation/test_conduct_replay.gd`; the original file retains all ten unit tests.

普通运行不包含专用 LLM、长模拟、玩法情景和调参类别。24 个月军纪重放单独存放，原文件的十个单元测试全部保留。

## Explicit expensive checks 显式请求

When the plan/acceptance requires expensive coverage, add this exact standalone line to the PR body before CI runs:

计划或验收要求昂贵测试时，在 PR 正文添加独立一行：

```text
GUT_INCLUDE: simulation,gameplay
```

Available opt-in categories are `simulation`, `gameplay`, `balance` and (until deletion) `llm`. Request only what the step needs. Merely mentioning a category in prose does not opt in. Unknown names fail the selector. Editing the PR body triggers a fresh selection run, so adding or removing a request updates the required matrix. The manual Actions workflow runs all functional categories and accepts comma-separated extra names in its `include` input. An empty category creates no job.

只请求当前步骤需要的类别。修改 PR 正文会重新选择测试，添加或删除请求会更新必需矩阵。手动触发运行全部功能类别，并可在 `include` 输入框填额外类别；空类别不创建任务。

## Local commands 本地命令

Run affected checks on final inputs before committing; no routine full suite:

提交前针对最终代码运行相关检查，不例行跑全量：

```sh
./run_tests.sh                         # diff against origin/main
./run_tests.sh --base HEAD             # uncommitted tracked changes
./run_tests.sh --category engine-military
./run_tests.sh --test tests/engine/test_army_conduct_day.gd
./run_tests.sh --base origin/main --include simulation
./run_tests.sh --category simulation   # explicit campaign replay request
./run_tests.sh --fast                  # functional engine + ledger3d
python3 tools/select_gut_tests.py --base origin/main  # inspect JSON selection
```

Diff selection includes tracked working-tree edits; Git does not include untracked files. Add new files to the index or request them with `--test`. Explicit `--category`/`--test` requests select exactly those scripts and also serve as local opt-in for expensive content. Unknown options and missing scripts fail before import. The old global `--shard=I/N` interface is replaced by categories.

差异选择包含已跟踪文件的工作树修改，不含未跟踪文件；新文件需暂存或用 `--test` 显式请求。类别或文件请求只运行指定内容，拼错参数或缺少脚本会在导入前失败。

Harness-only checks use Python and shell, without Godot:

```sh
python3 -m unittest discover -s .codex/hooks -p 'test_*.py'
python3 tools/test_select_gut_tests.py
python3 tools/test_run_tests.py
python3 tools/test_run_with_timeout.py
sh -n run_tests.sh
bash -n .codex/hooks/session-start.sh
```

## Gates and deadlines 检查和超时

Every selected category uses the same `run_tests.sh`: forced offline, bounded import/test phases, nonzero GUT exit propagation, ignored-script rejection, exact selected-script count, expected error count (zero without the local GDAI extension, two with it), and the existing narrow runtime-error allow-list. Empty selection succeeds before importing Godot. A timeout exits 124 and preserves the printed test log. `$GODOT` selects the binary; `TEST_TIMEOUT_SECONDS` overrides the per-phase deadline (local default 2700 seconds, CI 2100). CI keeps two import passes and a 75-minute job limit for two phases plus setup.

每个选中类别共用同一 runner，保留离线、导入和测试超时、退出码、解析、脚本数量、预期错误数和运行时错误门禁。空选择在导入前结束；超时返回 124 并保留日志。

`gut-tests` aggregates `harness-checks` and the selected matrix. It accepts skipped game jobs only when selection explicitly says no GUT is needed. Failed, pending, cancelled, missing or timed-out required checks never permit merge. A green aggregate proves the selected coverage, not an unrequested full/balance/campaign run. Cache misses can still spend time importing the art tree; these jobs do not replace visual review.

汇总只在专用检查及所选类别通过时成功；只有选择器明确无需 GUT 才允许跳过。绿色代表选中覆盖通过，不代表未请求的长模拟或全量通过，也不能代替视觉审查。
