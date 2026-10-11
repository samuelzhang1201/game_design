# CI/CD Procedure 项目 CI/CD 流程说明

Plain-language guide to how automated testing works in this project, for anyone (human or Claude Code) working on it. Chinese and English are paired paragraph by paragraph.

这份文档用通俗的语言说明本项目的自动化测试流程，给所有参与开发的人（包括 Claude Code）看。中英文逐段对照。

---

## 1. What runs, and when 流程是什么，什么时候跑

We use **GitHub Actions**, defined in [`.github/workflows/tests.yml`](.github/workflows/tests.yml). It runs the project's full GUT test suite (`./run_tests.sh`) automatically in the cloud.

我们用 **GitHub Actions** 来做自动化测试，配置文件是 [`.github/workflows/tests.yml`](.github/workflows/tests.yml)。它会在云端自动跑整个项目的 GUT 测试套件（`./run_tests.sh`）。

It triggers on two things:

它在两种情况下会触发：

- **`pull_request`** — every time a pull request is opened or updated against `main`. This is the main gate: it tells you (and anyone reviewing) whether the change is safe to merge.
  **`pull_request`** — 每次开 PR 或者往一个已开的 PR 里 push 新代码（目标分支是 `main`）时都会跑。这是主要的把关环节：告诉你和审核人这次改动能不能安全合并。
- **`workflow_dispatch`** — a manual "Run workflow" button on the Actions tab, for when you want to re-run the suite without pushing a new commit (e.g. to rule out a flake).
  **`workflow_dispatch`** — Actions 页面上的手动"Run workflow"按钮，想在不推新 commit 的情况下重新跑一次（比如怀疑是偶发性失败）时用。

It does **not** trigger on a plain push to `main` (e.g. after a PR merges) — merging already tested that exact commit on the PR, so testing it again on `main` would just burn Actions minutes for no new information.

它**不会**在直接 push 到 `main`（比如 PR 合并后）时触发——因为合并的这个 commit 已经在 PR 上测过了，在 main 上再测一次只是白白浪费 Actions 的分钟数配额，没有任何新信息。

It also **skips entirely** (no run at all, not even a pending check) when every changed file in the PR is one of:

它还会在以下情况**完全跳过**（压根不触发任何 run，也不会有 pending 的检查项）——条件是 PR 里改动的文件全部满足：

- a plain documentation file (`**/*.md` — `CLAUDE.md`, `docs/**`, `cicd_procedure.md`, etc.), or
  纯文档文件（`**/*.md`——比如各处的 `CLAUDE.md`、`docs/**`、`cicd_procedure.md` 等）；或者
- a CSV value tweak under `data/**/*.csv` — tests read their data through `tests/suite_data.gd`, never the live CSVs, so a tuning-number change there can't break a test.
  `data/**/*.csv` 下的数值调整——测试是通过 `tests/suite_data.gd` 读数据的，不会读真实的 CSV，所以单纯调一个数值不可能把测试搞挂。

**Exception**: `RANDOM_EVENTS.md` and everything under `game_story/**` are excluded from the doc skip — they're runtime game content (narration, event prose), not documentation, and have their own id-resolution tests, so a PR touching them still runs the full suite.

**例外**：`RANDOM_EVENTS.md` 和 `game_story/**` 下的所有文件，不算在"文档"豁免范围内——它们是运行时真正加载的游戏内容（叙事文本、事件文案），不是文档，而且有专门校验 id 是否能解析的测试，所以改到它们还是会照常跑全量测试。

If a PR mixes an ignored file (docs/CSV) with a real code change, the run still happens as normal — the skip only applies when *every* changed file matches.

如果一个 PR 里既改了文档/CSV，又改了别的代码，还是会正常触发全量测试——这个跳过规则只在**所有**改动文件都命中豁免条件时才生效。

## 2. What the workflow actually does 工作流具体做了什么

Each run, on a fresh `ubuntu-latest` GitHub-hosted machine:

每次运行，在一台全新的 `ubuntu-latest` GitHub 托管机器上：

1. **Checkout** the repo at the PR's commit.
   **检出（checkout）** PR 对应 commit 的代码。
2. **Cache / download Godot 4.7.** The Godot binary is cached across runs by version, so after the first run it's restored in seconds instead of being re-downloaded.
   **缓存/下载 Godot 4.7。** Godot 的二进制文件会按版本缓存，第一次跑完之后，后面的运行几秒钟就能恢复，不用重新下载。
3. **Cache the `.godot` import output.** Godot has to "import" every asset once before tests can run. The ~2.6GB art tree only needs to be reimported when the asset files or `project.godot` actually change (the cache key is a hash of those files) — otherwise the cached import is reused.
   **缓存 `.godot` 的导入产物。** Godot 跑测试前要先把所有素材"导入"一遍。这棵约 2.6GB 的美术资源树只有在素材文件或 `project.godot` 真的变了时才会重新导入（缓存的 key 是这些文件的哈希值）——否则直接复用缓存的导入结果。
