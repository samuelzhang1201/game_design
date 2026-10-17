# 战斗系统分阶段实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把已批准的战斗设计落实为七个可独立验证的阶段，每阶段一起交付规则、界面、美术和验收证据。

**Architecture:** 先统一可暂停、可保存的日结算，再接军队人员、国王与营地、战斗规则、俘虏和区域任务。Godot 引擎决定结果，3D 地图与 WAR ROOM 读取经过情报过滤的展示数据；Blender 与 Qwen 只生产资产。

**Tech Stack:** Godot 4.7、typed GDScript、GUT、CSV、单 JSON 存档、Blender、ComfyUI/Qwen。

**Spec:** [已批准的完整设计](../specs/2026-10-16-battle-system-design.md)。本文状态：**实施计划待用户审阅。**

文档结构：1份总计划、7份阶段子计划、20个实施任务。先审阅下方阶段总览；每个子计划均列出文件职责、接口、代码步骤、美术交付、具体测试数据和阶段放行条件。以下内容是实施要求，不是测试通过或资产制作完成的声明。

## Global Constraints

- 普通野战目标 3–5 个游戏日；一天 8 秒，支持 1/2/4 倍速；30 天一月。无独立战斗时钟、自动慢速或五轮强制平局。
- 没有疲劳度、紧急弃营、暂时失联人员、押送后方选项；国王不会被俘。拔营占完整一个游戏日。
- 普通单位贵族比例最高 10%，包含唯一贵族指挥官；征兵直接花钱。获释俘虏成为平民，重新征募才能服役。
- 战前协议逐条达成且必须遵守；只有已收到的军法生效。紧急事件由在场玩家或不在场时的指挥官处理。
- 引擎纯 RefCounted；引擎状态仅存整数、字符串及可 JSON 编码容器；随机只经引擎拥有的种子流；UI 不直接写状态。
- 所有数值与费用进入 CSV；外观进入编辑器资源。新增 `.tscn/.tres` 外观通过 gdai 编辑器制作，不文本拼接。
- 只有现有 3D 战略地图；不制作独立 Blender 战场或第二套战斗地图。无兵人头顶数字、血条、图标。
- 本计划中的手算数值是隔离测试夹具；不把它们暗中认定为最终平衡数值。
- 执行时遵守 PRD §6 与优先地图外观路线。当前请求授权编写计划，未授权绕过发布顺序。

## Review Focus

1. 月末遭遇暂停后重复月薪、行军或伤亡：P1.1/P1.2 的日事务及月末测试。
2. 国王移动导致远程军令瞬移，或拔营当天同时全速行军：P3.1/P3.2 的派发快照与时间边界测试。
3. 新军法、援军或主将更换绕过既有协议：P4.1 的协议快照与合法性测试。
4. 投降、释放、交换及俘获者覆灭产生重复人口：P5.1/P5.2 的逐人群守恒与唯一持有测试。
5. 通过搜索预览、模型数量或战报提前看见敌情：P6.1/P7.1 的展示数据等价与隐藏状态测试。

---

## 1. 阶段总览与交付顺序

