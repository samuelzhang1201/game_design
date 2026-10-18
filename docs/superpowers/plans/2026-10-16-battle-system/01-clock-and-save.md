# P1 日结算、暂停与存档 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 遭遇或事件可在任意一天安全暂停、保存和继续，日结算及月结算各执行一次。

**Architecture:** 把日游标、待处理决策及已产生输出存入 GameState。TickEngine 统一普通日与月末入口；GameRoot 只驱动唯一世界时钟。

**Tech Stack:** Godot 4.7、typed GDScript、GUT、JSON。

**Spec:** [基础设计](../../specs/2026-10-16-battle-system-design.md)；[已批准的行为/战场设计 §5、§7–8、§12–14](../../specs/2026-10-17-unit-behavior-and-battlefield-design.md)；[总计划与测试命令](../2026-10-16-battle-system-implementation.md)。前置：实施基线检查完成。

## Global Constraints

- 一天 8 秒，1/2/4 倍速对应 8/4/2 秒；30 天一月；不自动慢速。
- 首次遭遇自动暂停一次，未确认前零伤亡；普通援军不重复首次暂停。
- 暂停不积攒补跑时间；选择后保持暂停，由玩家恢复。
- 无疲劳、紧急弃营或失联人员；引擎纯逻辑、确定性、单 JSON，所有数字状态为整数。
- 使用总计划的测试、隔离工作区、编辑器外观和 PR 流程。
- 固定整数子步属于同一世界日事务，不建第二战斗时钟；子步数作为数据配置，任何暂停/存档恢复只续未完成子步。
- 每个子步依次行军、重算地面/法律并推进敌军到达，然后检测/合并接触；首次遭遇在本子步的战斗轮前暂停确认。确认后，本子步内按稳定 battle ID 顺序推进所有尚未交战的战场一次，再递增子步游标。伤亡前必须确认，任何战场每天最多一轮；之后子步到达的援军可加入存续战场，下一日再战。

## Review Focus

1. 第 30 天接触：P1.1 `test_month_end_blocks_before_settlement`，月薪只付一次。
2. 多战场后一个阻塞：P1.1 `test_second_battle_does_not_replay_first`，先前结果不重算。
3. 暂停读档：P1.1 `test_blocked_roundtrip_preserves_journal`，新引擎实例继续结果一致。
4. 一帧积攒 40 秒：P1.2 `test_encounter_stops_catchup`，不追跑剩余四天。
5. 关闭别的窗口解除战斗锁：P1.2 `test_decision_lock_survives_other_windows`。

---

## P1.1 可恢复的完整日事务

**Files — Modify:** `scripts/engine/game_state.gd`、`scripts/engine/tick_engine.gd`、`scripts/engine/battle_system.gd`、`scripts/engine/save_load.gd`；`tests/engine/test_battle_save.gd`、`tests/engine/test_tick_engine.gd`。

**Files — Create:** `scripts/engine/day_resolution.gd`、`tests/engine/test_day_resolution.gd`、`tests/fixtures/battle_scenario.gd`。

**Interfaces:**

```gdscript
# DayResolution，pure RefCounted；phase 常量属于流程协议，不是调校数值。
static func begin(day: int, month_end: bool) -> Dictionary
static func acknowledge(tx: Dictionary, token: String, choice: String) -> Dictionary
# TickEngine：唯一日推进入口；结果 status = blocked | complete。
func resolve_day(state: GameState) -> Dictionary
# BattleSystem：先发现所有遭遇，再逐战场推进。
static func prepare_day(repo: DataRepository, state: GameState) -> Array
static func step_battle(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary
static func finish_day(repo: DataRepository, state: GameState) -> void
# 测试夹具 BattleScenario：SuiteData 基础上放置真实单位，固定参与者与顺序。
static func contact(repo: DataRepository, day: int) -> GameState
static func two_battles(repo: DataRepository, day: int) -> GameState
static func roundtrip(state: GameState) -> GameState
```

事务字段固定为 `day, month_end, phase, substep_index, phase_cursor, battle_ids, battle_index, battle_step, pending_decision, consumed_tokens, journal`；journal 包含 works/arrivals/couriers/battles/sieges/raids/supply/conduct/reports。决策含 `token, kind, battle_id, substep_index, choices, selected`；token 用已保存的日/子步/战斗/序号构造，不取墙钟。子步表顺序和配置版本写入事务，读档后不得按新配置重跑已结算子步。

- [x] 在 `test_day_resolution.gd` 写纯状态测试；这是 begin/acknowledge 的最低可执行契约：

