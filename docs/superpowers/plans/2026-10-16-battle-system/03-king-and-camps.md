# P3 国王移动与营地 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 国王以真实位置指挥、派信和临阵；军队自动驻营，行动前完整拔营一天。

**Architecture:** KingSystem 管国王状态，CampSystem 管部队驻营状态。二者只在 P1 日阶段推进，地图节点读取状态与日内插值；现有 is_royal 军队标签不等于国王本人。

**Tech Stack:** Godot 4.7、GUT、CSV、Blender、编辑器场景。

**Spec:** [设计 §11–12、§16](../../specs/2026-10-16-battle-system-design.md)；[总计划](../2026-10-16-battle-system-implementation.md)。前置：P1、P2。

## Global Constraints

- 国王不会被俘，不播放被俘或阵亡动作；安全退离不改变军队败局。
- 没有疲劳度、紧急弃营；已驻营部队撤退也需完整一天拔营。
- 派发军令从国王当时实际位置出发，收报追踪国王真实位置；仓库不跟随国王移动。
- 世界仍8秒/天、1/2/4倍速；开WAR ROOM不移动国王。
- 美术直接落在现有3D地形、无底座；遵守总计划数据/测试/视觉/PR规则。

## Review Focus

1. 国王移动追溯更改已发信使原点：P3.1 `test_dispatch_origin_is_frozen`。
2. 到日末才收到命令却当天拔营完：P3.2 `test_late_order_packs_next_day`。
3. 暂停读档重复推进营地：P3.2 `test_pack_once_across_resume`。
4. 拔营遭袭营地瞬间复原：P3.2 `test_attack_preserves_pack_progress`。
5. 国王随军投降带全军逃走：P3.1安全退出测试，并在P5.1完整投降复验。

---

## P3.1 真实国王位置、信使与临阵范围

**Create:** `scripts/engine/king_system.gd`、`tests/engine/test_king_system.gd`、`tests/engine/test_king_couriers.gd`。

**Modify:** `scripts/engine/game_state.gd`、`scripts/engine/tick_engine.gd`、`scripts/engine/action_system.gd`、`scripts/engine/courier_system.gd`、`scripts/engine/missive_log.gd`、`data/army/balance.csv`、`data/realm/order_costs.csv`、`scripts/ui/game.gd`。

**Interfaces:**

```gdscript
# KingSystem；route 使用整数米 waypoint 字典；reason 必填。
static func position(state: GameState) -> Vector2i
static func set_route(repo: DataRepository, state: GameState, route: Array, reason: String) -> Dictionary
static func follow(repo: DataRepository, state: GameState, code: String) -> Dictionary
static func step_day(repo: DataRepository, state: GameState) -> void
static func present(repo: DataRepository, state: GameState, battle_id: int) -> bool
static func safe_departure(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary
```

保存 `king_state={x_m,y_m,route,follow_code,travel_state,last_advanced_day}`；出生点从玩家首都绑定读一次，之后不由 `current_location` 文本或选中地图决定。临阵距离从 CSV 读取。路径使用现有 MarchPath 通行能力；安全退离走合法最近退出路径，无路时保持受保护的国王状态并报告，绝不以传送军队解决。

- [ ] 写测试：国王(1000,2000)发军令，之后移到(4000,2000)，信使 origin仍(1000,2000)；在场军令本地收取不造信使，远方军令仍走真实路；信使费用一次，军队供给仓库不改位置。
- [ ] 增加范围纯测试：CSV指挥半径1000m，距离1000在场、1001不在场；仅选中战场、进入WAR ROOM或打开对话不改变 present。运行新文件见红。
- [ ] 给 ActionSystem 增加国王移动/随军/脱离命令，校验路线、权限和真实成本。普通命令及军法传播共用派发原点；已派信使的起点与已走路径保持不变，回报收件点按国王当前位置重规划，不瞬移已行旅程。
- [ ] 日阶段只调用一次 KingSystem.step_day；随军按目标实际移动/驻营状态跟随，不把 follow 当 teleport。国王独立离队不取消部队营地、任务或被俘结果。
- [ ] 被动临阵士气加成由距离和状态派生，离开即取消，不每天永久累加；付费主动鼓舞走P4命令。测试往返边界10次不积累士气，且国王安全退出只改 king_state/相关日志，不改军队人数、camp_state或battle winner。
- [ ] 读档测试保存途中路径、随军目标、已发与在途回信，恢复路径连续。跑king、courier_dispatch/ride、law_couriers、fast，提交 `feat: make royal movement and courier origins physical`。

## P3.2 自动驻营、供给效果与完整一日拔营

**Create:** `scripts/engine/camp_system.gd`、`tests/engine/test_camp_system.gd`。

**Modify:** `scripts/engine/army_system.gd`、`scripts/engine/enemy_ai.gd`、`scripts/engine/tick_engine.gd`、`scripts/engine/battle_system.gd`、`scripts/engine/courier_system.gd`、`data/army/balance.csv`、`tests/engine/test_army_hold_days.gd`。

**Interfaces:**