4. **Run the full GUT suite** via `./run_tests.sh --shard=I/5` for I = 1..5, one after the other (`CC_FORCE_OFFLINE=1`, so no real OpenAI API call is ever made in CI). One Godot process running every test grows past the runner's ~7.9 GB and is killed (exit 143), so each shard (every 5th test script, sorted) is a fresh process; every shard runs even if an earlier one failed.
   **跑完整的 GUT 测试套件**：通过 `./run_tests.sh --shard=I/5`（I 从 1 到 5）依次运行，并设置 `CC_FORCE_OFFLINE=1`，保证 CI 里绝不会真的调用 OpenAI API。单个 Godot 进程跑完所有测试会涨到超过运行器约 7.9 GB 内存而被杀掉（退出码 143），所以拆成 5 份（按排序后每第 5 个测试脚本一份），每份都是新进程；即使前面某份失败，后面的也会继续跑。
5. Report **success or failure** as the `gut-tests` check on the PR.
   把**成功或失败**的结果，作为 PR 上的 `gut-tests` 检查项汇报出来。

On a cold cache (first run, or after a cache eviction) this takes roughly **30 minutes**, mostly spent downloading Godot and importing the full art tree. With a warm cache it's much faster — typically a few minutes, since only the test run itself remains.

缓存是冷的时候（第一次跑，或者缓存被清掉之后）大概要 **30 分钟**，大头是下载 Godot 和导入完整美术资源。缓存是热的时候会快很多——通常几分钟，因为只剩下跑测试本身这一步了。

## 3. What a developer (or Claude Code) needs to do locally 开发者（或 Claude Code）本地要做什么

You do **not** need to run the full `./run_tests.sh` before every commit anymore — CI does that on the PR.

你**不需要**再在每次 commit 前跑全量的 `./run_tests.sh` 了——CI 会在 PR 上自动跑这件事。

While iterating and before every commit, run the fast regression check instead:

开发迭代中、每次 commit 前，跑这个更快的 regression 检查就行：

```bash
./run_tests.sh --fast
```

This covers `tests/engine`, `tests/ledger3d`, `tests/llm` — the subsystems that change most and matter most for correctness. It only takes a fraction of the full run's time.

它覆盖了 `tests/engine`、`tests/ledger3d`、`tests/llm`——改动最频繁、对正确性影响最大的几个子系统。耗时只有全量跑的一小部分。

Reach for the full `./run_tests.sh` locally only when:

只有以下情况才需要在本地跑全量的 `./run_tests.sh`：

- You're trying to reproduce a failure CI reported, or
  你想复现 CI 报告的某个失败，或者
- Your change touches `tests/ui`, `tests/map3d`, or `tests/war_room` — directories `--fast` doesn't cover — and you want to check before pushing.
  你的改动涉及 `tests/ui`、`tests/map3d` 或 `tests/war_room`——这些是 `--fast` 不覆盖的目录——想在推送前先确认一下。

## 4. Reading the result on a PR 怎么看 PR 上的结果

Every PR shows a `gut-tests` check at the bottom of the page (or in the "Checks" tab):

每个 PR 页面底部（或"Checks"标签页）都会显示一个 `gut-tests` 检查项：

- ✅ **green / passed** — the full suite ran clean; the PR is safe to merge as far as tests are concerned.
  ✅ **绿色 / 通过** — 全量测试跑通过了，就测试这一块而言这个 PR 可以安全合并。
- ❌ **red / failed** — something broke. Click "Details" to see the log; `run_tests.sh`'s own output (error counts, which test failed) is usually enough to tell you what to fix.
  ❌ **红色 / 失败** — 有东西跑挂了。点"Details"看日志；`run_tests.sh` 自己的输出（错误数量、哪个测试失败）通常就能告诉你要修什么。
- 🟡 **pending / yellow** — still running. No need to wait around; GitHub will update the check automatically.
  🟡 **黄色 / 进行中** — 还在跑。不用一直盯着，GitHub 会自动更新这个检查项的状态。

## 5. Cost 成本

This repository is **private**, so Actions run-time counts against the account's monthly GitHub Actions minutes quota (Linux runners count at a 1x rate; the free tier is 2,000 minutes/month, more on paid plans — overage is billed). This is the reason the workflow only runs on `pull_request` and not on every push to `main`: testing the same commit twice bought no extra safety, only extra cost.

这个仓库是 **private（私有）** 的，所以 Actions 的运行时间会算进账号每月的 GitHub Actions 分钟数配额里（Linux runner 按 1 倍率计费；免费版每月 2000 分钟，付费版更多，超出部分按量计费）。这就是为什么 workflow 只在 `pull_request` 上跑，不在每次 push 到 `main` 时跑：对同一个 commit 测两次并不会多带来什么安全保障，只是多花钱。

The Godot binary and `.godot` import caches also use the repo's Actions Cache storage (10GB limit per repo, free; GitHub evicts the oldest caches once that fills up).

Godot 二进制和 `.godot` 导入缓存也会占用仓库的 Actions Cache 存储空间（每个仓库限额 10GB，免费；满了之后 GitHub 会自动清掉最旧的缓存）。

## 6. One manual step still pending 还剩一个手动步骤没做

Ideally `main` should require the `gut-tests` check to pass before a PR can be merged (branch protection). No tool available to this session can set that — it has to be done by a repo owner on github.com:

理想情况下，`main` 分支应该设置成"必须 `gut-tests` 通过才能合并 PR"（分支保护规则）。这件事目前没有工具能从这个会话里直接操作，需要仓库所有者在 github.com 网页上手动做：

**Settings → Branches → Add rule (for `main`) → check "Require status checks to pass before merging" → select `gut-tests`.**

**Settings → Branches → 新增规则（针对 `main`）→ 勾选"Require status checks to pass before merging" → 选中 `gut-tests`。**