```gdscript
func test_acknowledge_is_idempotent() -> void:
    var tx: Dictionary = DayResolution.begin(10, false)
    tx["pending_decision"] = {"token": "10:b1:0", "kind": "encounter",
        "battle_id": 1, "choices": ["continue"], "selected": ""}
    assert_eq(DayResolution.acknowledge(tx, "10:b1:0", "continue")["status"], "accepted")
    assert_eq(DayResolution.acknowledge(tx, "10:b1:0", "continue")["status"], "duplicate")
    assert_eq(DayResolution.acknowledge(tx, "wrong", "continue")["status"], "stale")
```

- [x] 按总计划命令运行该文件，确认因新接口缺失而失败；不要把脚本解析失败当已执行测试。
- [x] 实现 begin 的完整默认结构；acknowledge 先检查 consumed_tokens，再检查 token/choices，合法才记录 choice 与消费 token。它不计时、不发信、不扣费。费用在对应 handler 的同一同步调用内核验并一次性执行；失败不消费 token。
- [x] 把 `_end_day` 拆成有名字的阶段处理函数，按下面顺序运行；阶段效果与游标前移在一个无 await 的调用内完成，返回 UI 前完整写回状态。

```text
WORKS → MARCH_ORDERS_AND_ROUTE_SETUP → COURIERS → AI_AND_SCOUT → SIGHTING_AND_INTEL_REFRESH
→ FIXED_TACTICAL_SUBSTEPS（每个子步：移动→重算→敌军到达→接触/确认→尚未交战战场的一轮；完成全部子步）
→ SIEGES → RAIDS → CAMPS_AND_SIGHTING → SUPPLY_AND_CONDUCT
→ DAILY_ECONOMY → REPORTS → MONTH_END_IF_NEEDED → CALENDAR → COMPLETE
```

- [x] 把 `advance()` 月结算正文抽成不再调用 `_end_day` 的内部方法。保留 tick==0 的开局初始化特例及既有 advance 的“一次日处理加月结算”兼容语义，不偷改成补跑余下整月。生产普通日和第30天只从 resolve_day 进入；已有事务的 month_end 不受中途切换入口影响。迁移所有调用点，兼容方法不得绕过 pending_decision。
- [x] 检查 `tests/invasion_play.gd`、`tools/sim_invasion.gd`、`tools/chapter0_numbers.gd` 等逐日调用者。测试或批量模拟只有显式选择自动确认首遇的策略才可续跑；默认应返回 blocked，不允许生产代码偷偷确认，也不能在阻塞日无限循环。批量工具输出阻塞原因与决策 token。
- [x] 把现有移动及战斗推进重构为统一固定整数子步；在单一顺序中执行行军/战术位移、真实接触检测、战斗组推进与结算。显式移除被替代的日末重复移动/整日伤亡调用；同一单位/人员组每一子步至多推进一次。战力系数沿用P4，不在P1调平衡。
- [x] 每个子步的真实接触在本子步伤亡结算前建立可保存遭遇决策；确认前不执行组级攻击/伤亡。多个新遭遇逐一确认后，本子步按稳定 ID 推进尚未交战的战场；阻塞时保存子步、battle_index和输出，不重放已完成战斗或子步。
- [x] 加入固定子步接触/恢复时序：真实单位在同一子步接触并阻塞；保存的子步游标停在接触处且伤亡为0，JSON 往返确认后该战斗的 round 事件带相同子步索引，位置/hash 与不中断续跑一致。旧的“全部移动后日末接触”手算不再适用。
- [x] 验证后续子步援军：首个子步先交战，援军在后续子步加入同一仍存续战场；当日不重开第二轮，次日 round 事件的参战名单包含该援军。
- [x] 跑步补给留P4实现，本阶段只固定同一子步事务接口和供给journal顺序；不得先在日末按跑步扣一次、再在子步重复扣。月末薪资和经营仍仅在所有战术子步完成后结算一次。
- [x] 实现夹具：`SuiteData.repo()/campaign`，从绑定的玩家/入侵国选择真实陆军，按 code 排序，用现有 `tests/invasion_play.gd` 放置方式安排接触；不写死国家或地图名。roundtrip 使用 JSON stringify/parse 和 `GameState.from_dict`，不是 Dictionary 深拷贝。
- [x] 加入以下集成用例并运行 `test_day_resolution.gd`、`test_battle_save.gd`、`test_tick_engine.gd`：