| 阶段 | 代码与可操作结果 | 本阶段美术交付 | 放行条件 |
|---|---|---|---|
| [P1 日结算与暂停](2026-10-16-battle-system/01-clock-and-save.md) | 普通日、月末同一可续跑事务；首次接敌暂停；存档恢复 | 沿用现有兵人，完成遭遇提示与暂停交互 | 暂停零伤亡；恢复不重扣；8/4/2 秒一天 |
| [P2 指挥官与征兵](2026-10-16-battle-system/02-roster-and-recruitment.md) | 唯一指挥官、家族、主将、付费贵族比例、真实人员账 | 玩家与开局入侵方的 Qwen 手绘头像；平民/贵族与国家色样张 | 600 人含 30 贵族时仍总计 600；比例、资金、人口守恒 |
| [P3 国王与营地](2026-10-16-battle-system/03-king-and-camps.md) | 国王真实移动、派信原点、临阵增益、自动驻营和一日拔营 | 独立国王模型与动作；营地建/驻/拔营资产 | 本地与远程时序准确；国王撤离不救走军队 |
| [P4 阵型、协议与战中决策](2026-10-16-battle-system/04-battle-rules-orders-events.md) | 四阵型、逐条交涉、五命令、逐日损失、在场事件与远程报告 | 阵线、传令官、死战旗；六类事件插图；首套可用接战演出 | 法律不可绕过；费用只付一次；正常野战基准达 3–5 天 |
| [P5 俘虏与战报](2026-10-16-battle-system/05-prisoners-and-reports.md) | 捕获归属、赎金/交换/释放、供给与不可变战后快照 | 投降、看守与随军俘虏表现；结算卡 | 人数完整守恒；国王例外；远程战报按送达显示 |
| [P6 画圈任务与围城](2026-10-16-battle-system/06-area-tasks-and-sieges.md) | 搜索/劫掠/摧毁/围城自动执行；五围城战术 | 四任务旗、情报虚线棋、围城器械与工程阶段 | 不泄露敌情；任务不重领收益；围城可持续跨月 |
| [P7 演出整合与交付](2026-10-16-battle-system/07-art-and-release.md) | 全流程集成、旧存档升级、平衡与性能回归 | 步/弓/骑动作完善、国家色全覆盖、营地和围城统一风格 | 真实窗口视觉审查、性能预算、CI、全新克隆可运行 |

依赖顺序：P1 → P2 → P3 → P4 → P5 → P6 → P7。肖像生产可在 P2 的人物清单冻结后与后续代码并行；营地和器械制作可在其状态接口确定后并行。修改 `GameState`、`TickEngine`、`ActionSystem`、`DataRepository` 的工作按阶段串行集成，不让多个执行者同时改同一入口。每阶段可在开发分支运行并验收，但全部通过 P7 才算本次功能完整发布，不能把缺头像、缺动作或临时按钮当最终交付。

P1 不新增平衡规则；P2/P3 提供后续依赖；P4 能独立进行新野战；P5 完成战争后果；P6 完成任务入口与围城；P7 不承担前面阶段漏掉的功能。

## 2. 开始实施前的工作区与基线

- [ ] 读当前实际存在的根与子系统 `AGENTS.md`；若子目录仍使用 `CLAUDE.md`，同时读该文件及其 Topic guides。不得为了计划统一改名。
- [ ] 读 `docs/design/PRD.md` §6、`docs/design/DATA_ARCHITECTURE.md`、相关旧系统 spec 和本次新设计。新设计覆盖冲突旧规则，但不授权扩展到亲卫、继承或刺杀。
- [ ] 用 `git status --short`、`git branch --show-current`、`git log -3 --oneline` 检查现场。编写计划时，共享 checkout 在 `codex/automatic-unit-behavior-menu`，有他人改动；不得切换、清理或提交它们。实施按 using-git-worktrees 技能建立/复用隔离工作区，再以实际最新基线为准。
- [ ] 把本组计划和已批准设计带入实施分支。设计曾保存于 `codex/battle-system-design` 的 `2e8aeb8bd6f0d9af865cc147f5115e3ad895fd12`；使用当前获批文本，避免覆盖后续修订。
- [ ] 运行 `./run_tests.sh --fast` 保存基线结果。先前检查曾有 army stance 菜单与本地 `hero_compare.gd` 数据路径失败；这不是允许忽略失败的名单，必须在当前隔离基线重测、定位并分开记录。
- [ ] 核对当前已移除的手动 army behaviour 菜单；本次只增加真实战斗/任务上下文命令，不恢复旧占位行为入口。

## 3. 共同开发与验收流程

每个子任务依次：写反例 → 运行指定测试见红 → 实现核心接口 → 同一测试见绿 → 本阶段局部测试 → `./run_tests.sh --fast` → 定向暂存并提交。已有缺陷与新引入失败都要有明确结果，不能以“原来就红”宣布通过。

