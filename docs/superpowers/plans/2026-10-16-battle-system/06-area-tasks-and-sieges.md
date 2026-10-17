# P6 画圈任务与围城 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WAR ROOM 可画圈下达四类真实任务，军队按收到授权自动执行，并支持跨月围城的五种战术。

**Architecture:** ArmyTasks保存授权、搜索覆盖和阶段；复用MarchPath/Sighting/RaidSystem，圈只是行动授权区。SiegeTactics在已有SiegeSystem上增加工程、封锁入口、谈判与资源分配，和野战共享军法/日事务。

**Tech Stack:** Godot 4.7、GUT、CSV、编辑器WAR ROOM资源、Blender器械。

**Spec:** [设计 §13–14、§16](../../specs/2026-10-16-battle-system-design.md)；[总计划](../2026-10-16-battle-system-implementation.md)。前置：P1–P5。

## Global Constraints

- 搜索默认保持距离并报告，可选接近并进入对峙；敌方仍可主动强迫接触。
- 圈选不揭示隐藏敌军/城镇，装饰性war_plans不直接变成真实命令。
- 本地命令就地送达；远程确认/修改/取消均须信使到达；国王起点规则适用。
- 俘虏随军，无疲劳、紧急弃营、失联；自动返程也不能跳过一日拔营。
- 围城可一月以上；五战术为地道、投石机、云梯、劝降、封锁补给。
- 遵守已有军法/协议、不自动强攻；遵守总计划引擎/数据/测试/视觉要求。

## Review Focus

1. 圈选菜单暴露隐藏目标：P6.1 `test_task_preview_does_not_reveal_hidden_state`。
2. 航线不可达还显示区域已搜完：P6.1 `test_search_keeps_unreachable_area_unsearched`。
3. 读档/编辑任务重复掠夺或摧毁：P6.1 `test_target_effects_are_not_repeated`。
4. 同批士兵同时挖地道造器械封锁：P6.2 `test_siege_labor_is_not_double_allocated`。
5. 援军只靠近城外就触发解围：P6.2 `test_relief_requires_an_open_route`。

---

## P6.1 授权区域与四类自动任务

**Create:** `scripts/engine/army_tasks.gd`、`scripts/engine/task_coverage.gd`、`data/army/task_kinds.csv`、`tests/engine/test_army_tasks.gd`、`tests/engine/test_task_coverage.gd`、`tests/ui/test_war_task_orders.gd`。

**Modify:** `scripts/engine/game_state.gd`、`scripts/engine/action_system.gd`、`scripts/engine/tick_engine.gd`、`scripts/engine/sighting.gd`、`scripts/engine/raid_system.gd`、`scripts/engine/siege_system.gd`、`scripts/engine/data_repository.gd`、`data/tables.csv`、`data/realm/order_costs.csv`、`scripts/ui/war_plan_desk.gd`、`scripts/ui/war_plan_form.gd`、`scripts/ui/war_room_screen.gd`、`scripts/war_room/war_plan_tool.gd`、`scripts/war_room/war_plan_geometry.gd`、编辑器 `scenes/war_room/war_plan_form.tscn`。

**Interfaces:**

```gdscript
# task: id/kind/unit_codes/center_x_m/center_y_m/radius_m/known_target_id/
# encounter_policy/supply_floor/return_target/revision/issued_day。
static func preview(repo: DataRepository, state: GameState, realm: String, task: Dictionary) -> Dictionary
static func issue(repo: DataRepository, state: GameState, task: Dictionary) -> Dictionary
static func receive(repo: DataRepository, state: GameState, task_id: String, revision: int) -> Dictionary
static func step_day(repo: DataRepository, state: GameState) -> Array
# 整数米分格；格大小来自CSV，几何覆盖并不等于发现全部敌军。
static func mark(coverage: Dictionary, cells: Array[Vector2i], day: int) -> void
static func searched_cells(coverage: Dictionary) -> int
```

保存每单位执行状态 queued/travelling/working/paused_battle/returning/completed/failed，received_revision、route、covered_cells及日期、已处理target+effect id、收益、失败原因、供给底线。新修订仅在到达该单位时替换其授权；一组多单位不假装同时收到。

- [ ] 写coverage幂等测试：

```gdscript
func test_coverage_counts_unique_cells() -> void:
    var coverage: Dictionary = {}
    TaskCoverage.mark(coverage, [Vector2i(1, 2), Vector2i(1, 3)], 10)
    TaskCoverage.mark(coverage, [Vector2i(1, 2)], 11)
    assert_eq(TaskCoverage.searched_cells(coverage), 2)
    assert_eq(coverage["1:2"], 11)
```

