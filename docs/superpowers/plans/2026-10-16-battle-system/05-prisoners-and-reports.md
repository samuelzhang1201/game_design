# P5 俘虏与战后结算 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 战斗人数可完整核对，俘虏唯一归属实际俘获部队，所有获释者转为平民，战报按实际信息送达。

**Architecture:** PrisonerSystem 操作P2人员账与唯一俘虏批次；BattleReport保留战斗结束快照及后续处置引用。供给和地图跟随当前持有者，战报历史不随释放改写。

**Tech Stack:** Godot 4.7、GUT、CSV、JSON、编辑器UI、Blender复用动作。

**Spec:** [设计 §9、§15、§20](../../specs/2026-10-16-battle-system-design.md)；[总计划](../2026-10-16-battle-system-implementation.md)。前置：P1–P4。

## Global Constraints

- 无失踪或暂时失联人数；战后可战+留己方伤兵+阵亡+被俘=全部参战人次中不重复的人员总数。
- 俘虏属于抓到他们的部队；具名人物不自动归王室；没有押送后方。
- 释放、赎回、交换后均成为平民，重新征募才可服役；不参战承诺继续有效。
- 接受投降俘获全部存活军人含贵族/伤兵；国王不会被俘。
- 人数和钱粮整数、同操作幂等、原因完整；遵守总计划测试/视觉/PR规则。

## Review Focus

1. 俘虏中的伤兵重复加入己方伤兵：P5.1 `test_wounded_captives_are_not_double_counted`。
2. 多部队重复拥有同一批人：P5.1 `test_capture_has_one_holder`。
3. 俘获单位覆灭导致俘虏删除：P5.1 `test_holder_defeat_transfers_or_releases`。
4. 赎回重复到账或释放自动补员：P5.2 `test_settlement_releases_once_to_civilians`。
5. 远程卡片提前显示战报：P5.3 `test_result_is_visible_on_delivery`。

---

## P5.1 捕获、投降、守恒与持有者

**Create:** `scripts/engine/prisoner_system.gd`、`scripts/engine/battle_report.gd`、`tests/engine/test_prisoner_system.gd`、`tests/engine/test_battle_conservation.gd`。

**Modify:** `scripts/engine/game_state.gd`、`scripts/engine/military_roster.gd`、`scripts/engine/battle_system.gd`、`scripts/engine/battle_orders.gd`、`scripts/engine/army_system.gd`、`scripts/engine/enemy_ai.gd`。

**Interfaces:**

```gdscript
# capture_id含battle/round/source/序号；participants仅实际俘获方的贡献权重。
static func allocate(participants: Dictionary, count: int) -> Dictionary
static func capture(repo: DataRepository, state: GameState, capture: Dictionary) -> Dictionary
static func holder_defeated(repo: DataRepository, state: GameState, holder: String, controllers: Array[String]) -> Dictionary
# BattleReport：snapshot生成一次；battle_records内原快照不变。
static func snapshot(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary
```

batch保存 id/source_cohort/origin_realm/holder_code/commoners/nobles/named_ids/wounded_subset/capture_id/disposition。具名人物属于人数子集；同一capture_id不能再建第二批。存活伤兵计入源cohort的captured_current后从原队wounded移除；全部有效在押批次的人数合计必须等于对应captured_current。历史累计被俘人数只读事件或战报，不拿它充当当前在押人数。状态不存在missing字段。

- [x] 写分配测试见红；按code稳定排序后复用最大余数法：

```gdscript
func test_capture_has_one_holder() -> void:
    assert_eq(PrisonerSystem.allocate({"u_b": 3, "u_c": 2, "u_a": 5}, 7),
        {"u_a": 4, "u_b": 2, "u_c": 1})
    assert_eq(PrisonerSystem.allocate({"u_b": 1, "u_a": 1}, 1),
        {"u_a": 1, "u_b": 0})
```

- [x] participants来源只能是实际负责拦截/看守/接收的部队，不能按全王国军队比例瓜分。具名者先服从其实际抓获部队；未单独确定的按分配剩余槽位与人物稳定id放入，人数不变。无人可合法持有则捕获动作失败或按战局明确释放，不能写空holder后遗失。
- [x] 实现capture原子更新源队人数和批次；投降先核验对方接受，再把全部可战与伤兵转俘虏，不仅可战者；国王单独由KingSystem安全退离，绝不加入source_cohort。被拒投降保持原action。
- [x] 写600人守恒：430可战+70己方伤+40死+60俘=600；俘虏中20伤仍总计60。再加入100援军，总参战700；确保增援离开再返回不重复算同一人。按平民/贵族/具名逐项核对。
- [x] holder_defeated不先删除部队：现场控制者清点，属于获救方的俘虏释放为平民；其他俘虏转到明确接管部队。重放同一结算幂等，无场外押送路径。测试贵族指挥官被救不自动任职、先前不参战承诺不消失。
- [x] 国王同场、100军人含10贵族/20伤兵全体投降：捕获100、俘虏伤20、国王0、部队可战0，不因国王安全退离改成军队撤退成功；已驻营不绕过拔营变成全军脱离。
- [x] 补给按存活士兵/伤兵/俘虏和贵族权重计，死亡0粮；看守人数降低可战投入而不复制/消灭看守者，俘虏负重影响移动。捕获与转移后原持有者不继续扣这批粮。跑prisoner/conservation、battle_resolve、army_supply和fast，提交 `feat: account for surrender and unique prisoner custody`。