单文件 GUT 命令模板（把路径换成子计划明确列出的测试文件，不修改测试框架）：

```bash
CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_day_resolution.gd -gpre_run_script=res://tests/pre_run.gd -gpost_run_script=res://tests/post_run.gd -gexit
./run_tests.sh --fast
```

受影响 UI/地图/WAR ROOM 另跑对应目录，不能认为 `--fast` 已覆盖：

```bash
CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/ui,res://tests/map3d,res://tests/war_room -ginclude_subdirs -gpre_run_script=res://tests/pre_run.gd -gpost_run_script=res://tests/post_run.gd -gexit
```

检查 GUT 实际执行了新增脚本，没有 `Ignoring script` 或意外 `SCRIPT ERROR`。插件存在时沿用仓库允许的 2 个插件探测错误，不放宽错误白名单。头less 测试只验证逻辑，不能用于拍 3D 截图。完整 `./run_tests.sh` 留给 PR CI，只有复现 CI 失败才本地全跑。

每阶段证据保存在 `docs/reviews/battle-system/P1.md` 至 `P7.md`（实施时创建）：提交号、测试命令/结果、关键手算、截图/视频路径、视觉判定、未通过项。美术修改使用 visual-review：真实窗口、2–3 方案对照、关键裁切、独立审查；先单件样张再批量。美术证据不能拿 headless 渲染或脱离游戏光照的 Blender 图替代。

每阶段形成独立可审查的提交组；阶段PR按依赖顺序指向 `main`，后续阶段先等待前置合并或采用明确的堆叠分支，避免把未审查的依赖重复提交。最终集成通过P7后才视为完整交付；CI `gut-tests` 通过才合并。提交只含该阶段明确文件，不用 `git add .`。更新规则到对应子系统 guide，根文档只保留跨模块原则。

## 4. 共享状态与接口约定

| 数据/接口 | 唯一负责阶段 | 后续使用约束 |
|---|---|---|
| `GameState.day_resolution`；`TickEngine.resolve_day(state) -> Dictionary` | P1 | `blocked/complete`，完整日输出 journal 一起保存 |
| `Game.resolve_battle_decision(token, choice) -> Dictionary` | P1；P4 扩展处理器 | 验证后一次性应用，绝不自动启动时钟 |
| `GameState.military_rosters/military_cohorts`；`MilitaryRoster` | P2 | roster引用唯一cohort；批次原子写入，P5在押批次引用同一源账 |
| `GameState.king_state`；`KingSystem` | P3 | 真实整数坐标；派发瞬间冻结信使起点 |
| 部队 `camp_state`；`CampSystem` | P3 | 本日 movement gate + 日末处理；读档不会重新计时 |
| 战斗 `agreements/formation/action`；`BattleRules/BattleOrders/BattleEvents` | P4 | 协议快照优先；事件消费 token 由 P1 保存 |
| `GameState.prisoner_batches/battle_records`；`PrisonerSystem/BattleReport` | P5 | 当前归属可变，历史战报快照不变 |
| `GameState.army_tasks`；`ArmyTasks/SiegeTactics` | P6 | 不复用装饰性 `war_plans` 当执行状态 |
| `BattlePresentation.snapshot(repo, state, realm) -> Dictionary` | P4，P7 完善 | 唯一战斗展示投影；隐藏情报不传进地图节点 |

战斗 `battle_id` 沿用现有 int；命令、任务、事件 token 使用 String，不能为了接口统一把旧战斗 ID 改成字符串。围城新增 String ID 与野战 ID 分开保存，关联强攻／解围使用整数 battle_id。

所有新保存字段缺省值均可迁移。最终存档升级沿用仓库版本策略，目标新版本统一在实施分支一次确定，不能每阶段私自拒绝上一阶段存档。旧阵亡/伤兵是输入事实，迁移不能复活；不能从无法得知的旧数据伪造具名历史战果。