- [ ] 用SuiteData两份同已知情报但不同隐藏敌军位置的state调用preview，要求结果相同，包括按钮、费用、预计时长、可围城列表。未知城镇不因圈住就出现；圈内有多个已知城镇必须明确选一个。运行新测试见红。
- [ ] preview返回合法任务、具体作用对象、估算路程/信使时延、费用、风险、补给底线及返程点；非法空队/海军/半径/离图/敌情权限给可读原因。issue通过ActionSystem费用检查；确认后先pending旗，收到才received，不提前动兵。
- [ ] 搜索把可通行区域按格/路段稳定排序，以已搜日期和路程选下一目标，记录实际侦察足迹；不可达处单独标记未搜。发现敌人默认停留安全位置并发报告，可选接近则寻合法接触点；不把“保持距离”做成敌人无法追上。重搜可以发现移动敌军，但不会把旧搜索日期当永久视野。
- [ ] 劫掠只从真实有限库存扣粮/物资，同时限制携带容量、军法与秩序代价；摧毁只改存在设施的功能状态，桥断影响实际路径、仓库影响真实供给，收益记effect id。重复10次指向同空仓/已毁目标不发奖励、不再扣同一库存；若设施真实重建，新revision可再次合法作用。
- [ ] 路过圈外允许，只有执行袭击/破坏等行为受授权边界；不得为抄近路顺带攻打圈外目标。战斗中暂停任务，结束后依据部队剩余能力、军法和存活目标恢复/返程/失败，不能无限循环追逐圈外敌人。
- [ ] 补给底线包含返程耗粮及一日拔营；触底提前返程或报告无法返程。完成任务安全停留，随后符合条件自动驻营；改令、取消在信使抵达前旧令仍有效。测试营地返程、目标已消失、路径被毁、部分单位灭亡、多单位不同送达日、存档恢复。
- [ ] 画圈UI显示四类任务、遭遇策略、费用、范围和确认；手工假想兵棋与真实intel标记不同。旗显示pending/received/fighting/returning/completed，不以额外头顶图标污染真实兵人。编辑器完成静态界面，war_room层只发几何/选择signal。
- [ ] 跑army_tasks/coverage/raid/war_plans、war_room与UI测试、fast，更新 `scripts/war_room/guide/plans.md` 和engine regiments指南，提交 `feat: execute authorized area tasks from the war room`。

## P6.2 围城工程、封锁、强攻与契约

**Create:** `scripts/engine/siege_tactics.gd`、`scripts/engine/siege_terms.gd`、`data/battle/siege_tactics.csv`、`data/battle/siege_terms.csv`、`tests/engine/test_siege_tactics.gd`、`tests/engine/test_siege_terms.gd`。

**Modify:** `scripts/engine/game_state.gd`、`scripts/engine/siege_system.gd`、`scripts/engine/supply_lines.gd`、`scripts/engine/march_path.gd`、`scripts/engine/battle_events.gd`、`scripts/engine/battle_rules.gd`、`scripts/engine/data_repository.gd`、`data/tables.csv`、`tests/engine/test_siege.gd`。

**Interfaces:**

```gdscript
# allocations: tactic -> 非负整数人数；不得超过可分配人力。
static func allocate(repo: DataRepository, state: GameState, siege_id: String, allocations: Dictionary) -> Dictionary
static func step_day(repo: DataRepository, state: GameState, siege_id: String) -> Dictionary
# terms含deadline_day/open_routes/allowed_actions/troops/civilians/withdrawal。
static func propose(repo: DataRepository, state: GameState, siege_id: String, terms: Dictionary) -> Dictionary
static func relieved(repo: DataRepository, state: GameState, siege_id: String) -> bool
```

- [ ] 建立唯一 `GameState.sieges`，用已保存的递增序号生成 String ID，记录 town、参与双方、开始日、工程、入口、协议与整数 battle_id 引用。把当前分散在 ai_hosts 的 siege_progress/siege_days/siege_town 迁移到对应围城记录；同城同一围城合并参与者，host 只保留关联 ID。迁移重复运行不复制围城；旧强攻定时器不能在新授权规则之外自动发起进攻。
- [ ] 写fixture人力300，地道120+器械100+封锁80合法，再加云梯1不合法且保持原分配；其中被看守、伤病、已投入解围野战的人先扣除可分配总数。运行test_siege_tactics见红。
- [ ] 增加分批抵达用例：骑兵已到城外、步兵与器械仍在途中时，只有实际到位且可投入的人员与装备进入工程/封锁分配。未到位者保持真实行军状态，不能因同属一个host就获得围城位置、封锁贡献或工程产出。抵达后只从当日合法结算阶段起贡献，不补领此前进度；同日读档续跑不重复加入。复验现有army_clearance与siege用例，区分“先头到达”“实际部署”“整个host到齐”，不通过扩大距离阈值、瞬移后队或延长测试等待时间掩盖状态错误。
- [ ] 部分部队真实到位、合法驻守且有可投入人员后即可开始其有能力执行的围城作业，不以全部初始部队到齐作为启动门槛，也不增加固定部署等待日。后续增援仅增加实际可分配资源，不重置围城进度；全部现场部队离开则停止对应工程和封锁效果。测试先到100人、后续200人在途：工程可用人数先为100，到位后300；另有远方1000人始终不贡献，直到实际到位。仍需逐条检查战术资源与路线，100人不能凭围城状态自动全封大型城镇。
- [ ] 保存每条实际补给入口/路线的封锁状态、城内库存/士气、围城方库存、工程进度/损坏、deadline、已有协议、关联强攻与解围battle_id。围城不足以覆盖全部入口就保留漏入供给，不使用“进入围城即所有粮路关闭”布尔捷径。
- [ ] 实现五战术的独立投入与进展：