```gdscript
static func request_departure(state: GameState, code: String, effective_day: int, march_already_done: bool) -> void
static func can_march(state: GameState, code: String, day: int) -> bool
static func finish_day(repo: DataRepository, state: GameState, day: int) -> void
```

保存 `camp_state={phase,idle_days,build_progress,pack_start_day,move_not_before_day,last_updated_day,site}`；phase为none/building/camped/packing。构筑与拔营进度是状态，遇敌不清空。idle threshold先用设计建议2天进入表，标记为可调而不是固定承诺。

- [ ] 写无引擎依赖的时序测试：

```gdscript
func test_local_order_uses_one_full_day() -> void:
    var s := GameState.new()
    s.regiments["u"] = {"camp_state": {"phase": "camped"}}
    CampSystem.request_departure(s, "u", 10, false)
    assert_false(CampSystem.can_march(s, "u", 10))
    assert_true(CampSystem.can_march(s, "u", 11))

func test_late_order_packs_next_day() -> void:
    var s := GameState.new()
    s.regiments["u"] = {"camp_state": {"phase": "camped"}}
    CampSystem.request_departure(s, "u", 10, true)
    assert_false(CampSystem.can_march(s, "u", 11))
    assert_true(CampSystem.can_march(s, "u", 12))
```

- [ ] 运行见红后实现：pack_start_day=effective_day+(1 if march_already_done else 0)，move_not_before_day=pack_start_day+1。已packing收到新目的地只改路线，不能刷新计时或提前完成；每日移动先经过can_march。
- [ ] 日末只对野外、持续停留、非战斗且未临敌部队增长idle_days，达阈值开始building。玩家/敌军共用；城镇驻防不生成第二座野营。供给紧急返程、撤退、区域任务新路都走同一拔营gate。
- [ ] 营地防御按当前位置与真实构筑阶段派生；供给加成表现为降低损耗和储存改善，不增加不存在的粮。伤兵恢复沿用伤病规则，不能重建疲劳。离开营地不携带永久防御buff。
- [ ] 加入 `test_pack_once_across_resume`：同一天blocked/JSON往返/重复推进，packing日期不变；`test_attack_preserves_pack_progress`：部分收营遭袭保留进度和对应较低防护，撤退仍等待gate；禁止任何abandon捷径。
- [ ] 手算库存：起始100、正常消耗10、夹具营地只把运输损耗从2减到1，结束89而非凭空增加粮；0库存无供给线不变为正值。测试不把防御奖励重复应用到阵型与营地两个相同来源。
- [ ] 更新regiments/battle指南，跑camp、army_hold_days/march、courier_orders和fast，提交 `feat: stage camps and enforce a full packing day`。

## P3.3 国王与营地真实地图表现

**Create:** `scripts/map3d/map3d_king.gd`、`tests/map3d/test_map3d_king.gd`、`tests/map3d/test_map3d_camps.gd`；`assets/3D/characters/king/`、`assets/3D/buildings/field_camp/`，编辑器创建 `scenes/models/characters/king.tscn`、`scenes/models/buildings/field_camp.tscn`。

**Modify:** `scripts/map3d/map3d_unit_camps.gd`、`scripts/map3d/map3d_layer_couriers.gd`、`scripts/map3d/map3d_courier_palace.gd`、`scripts/map3d/map3d_view.gd`、`scripts/ui/game_root.gd`、`scripts/engine/game_art.gd`。**Create in editor:** `assets/3D/buildings/camp_models.tres`（当前引用存在但资源未安装）。GameRoot获取引擎状态并注入Map3DView，Map3DView再转发至各层；不在map3d目录新增Game依赖。

- [ ] 先盘点royal/cavalry/courier动作与营地资源，记录可复用项；王室部队外观不替代独立国王模型。模型制作加载建模/绑定/自然动画技能，减面时另用decimate-quality。
- [ ] 国王交付独立可选模型、行进/待机/观察/指挥/鼓舞动作；骑乘结构优先复用合格马匹但国王与马绑定职责明确。没有国王被俘、阵亡动画槽。
- [ ] 营地交付指挥帐、普通帐、粮车/物资、警戒与旗、royal标记；建/驻/拔营各阶段可展示。设施直接落地避水/路/建筑，不用统一圆底座；模型源放本对象 model_wip，GLB等运行资产提交。
- [ ] 地图层接口采用 `apply_snapshot(snapshot: Dictionary) -> void`，由UI桥送king和camp数据；不读Game，不写模拟。国王旗跟本人，离队后营地不留假王旗；信使动画从真实起点生成。
- [ ] map3d测试验证阶段到资产key映射、king节点独立、拔营遇袭不复原；真实窗口检查脚贴坡、帐篷规模、王旗移动、一天收营连续表现。至少平地/斜坡/近水三处检查；fast和相关map3d测试通过后提交 `art: integrate king and field camp states`。

**阶段放行：** 国王可独立移动、随军、离开、派信；营地自动搭建与一日拔营可见；无疲劳/弃营按钮；UI与真实位置一致。