## 5. 设计覆盖索引

| 设计章节 | 实施与验收任务 |
|---|---|
| §1–2 目标及排除项 | 全部 Global Constraints；P7.3 禁止机制与完整流程检查 |
| §3 时间 | P1.1–1.2；P4.2 时长调校；P6.2 跨月围城 |
| §4 情报与权限 | P3.1；P4.3；P5.2；P6.1；P7.1 |
| §5–6 指挥官、征兵与军队构成 | P2.1–2.3；P5.1 人员守恒 |
| §7 阵型 | P4.1–4.2；P7.1 |
| §8 逐条交涉 | P4.1；P6.2 围城条约 |
| §9 命令 | P3.1 信使；P4.2；P5.1 投降 |
| §10 战场事件 | P4.3；P1.1 中断续跑 |
| §11–12 国王、营地 | P3.1–3.3 |
| §13 圈选任务 | P6.1 |
| §14 围城 | P6.2–6.3 |
| §15 伤亡、俘虏与战报 | P4.2；P5.1–5.3 |
| §16 视觉 | P2.3、P3.3、P4.3、P5.3、P6.3、P7.1–7.2 |
| §17 工程及存档 | P1；全部接口、P7.3 |
| §18 验收、§19 旧实现替换 | P7.3；各阶段直接替换而非双写 |
| §20 参数与技术默认 | P2.1、P3.2、P4.1–4.2、P5.1–5.2、P7.3 |

## 6. 本次审阅重点

七个阶段的复选框均是未来实施与验收要求。阶段放行需要同时具备可操作功能、该阶段资产和测试证据；只有代码通过不能代替美术签收。具体执行记录单独维护，避免把本计划误读为完成报告。

优先审阅以下依赖与成本：

| 项目 | 实施安排 | 对排期与验收的影响 |
|---|---|---|
| 人员与旧档迁移 | P2先统一crew、原籍和人数，再冻结指挥官名单 | 肖像数量按真实名册计算；不能先按旧单位数量批量出图 |
| 美术生产 | 每类先做样张并放入游戏，再批量生成/建模 | Qwen画像、国王和营地、战斗动作、围城器械分别在所属阶段交付 |
| 野战与围城调校 | P4建立野战基准，P6跨月围城，P7完整复测 | 3–5天是普通野战目标，不能硬设结束日期；金额和系数不是已验证定值 |
| 共享接口 | 日事务、人员账、军令、协议按依赖顺序集成 | 后续阶段不能复制另一套计时、收费或俘虏账来绕开前置接口 |
| 最终交付 | 规则测试、真实窗口视觉、性能、旧档与新克隆共同放行 | P7用于验证整合，不接收前面遗漏的必要功能或资产 |

请先看阶段顺序、每阶段交付物和放行条件，再看子计划里的文件与手算案例。P2 同时迁移人员、装备与人口来源，覆盖舰队和 royal train；这是实现贵族比例与人数守恒的前置，不新增海战玩法。本计划给出技术落地方式；数值仍需 P4/P7 的模拟与试玩校准，美术数量由 P2 清单计算，均不会冒充已验证结果。尤其需要先统一装备元素与实际人数，按人员上限重算拆分结果，再冻结指挥官与肖像清单；旧存档保留既有伤亡、库存和在途命令。

建议按阶段顺序实施，对日事务、人员守恒和协议权限安排独立审查；这些共享接口出错会影响存档与后续阶段。此次交付是供审阅的计划，文中的复选框表示验收要求，不表示功能已经完成。

文档自查已核对设计章节覆盖、阶段依赖和本地文档链接，并明确三处边界：旧伤亡按人员保留而非再次乘crew；当前在押人数与历史战报分开；围城只由实际到位资源贡献，不等待整个host到齐。P4完成地道事件的内容和插图，P6才验收其真实工程触发。游戏回归、视觉和性能验收按上述阶段执行，本次文档检查不代替这些测试。