| 战术 | 真实输入 | 日结果/反制 | 结束或升级条件 |
|---|---|---|---|
| 地道 | 工兵、木料、工具、可挖地点 | 进度、坍塌/反地道风险 | 达标制造缺口机会；P4塌陷事件使用真实工程 |
| 投石机 | 器械、弹药、操作人力 | 城防损坏、误差与反击损失 | 城防阈值触发强攻机会，不自行冲锋 |
| 云梯 | 梯具、突击人力、准备 | 强攻准备，攻方暴露与守方优势 | 只有收到合法强攻命令才创建关联野战/攻城阶段 |
| 劝降 | 合法条件、传令与时间 | 接受/拒绝/反提案，保存收到时间 | 接受并履约后转交，不能点击即占城 |
| 封锁 | 足够驻军分配至实际路线 | 城内库存按真实入流−消费改变 | 投降/打通路线/撤围，不能凭空扣粮 |

- [ ] 工程计算fixture：100工兵、每人每日2进度，需求1000，5个完整日完成；同日重入不成第6次投入。城内粮100、日需10、未封入口流入4，第1天94，第10天40；全封10天变0，不能小于0；按人口需求解释士气后果。
- [ ] 强攻及解围结束保留围城id、工程与城内库存；野战伤亡不在围城日末再扣一次。围城天数跨30日继续，普通月末经济仍结算一次。至少一条40天受控基准展示能跨月，不硬设30天胜负。
- [ ] 协议逐条约定截止日、停火期间动作、是否继续封锁/挖掘、驻军/居民待遇和撤离；日期绝对日整数。relieved必须验证援军实际打开可用补给/撤离路线，邻近援军、单封信或隐藏军队都不算解围。既有安全撤离协议约束追击。
- [ ] 测试截止日前/当日/之后、条件不一致局部拒绝、已议定停火时非法强攻、地道事件取消工程、围城方饿粮、双方补给并发、多个城镇分开围城；跑siege/tactics/terms/supply/battle_save与fast，更新 `scripts/engine/guide/siege.md` 后提交 `feat: resolve siege tactics and conditional surrender`。

## P6.3 任务旗与围城工程演出

**Create:** `assets/3D/props/army_task_flags/`、`assets/3D/siege/trebuchet/`、`assets/3D/siege/ladder/`、`assets/3D/siege/tunnel/`；编辑器创建 `scenes/models/siege/trebuchet.tscn`、`ladder.tscn`、`tunnel.tscn`；`scripts/map3d/map3d_siege.gd`、`tests/map3d/test_map3d_siege.gd`。

**Modify:** `scripts/war_room/war_pennants.gd`、`scripts/war_room/war_intel_ink.gd`、`scripts/engine/game_art.gd`、`scripts/engine/battle_presentation.gd`、`scripts/ui/war_room_screen.gd`。

- [ ] 盘点已有投石机/梯具/旗素材，复用合格模型；交付四种任务旗、虚线真实情报兵棋与时间/来源展示。未知敌军不生成不可见但可碰撞/可hover的节点。
- [ ] 地道入口/弃土、投石机阵地、梯具、城防破损、围城传令信号按真实进度出现；器械有装填/发射/复位。模型直接落地、避开道路/水体，尺寸与现有城墙可搭接。
- [ ] `Map3DSiege.apply_snapshot(snapshot: Dictionary) -> void` 只读过滤后的工程/战术；测试未建工程不可提前出现、损坏模型不自动复原、暂停冻结发射/投射物、快进不漏掉取消或投降。
- [ ] 真实窗口检查“圈选→信使→任务旗换状态→搜索接敌→围城→地道事件→强攻或劝降→战报”；记录平地/坡地城镇、1x/4x、相近国家色。跑map3d/war_room/UI相关目录和fast，保存P6证据后提交 `art: show area orders and siege engineering on the map`。

**阶段放行：** 四任务均有从下令到完成/失败的真实路径；五围城战术可分别投入并组合，不重复占人；实际封锁、逐条契约、跨月与解围均可复现。
