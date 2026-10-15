# P4 阵型、逐条协议、命令与事件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成一场可操作、逐日结算、有法律约束和战场选择的野战。

**Architecture:** BattleRules 给出合法行动集合；BattleOrders 负责费用与送达执行；BattleEvents 在 P1 事务内阻塞或自动处理。BattleSystem 保持战斗生命周期与结算，BattlePresentation 过滤展示信息。

**Tech Stack:** Godot 4.7、GUT、CSV、作者事件正文、Qwen插图、Blender动作。

**Spec:** [设计 §7–10、§15–17](../../specs/2026-10-16-battle-system-design.md)；[总计划](../2026-10-16-battle-system-implementation.md)。前置：P1–P3。

## Global Constraints

- 四阵型：横向长战线、锥形、保护真实中心的菱形、紧凑双排；阵型与行动分开。
- 战前交涉自动按已收军法逐条达成；国王在场也不能临时对话改口；有效条款必须遵守。
- 全军进攻/坚持驻守/撤退/投降互斥；鼓舞为一次性辅助，有费用、冷却与限制。
- 国王在场主要事件由玩家选，离场指挥官依法自动处理、之后报告；无自动慢速。
- 野战通常3–5天但可更短更长；无五轮平局、疲劳、无条件撤退免疫。
- 事件正文由作者写，LLM不决定结果或运行时编造事件；遵守总计划所有流程。

## Review Focus

1. 一条不合就废除全部协议：P4.1 `test_clause_agreements_are_independent`。
2. 改法律/换主将/援军重置承诺：P4.1 `test_agreement_snapshot_survives_changes`。
3. 重送军令或过期信使重复收费：P4.2 `test_orders_reserve_and_execute_once`。
4. 远程事件使用玩家看见的全知敌情：P4.3 `test_commander_uses_only_known_state`。
5. 无合法选项、资金变化或读档导致卡死：P4.3 `test_event_revalidates_choices_and_has_legal_fallback`。

---

## P4.1 阵型和逐条交涉

**Create:** `scripts/engine/battle_rules.gd`、`scripts/engine/battle_formation.gd`、`data/battle/formations.csv`、`data/battle/parley_clauses.csv`、`tests/engine/test_battle_rules.gd`、`tests/engine/test_battle_formation.gd`。

**Modify:** `scripts/engine/battle_system.gd`、`scripts/engine/law_system.gd`、`scripts/engine/data_repository.gd`、`data/tables.csv`、`scripts/ui/laws_screen.gd`、`scripts/ui/law_row.gd`、`scripts/ui/war_formation_dots.gd`；编辑器更新laws与battle encounter面板。保留 `data/army/army_formations.csv` 的兵人数档位职责，不混成战术阵型数值表。

**Interfaces:**

```gdscript
# 输入是逐条规范化的收到版本；返回 agreed/rejected 及各自原因。
static func negotiate(ours: Dictionary, theirs: Dictionary) -> Dictionary
static func legal_actions(repo: DataRepository, state: GameState, battle_id: int, side: String) -> Array[String]
# BattleFormation，职责是地形/兵种适用性与换阵状态。
static func request(repo: DataRepository, state: GameState, battle_id: int, side: String, formation: String) -> Dictionary
```

- [ ] 写纯协议测试并运行见红：

```gdscript
func test_clause_agreements_are_independent() -> void:
    var ours := {"herald_safety": "protect", "noble_ransom": "allow", "surrender": "accept"}
    var theirs := {"herald_safety": "protect", "noble_ransom": "deny", "surrender": "accept"}
    var result := BattleRules.negotiate(ours, theirs)
    assert_eq(result["agreed"], {"herald_safety": "protect", "surrender": "accept"})
    assert_true(result["rejected"].has("noble_ransom"))
```

- [ ] 把传令官安全、贵族待遇/赎金、普通士兵待遇、投降接纳、伤者与约定撤离、允许战术各自建条款ID。简单一致项直接达成；带时间/条件/范围的条款按 schema 比较完整条件，不只比较显示文字。拒绝项保留双方提议及理由，不覆盖已同意项。
- [ ] 在对峙创建时冻结双方实际收到的军法版本/条款；谈判输出绑定 battle_id。新法以后送达不能覆盖协议，援军加入前继承该战场约束，新主将也继承；已获准撤离/停火优先于普通追击授权。
- [ ] 红旗只表示拒绝新的投降，不等于自己永不投降，不撤销已接受俘虏权益。根据军法与有效协议禁用不合法红旗/战术；角色性格和事件均只能在 legal_actions 中选择。测试国王在场无人工重谈入口。
- [ ] 四阵型写入formations表：适用正面宽度、兵种要求、中心目标要求、攻防/侧翼修正、换阵消耗与失序时长。数值使用现有战斗尺度，所有修正带唯一来源；菱形无需要保护的中心时明确显示收益不足，不能凭空保护不存在目标。
- [ ] 换阵请求本地直接/远程信使送达才开始；保存 previous/target/progress/disorder_until。换阵暴露期不同时享用新旧全部收益。测试窄地横线收缩、受夹击时菱形、正面守御双排、锥形侧翼代价、重复换阵不能清失序。
- [ ] LAW页按条款显示政策；对峙面板只读展示“达成/未达成/原因/收到版本”，WAR ROOM显示真实阵线。运行rules/formation/law_guard/law_couriers/UI测试与fast；提交 `feat: enforce formations and per-clause battle agreements`。