## P5.2 赎金、交换、释放与平民身份

**Create:** `scripts/engine/prisoner_disposition.gd`、`data/battle/prisoner_terms.csv`、`tests/engine/test_prisoner_disposition.gd`。

**Modify:** `scripts/engine/military_population.gd`、`scripts/engine/recruitment_system.gd`、`scripts/engine/action_system.gd`、`scripts/engine/law_system.gd`、`scripts/engine/data_repository.gd`、`data/tables.csv`、`data/realm/order_costs.csv`。

**Interfaces:**

```gdscript
# proposal含id/kind/batches/named_ids/money/parties/terms，明确整批或子人数。
static func propose(repo: DataRepository, state: GameState, proposal: Dictionary) -> Dictionary
static func settle(repo: DataRepository, state: GameState, proposal_id: String) -> Dictionary
```

- [x] fixture：持有60人，赎回10贵族成交价100金，法定俘获方份额300‰，王室收到70、俘获方分账30（具体身份映射现有财产账户），在押与源cohort的captured_current均变50、released增加10、原籍可征平民增加10、军队不变；历史战报仍记被俘60。份额只测试分账算法，生产比例取收到军法；不硬编码三分之一。
- [x] 测试提案未履行时零付款零释放；拒绝、买方余额不足、名单已转移/释放都不得部分扣款。交换双方各10人，必须同一次同步事务检查并同时释放，不能先把一边清空。运行test_prisoner_disposition见红。
- [x] propose冻结名单与条件但不立即收钱/放人；settle重验当前持有权、法律、资金、名单与承诺。全部有效后财政一次转账、PrisonerSystem更新、MilitaryRoster.transition把captured_current转released并解除动员占用、记录civilian disposition。重复proposal_id返回原结果。
- [x] 原籍不再属于原国家时，按实际原籍人口账归档与当前所有权展示；不能凭当前领主变化重复加人口。具名贵族保留Character/family但command assignment清除；受不参战承诺约束的civilian在RecruitmentSystem中拒绝，给出条款/到期原因。
- [x] 所有赎金/家族关系/放弃收益附reason，并记批次原主与俘获单位功劳；钱怎么分不改变held_by。操作菜单不含押送后方、上缴重要俘虏或点击即复员。
- [x] 跑disposition/population/recruitment/law_guard/save_load和fast；更新regiments与battle指南，提交 `feat: release ransomed and exchanged captives as civilians`。

## P5.3 战报、俘虏卡与随军表现

**Create:** `scripts/ui/prisoner_panel.gd`、编辑器创建 `scenes/panels/prisoner_panel.tscn`、`scenes/panels/battle_report_panel.tscn`；`tests/ui/test_prisoner_panel.gd`。

**Modify:** `scripts/engine/battle_report.gd`、`scripts/engine/missive_writer.gd`、`scripts/engine/missive_log.gd`、`scripts/engine/battle_presentation.gd`、`scripts/map3d/map3d_units.gd`、`tests/engine/test_battle_report.gd`。

- [ ] 写test_battle_report：战斗结束快照包含唯一battle_id、地点、天数、参与者/增援、阵型与主要命令/事件、损失、余部、俘虏、装备物资、家族关系及原因；释放后快照hash不变，处置记录独立增加。
- [ ] 本地立刻可查看，远程只在信使送达后显示许可精度；地图控制权等可见事实可立即更新，但不能顺带泄露精确损失。测试用同一战斗结果改变送达状态，仅允许的字段进入BattlePresentation。
- [ ] UI展示当前在押与历史被俘为两个明确口径；部队归属显示实际holder，点具名贵族进入原人物卡。赎金/交换显示提案、已接受、已履行，不拿发出提议当已到账。
- [ ] 实现接受投降后才收武器、看守小队随持有者移动；复用兵人模型与受控人数档位，不一比一显示俘虏数。无人头顶计数、不造押送独立单位；国王不进入投降/死亡动作。
- [ ] 在实际地图演示投降→随军→赎回→平民→重新征兵；截图俘虏卡/结束战报，核对600人例子及两次释放不重复。跑report/UI/map3d与fast，记录P5证据后提交 `feat: present prisoner custody and immutable battle reports`。

**阶段放行：** 战败、投降、赎回、交换、释放、俘获者覆灭均有守恒测试和真实界面演示；国王例外明确；无人员丢失或自动归队。