| 用例 | 设置 | 必须得到 |
|---|---|---|
| `test_encounter_before_losses` | 第 10 天；工作量日增 1000；第三固定子步接触 | 阻塞时工作=1000、日期=10、接触双方位置为第三步位置、伤亡=0；重复推进不变；确认后不重复位移，且先推进该步战术/伤亡阶段再进入下一步 |
| `test_second_battle_does_not_replay_first` | A/B 各100可战；日损100‰，伤占500‰；B选择费7金 | B暂停时A=90可战/5伤/5死/1轮；B未损；100金→93仅一次；继续后A不重算 |
| `test_blocked_roundtrip_preserves_journal` | 上两种暂停点各做 JSON 往返并新建 TickEngine | 相同选择后的 `SaveLoad.state_hash`、随机流、费用、战报数一致 |
| `test_month_end_blocks_before_settlement` | 第30天、100金、仅月薪7金 | 阻塞时原tick/30日/100金；继续后tick+1/1日/93金，仅一条薪资原因 |
| `test_opening_does_not_consume_first_day` | tick==0初始化 | 不多做一天行军、工作或扣粮 |

P1 的第二战场事件用测试侧可控处理器验证事务续跑，不提前引入正式战场事件。P4.3 必须用真实事件和财政处理器重新执行该用例，才能签收“7金只付一次”；P1 通过不能代替 P4 的验收。子步手算只验证游标与移动的原子性；跑步及战斗公式由P4的独立手算测试验收。

### 批准的 P1.1 战役验收修订（2026-10-17）

用户选择接触与战斗均在固定移动子步内立即处理。首次遭遇仍在任何伤亡前阻塞确认；确认后该子步推进尚未交战战场的一轮，之后才进入下一子步。保留有意义的弱/强防守差异、伤亡守恒、每日每场最多一轮、子步援军下日参战、捕城时 HOLD 及之后既有撤退行为；旧的强守不陷城和特定伤亡上限不再作为门槛，因为它们依赖旧接触名单。不得调平衡系数或把观察到的日期/伤亡数写成目标值。

- [x] 更新 `scripts/engine/guide/battle_and_ai.md` 日入口规则并运行 fast；P1.1 提交单独记录于 HANDOVER。

## P1.2 时钟桥接与遭遇窗口

**Files — Modify:** `scripts/ui/game.gd`、`scripts/ui/game_root.gd`、`tests/ui/test_game_root.gd`、`scripts/ui/CLAUDE.md`（或实施时实际 AGENTS guide）。

**Files — Create:** `scripts/ui/battle_encounter_panel.gd`、编辑器创建 `scenes/panels/battle_encounter_panel.tscn`。

**Interfaces:** `Game.advance_day() -> Dictionary` 增加 status/decision/journal；`Game.resolve_battle_decision(token: String, choice: String) -> Dictionary`；面板 `decision_selected(token: String, choice: String)` signal。面板只发请求，不改引擎字典。

- [ ] 在现有 GameRoot 测试加入下列时序断言；使用仓库已有 screen/Game 测试设置，注入 P1.1 的 contact 夹具：

```text
_process(40.0) → 第一个8秒边界blocked → 只有1个day_resolution，零伤亡
提交continue → 保持clock_speed=0，清掉积存时间
玩家按继续 → 先完成旧事务；不再扣8秒
再经过7.9秒 → 下一天未结算；再0.1秒 → 完成下一天
参数化speed=1/2/4 → 新日分别消耗8/4/2秒
```

- [ ] 运行 `tests/ui/test_game_root.gd` 确认新断言失败。
- [ ] 修改 `_process`：新日才扣时间；blocked 立即 break 并清 accumulator；日事务未完成时不让 `day_progress` 再预演行军。恢复先续跑已有事务，再开始新日计时。Game 只有 status==complete 才发布完成日输出。
- [ ] 用独立命名锁 `battle_decision` 控制暂停，加载 pending_decision 自动恢复该锁；选项成功才解除这把锁，仍保持手动暂停。关闭地图窗口或其他事件窗口不能解除它。保存玩家原选倍速，手动恢复使用该倍速。
- [ ] 编辑器制作遭遇面板：只显示已知敌情、己方单位、进入部署按钮及继续按钮；现有信息左栏，人物右栏，中央事件窗口。不增加精确敌军计数或自动计时关闭。
- [ ] 测试 `test_decision_lock_survives_other_windows`、多场首遇逐一确认、普通增援不重复暂停、读档重现同一窗口；跑 UI 目录和 fast。
- [ ] 真实窗口录制暂停前后 1x/4x，各检查遭遇前零伤亡和恢复不补跑。沿用现有兵人，不在此阶段制作新战斗动作。保存 P1 证据后提交 `feat: pause encounters at the daily boundary`。

**阶段放行：** 普通日/月末/多战场/读档及接触子步均通过；不存在被调用的重复日末移动/伤亡入口；子步配置固定且事务可恢复，没有改变世界时速。P4 的战术、跑步及事件处理器复用本阶段token、游标与事务，不另建时钟或暂停系统。