## P4.2 命令成本与逐日战斗

**Create:** `scripts/engine/battle_orders.gd`、`scripts/engine/battle_strength.gd`、`data/battle/orders.csv`、`tests/engine/test_battle_orders.gd`、`tests/engine/test_battle_strength.gd`、`tests/engine/test_battle_duration.gd`。

**Modify:** `scripts/engine/battle_system.gd`、`scripts/engine/action_system.gd`、`scripts/engine/courier_system.gd`、`scripts/engine/enemy_ai.gd`、`data/battle/battle_outcomes.csv`、`data/realm/order_costs.csv`、`data/tables.csv`、`scripts/engine/data_repository.gd`、`tests/engine/test_battle_lifecycle.gd`、`tests/engine/test_battle_resolve.gd`。

**Interfaces:**

```gdscript
# order含id/battle_id/side/kind/issued_day/params，队伍必须仍在战场。
static func issue(repo: DataRepository, state: GameState, order: Dictionary) -> Dictionary
static func deliver(repo: DataRepository, state: GameState, order_id: String) -> Dictionary
static func invalidate(repo: DataRepository, state: GameState, order_id: String, reason: String) -> Dictionary
# 输入项为整数等效战力/千分比，每个factor带唯一source和reason。
static func combine(base: int, factors: Array[Dictionary]) -> Dictionary
```

- [ ] 写系数手算：base630，训练800‰、士气900‰、军纪1000‰，结果453（逐层整数舍去规则固定）；传入重复source必须报错而不是乘两次；factor说明随结果返回。运行test_battle_strength见红。
- [ ] 实现 combine 的确定顺序：身份装备基础 → 训练 → 士气 → 军纪 → 补给 → 阵型/地形 → 当前行动；同类修正先合成一次，顺序固定，CSV上下限夹紧。保留原可复用 odds/split_losses/apportion 并补齐每一新公式的手算测试，不能把贵族装备、纪律加成和旧army_quality再重复计算。
- [ ] 战斗日按近战/远程/冲击/撤离/追击情境计算真实损失，原子更新人员账、士气与本轮号。初步复用现有outcomes表，移除五轮强制结束；用规则推导撤离/溃败/失能终止。战斗随机由唯一保存的引擎种子流取值并在该轮记录，移除会旁路该流的旧战斗随机入口；阻塞重试不重抽，存读档完全一致。
- [ ] 实现命令表中的具体效果和成本：

| 命令 | 执行效果 | 必付成本/限制 | 失败与终止 |
|---|---|---|---|
| 全军进攻 | 投入可用预备、提高攻击压力 | 每实际进攻日额外粮/器材、暴露防御；不凭空产生预备 | 无可用补给/人力按合法回退，报告原因 |
| 坚持驻守 | 防御稳定、保持阵位 | 放弃主动推进与相应机会；正常维持补给 | 被包抄或失能不产生无限防守免疫 |
| 鼓舞士气 | 一次士气增益，在场国王增强 | 赏金派发时保留，执行时支付；冷却，不叠加同类效果 | 战斗结束/已失去目标退未花赏金；信使已花费用不退 |
| 撤退 | 后卫掩护、走真实退出路 | 让出阵地、士气/装备损失、可能被追击；营地gate仍生效 | 约定安全撤离阻止违规追击；无路不能瞬移 |
| 投降 | 请求接纳，接受后全体存活军人含伤兵/贵族交P5俘获 | 失去部队控制和装备 | 拒绝则维持原行动；国王不入俘虏 |

- [ ] 对峙阶段照常供给、收信、接纳援军；只有主将依据合法预案/局势决定交锋或收到合法进攻令才进入伤亡阶段。测试双方保持距离时连续3日轮数不增但粮减少；随后进攻只开始同一battle_id的交战，不重新弹首次遭遇。对峙不能因用户按“继续时间”就被强制解释成全军进攻。

- [ ] 写命令fixture：总金100，信使费2，鼓舞赏金7。派发总金98、保留7、可支配91；执行总金91、保留0；取消则总金98、保留0。重复送达/读档重送/战斗结束后的旧信均不重扣、不重鼓舞、不复活战斗。所有财政操作附可读原因。
- [ ] 相互覆盖用最后实际送达合法行动，而不是最后点击；鼓舞不清除attack/hold；同一order_id幂等；会违反已达成协议的命令发送前及送达时都校验。用king现场/远程相同动作对比仅延迟不同。
- [ ] `test_battle_duration.gd` 建立固定种子基准组（均势、较大军队、充足补给、第三天增援、压倒性优势），明确首遇/结束日。普通基准校准3–5日；至少一个补给/增援案例持续超过5日且battle_id不变；一个优势案例更快。不要用硬上限“修到测试通过”。模拟记录原始日数、伤亡、粮与理由，改表后同时重算手算测试。
- [ ] 跑orders/strength/duration及旧battle生命周期/存档/撤退用例和fast，更新battle指南后提交 `feat: resolve costly battle orders over game days`。

## P4.3 事件、合法自动决策与展示数据

**Create:** `scripts/engine/battle_events.gd`、`scripts/engine/battle_presentation.gd`、`data/battle/events.csv`、`data/battle/event_choices.csv`、`tests/engine/test_battle_events.gd`、`tests/engine/test_battle_presentation.gd`、`scripts/ui/battle_panel.gd`；编辑器创建 `scenes/panels/battle_panel.tscn`。

**Modify:** `RANDOM_EVENTS.md`、`scripts/engine/story_source.gd`、`scripts/engine/data_repository.gd`、`data/tables.csv`、`scripts/ui/game.gd`、`scripts/engine/tick_engine.gd`、`scripts/engine/missive_writer.gd`、`scripts/engine/game_art.gd`。

**Interfaces:**

```gdscript
static func offer(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary
static func choose(repo: DataRepository, state: GameState, token: String, choice: String) -> Dictionary
static func commander_choice(repo: DataRepository, state: GameState, event: Dictionary) -> String
# 不传真实隐藏部队给视图，只返回本国已知信息。
static func snapshot(repo: DataRepository, state: GameState, realm: String) -> Dictionary
```

- [ ] 为六个事件写完整触发、选择、增益/代价、冷却和一次性消费测试：侧翼动摇、贵族请求冲锋、援军投入或保留、伤员撤路、夺得补给、地道塌陷征兆（围城触发在P6接入）。fixture中鼓舞选择+8士气/−7金，拒绝保留资源；已消费token重送零变化。
- [ ] 运行battle_events见红，随后实现 offer 先读真实触发，再按种子流选事件，保存选中ID与合法choices；不能在窗口每次刷新重抽。1–2次大事件是普通战斗节奏目标，不是强制配额，短战斗允许没有。
- [ ] 作者在 `RANDOM_EVENTS.md` 写唯一 `### EV-NN` 与 `**Scene:**`，实际分配未占用ID；文字只用realm占位符。独立battle表引用这些ID，不能让月事件池再次抽同一battle-only项。扩展StorySource读取所需原文，不走Voicer API生成事件。
- [ ] 本地主要事件通过P1决策阻塞；选择时重新核验资金/协议/目标，失效选项显示理由并保持同一事件。每个事件提供真实合法的保守选项：坚守现令/依法报告/停止危险工程，按情境选择且有真实后果，不能用违反协议的万能回退。
- [ ] 指挥官从同一legal choices按能力/性格/已知局势评分，稳定ID打破同分；保存选择、可读理由、效果与报告，不阻塞世界时钟。法禁冲锋即使boldness最高仍不能选；国王后来抵达不回滚已经自动处理的事件。
- [ ] snapshot返回己方许可数据、敌方估计、已收到的事件/战报；隐藏敌军变化且情报不变时投影必须相同。所有UI按钮与图示都基于该投影，不能先把隐藏真实数字传给地图再用透明度遮住。
- [ ] 制作六类事件插图到 `assets/2D/events/battle/`，Qwen手绘，动作和人数符合prompt规范；每图经ArtTable资源映射。战斗卡显示命令效果、费用、送达状态、冷却和法律禁用原因；红旗和传令官资产在地图真实展示，接战最少具备驻防/走位/攻击/格挡。
- [ ] 验证国王到/离场、事件选择前存档、余额变化、零合法进攻、报告延迟、多战场同时触发；跑battle_events/presentation、event_content、UI、fast并完成真实窗口审查，提交 `feat: add authored battle events and informed command views`。

**阶段放行：** 能部署、自动逐条交涉、发五类命令、收到六类事件的对应结果；正常野战基准达目标，长战斗不中断编号；费用/军法/自动决策/暂停均有可复现证据。投降和俘虏最终闭环以P5放行为准。
