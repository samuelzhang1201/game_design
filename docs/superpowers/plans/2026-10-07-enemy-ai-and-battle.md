# 敌军 AI 与两军战斗 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 第 15 天前后,多支敌军越境,玩家能用战前姿态、信使命令和增援应对;敌军有简易 AI,围城/劫掠/战败后果齐备(spec 的 P1–P3)。

**Architecture:** 三个 `RefCounted` 引擎类 `BattleSystem` / `EnemyAi` / `SiegeSystem`,挂在 `TickEngine._end_day`;敌军的兵力状态放在**独立的** `GameState.foes`(与 `regiments` 同形状),由 `ArmySystem.state_of` 与 `march_day` 接纳,这样三十多处遍历 `state.regiments` 的玩家专用代码(补给线、LEDGER、危险区、地图)全部不受影响。所有数值进 CSV / `balance.csv`;战斗抽签用哈希,不碰 `GameState.rng`。

**Tech Stack:** Godot 4.7、GDScript(全类型标注)、GUT、CSV 数据表。

**Spec:** `docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md`(本计划在 Task 1 把其中"敌军进 `GameState.regiments`"改为"进 `GameState.foes`")。P4(战斗标记、幽灵棋子、战报 UI)不在本计划内,须本地会话 + `visual-review`。

## Global Constraints

- 引擎类 `RefCounted`,不引用 `scripts/ui/`、`scripts/llm/`,不碰 `Game`(`tests/engine/test_engine_isolation.gd`)。
- 无 `Time.get_*`、无未播种的 `randi()`;战斗抽签 = `hash([seed, attacker_codes, defender_codes, absolute_day, round]) % 1000`,不读不写 `GameState.rng`。
- 存档状态只含整数、字符串、数组、字典,不含浮点;敌军位置是整米(`x_m` / `y_m`)。
- 每个状态变化带原因串(`MapOwnership.set_owner`、`MapManors.set_owner`、opinion、国库账目)。
- 设计数值只在 CSV / `balance.csv`,脚本里不写常数;故事文字用 `{player_realm}` / `{raider_realm}`,不点名王国,也不点名地图包。
- 测试数据取自 `tests/suite_data.gd`(`SuiteData.repo()`、`SuiteData.campaign(repo, seed)`),不用 `DataRepository.load_all`;等待用 `wait_process_frames` / `wait_until`。
- 单个测试文件:`CC_FORCE_OFFLINE=1 $GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/engine -gselect=<文件名不带.gd> -gpre_run_script=res://tests/pre_run.gd -gexit`(下文简写 `RUN <名>`)。迭代用 `./run_tests.sh --fast`,提交触及非文档时跑完整 `./run_tests.sh`(预期错误数 0)。
- `scripts/engine/CLAUDE.md` 与根 `CLAUDE.md` 有字数上限测试(`test_claude_md_size.gd`):规则写进新的 `scripts/engine/guide/battle_and_ai.md`,`CLAUDE.md` 只加一行索引。
- 云端会话无编辑器、无窗口:不改 `.tscn` / `.tres`,不声称任何视觉改动已审。

## Review Focus

- 敌军 regiment 被其它只认玩家兵的系统误读(补给线、LEDGER、危险区的伤兵扣除、`Intel`):敌军只在 `foes`,任何 `state.regiments` 遍历都不得看见它(Task 1 测试)。
- 老存档(无 `foes` / `ai_hosts` / `battles` 键)读入后不崩、行为同改动前(Task 2 测试)。
- 一场战斗中某参战 regiment 被信使命令撤走、或头数为 0:不得除零、不得留下空战斗(Task 4 测试)。
- 两支敌 host 同帧选同一目标 / 无任何候选目标:不得重复围同一城,也不得卡死在 ADVANCE(Task 7 测试)。
- 围城中守军 regiment 被调走 / 城镇已易主:`siege_progress` 不得继续累加,不得二次换主(Task 9 测试)。
- 玩家夺回城后敌军 HOLD 的 host 的去向(应转 RETREAT,不是永远 HOLD)(Task 9 测试)。

## File Structure

| 文件 | 职责 |
|---|---|
| `data/battle_outcomes.csv`、`data/battle_stances.csv`、`data/ai_doctrines.csv` | 战斗五档、姿态、AI 作风 |
| `data/maps/<id>/military/raid_hosts.csv` | 每个 pack 的敌军编成(由 `DataRepository.default_pack_id()` 定位,代码不点名 pack) |
| `data/balance.csv`(追加键) | `battle_*`、`ai_*`、`siege_*`、`raid_*` |
| `scripts/engine/data_repository.gd`(改) | 加载新表:`battle_outcomes`、`battle_stances`、`ai_doctrines`、`raid_hosts` |
| `scripts/engine/game_state.gd`(改) | 新字段 `foes`、`ai_hosts`、`battles`、`foe_next_id`,存读 |
| `scripts/engine/army_system.gd`(改) | `state_of` 接纳 `foes`;`march_day` 第二遍走 `foes`;删掉 `battle_odds` 的"占位"注释 |
| `scripts/engine/battle_system.gd`(新) | 纯函数结算 + `settle_day` 生命周期 |
| `scripts/engine/enemy_ai.gd`(新) | 出兵、打分、状态机、预警 |
| `scripts/engine/siege_system.gd`(新) | 围城进度、强攻、断粮、城破、夺回 |
| `scripts/engine/raid_system.gd`(新) | 劫掠、危险区、战利品 |
| `scripts/engine/defeat_system.gd`(新) | 战败后果 |
| `scripts/engine/tick_engine.gd`(改) | `_end_day` 挂接 |
| `scripts/engine/action_system.gd`(改) | `ARMY_STANCE` 命令 |
| `scripts/engine/guide/battle_and_ai.md`(新) | 规则指南 |
| `tests/engine/test_battle_*.gd`、`test_enemy_ai_*.gd`、`test_siege.gd`、`test_raid.gd`、`test_defeat.gd` | 对应测试 |

---

## Part 1 — 战斗核心(spec P1)

### Task 1: 数据表、加载与敌军状态容器

**Files:**
- Create: `data/battle_outcomes.csv`, `data/battle_stances.csv`, `data/ai_doctrines.csv`, `data/maps/<default pack>/military/raid_hosts.csv`
- Modify: `data/balance.csv`, `scripts/engine/data_repository.gd`, `scripts/engine/game_state.gd`, `scripts/engine/army_system.gd`, `docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md`(§2 把"进 `GameState.regiments`"改为"进 `GameState.foes`,同形状,理由见本计划 Architecture")
- Test: `tests/engine/test_battle_data.gd`

**Interfaces:**
- Produces: `DataRepository.battle_outcomes: Array[Dictionary]`(按 `eff_min` 升序,键 `tier, eff_min, eff_max, attacker_loss_permille, defender_loss_permille, wounded_share_permille, attacker_morale, defender_morale, rout`)、`battle_stances: Dictionary`(stance → `{label, defence_permille, morale_decay_permille, retreat_odds_permille, retreats_on_contact}`)、`ai_doctrines: Dictionary`(role → `{greed_permille, caution_permille, dist_cost, engage_odds_permille, retreat_morale, town_bonus}`)、`raid_hosts: Array[Dictionary]`(`host_code, regiments(Array), appear_day, role, start_x, start_y`)。
- Produces: `GameState.foes: Dictionary`、`GameState.ai_hosts: Dictionary`、`GameState.battles: Array`、`GameState.foe_next_id: int`。
- Produces: `ArmySystem.state_of` 对 `state.foes` 中的 code 返回其存储项;`ArmySystem.is_foe(state, code) -> bool`。

- [ ] **Step 1: 写失败的测试** `tests/engine/test_battle_data.gd`:`test_outcomes_tile_the_whole_range`(五档,首档 `eff_min` 0、末档 `eff_max` 1000、相邻档首尾相接无缝无叠)、`test_every_stance_row_complete`(三姿态 `hold`/`steady`/`evade` 都在)、`test_doctrines_cover_every_host_role`(`raid_hosts` 里出现的每个 `role` 在 `ai_doctrines` 有行)、`test_balance_keys_present`(逐个 `repo.bal(...)` 列出 spec §7 的全部新键)、`test_raid_hosts_name_real_regiments`(每个 host 的 regiments 在 `repo.regiment(code)` 非空,且属于 `repo.resolve_realm("raider_realm")`)、`test_state_of_reads_foes`(往 `state.foes` 放一个条目,`ArmySystem.state_of` 返回它;不在 `foes` 且非玩家兵仍返回 `{}`)、`test_foes_never_in_player_iteration`(放入 foe 后 `state.regiments.has(code)` 为 false)。
- [ ] **Step 2: `RUN test_battle_data`**,预期 FAIL(表与字段不存在)。
- [ ] **Step 3: 写 CSV 与加载。** 表头与 spec §4.3、§4.4、§3.3 一致;`battle_outcomes.csv` 五档 `eff` 区间 0–200–400–600–800–1000(Default),损失/士气数值取草稿值并在 `notes` 列写明"first draft"。`raid_hosts.csv` 的 regiments 列用 `|` 连接,3 个 host(main / raider / reserve),`appear_day` 为 15 / 15 / 18,regiment 选自 `{raider_realm}` 在 pack `military/regiments.csv` 中的真实 code。`balance.csv` 追加 spec §7 列出的全部键与 Default 值。`data_repository.gd` 照 `army_hostile_stances` 的 `_load_if_present` 模式加载;`raid_hosts` 从 `dir + "/maps/<pack>/military/raid_hosts.csv"` 读(沿用其它 pack 表的读取方式,不硬编码 pack id)。
- [ ] **Step 4: `GameState` 加四个字段并存读**:`foes` 走 `_encode_values` / `_decode_values`,键缺失时 `{}` / `[]` / `0`;`ArmySystem.state_of` 先查 `state.foes`;新增 `is_foe`。
- [ ] **Step 5: `RUN test_battle_data`**,预期 PASS;`./run_tests.sh --fast` 全绿。
- [ ] **Step 6: Commit** `git add data scripts/engine tests/engine/test_battle_data.gd docs/superpowers/specs && git commit -m "feat: battle and AI data tables, foe state container"`

### Task 2: 存档往返与旧档兼容

**Files:**
- Test: `tests/engine/test_battle_save.gd`
- Modify: `scripts/engine/game_state.gd`(若 Task 1 的存读有遗漏)

**Interfaces:**
- Consumes: Task 1 的四个 `GameState` 字段。

- [ ] **Step 1: 写测试**:`test_foes_ai_hosts_battles_round_trip`(`SuiteData.campaign` 得到的 state,写入一个 foe 条目、一条 `ai_hosts`、一场 `battles`,`to_dict` → `from_dict` 后三者逐项相等,且无浮点:遍历值断言 `typeof != TYPE_FLOAT`);`test_old_save_without_keys_loads`(从 `to_dict` 结果删掉三个键再 `from_dict`,字段为空,不报错);`test_save_is_stable`(两次序列化字符串相同)。
- [ ] **Step 2: `RUN test_battle_save`**,预期:若 Task 1 已正确实现则 PASS,否则 FAIL 并据此补齐。
- [ ] **Step 3: 补齐 `game_state.gd` 缺口(如有)。**
- [ ] **Step 4: `RUN test_battle_save` 通过。**
- [ ] **Step 5: Commit** `git commit -m "test: foe/battle state saves and loads old saves"`

### Task 3: 一轮战斗的纯结算

**Files:**
- Create: `scripts/engine/battle_system.gd`
- Modify: `scripts/engine/army_system.gd`(`battle_odds` 注释去掉"PLACEHOLDER",保留公式并说明由 `BattleSystem` 使用)
- Test: `tests/engine/test_battle_resolve.gd`

**Interfaces:**
- Produces(全部 `static`):
  - `BattleSystem.roll(seed_value: int, side_a: Array, side_b: Array, day: int, round_no: int) -> int`(0..999,`hash` 取模,codes 先排序)。
  - `BattleSystem.eff_permille(odds_permille: int, roll: int, variance_permille: int) -> int` = `clampi(odds + (roll − 500) × variance / 1000, 0, 1000)`(整数除法,`@warning_ignore`)。
  - `BattleSystem.tier_of(repo: DataRepository, eff: int) -> Dictionary`(`battle_outcomes` 中 `eff_min <= eff < eff_max` 的行;`eff == 1000` 归末档)。
  - `BattleSystem.side_power(repo, state, codes: Array, stance_of: Callable, attacking: bool) -> int`(逐 regiment `ArmySystem.power(...)`,含高度系数,求和;姿态 `defence_permille` 只乘防守方)。
  - `BattleSystem.odds_permille(attack_power: int, defend_power: int) -> int` = `1000 × A / (A + D)`,`A + D == 0` 时 500。
  - `BattleSystem.split_losses(fit: int, loss_permille: int, wounded_share_permille: int) -> Dictionary`(`{"lost": fit×permille/1000, "wounded": lost×share/1000, "dead": lost − wounded}`)。
  - `BattleSystem.apply_round(repo, state, codes_att, codes_def, tier: Dictionary, reason: String) -> Dictionary`(按 `ArmySystem` 现有的 `wounded` / 各兵种头数扣减,最大余数法分摊到各 regiment 与兵种;士气按档增减并写入 reason;返回各 code 的 `{dead, wounded, morale}` 以便写战报)。

- [ ] **Step 1: 写失败的测试**(手算值):
  - `test_odds_permille`:`odds_permille(3000, 1000) == 750`;`odds_permille(0, 0) == 500`。
  - `test_eff_permille`:`eff_permille(600, 700, 300) == 660`;`eff_permille(900, 1000, 300) == 1000`(夹紧);`eff_permille(50, 0, 300) == 0`。
  - `test_tier_edges`:`eff 199`→第 1 档,`200`→第 2 档,`1000`→第 5 档。
  - `test_split_losses`:`split_losses(1000, 100, 700) == {"lost":100,"wounded":70,"dead":30}`;`split_losses(7, 100, 700)` 的 `lost` 为 0 且 `dead + wounded == lost`。
  - `test_roll_is_deterministic_and_order_free`:同参数同值;`side_a` 乱序传入同值;`day` 变则(对若干天)至少出现不同值。
  - `test_roll_leaves_game_rng_alone`:`state.rng.state` 在调用前后相同。
  - `test_apply_round_conserves_heads`:对一个玩家 regiment 套用一档,`dead + wounded + 完好 == 原头数`,各兵种头数非负。
  - `test_apply_round_zero_heads_no_divide`:头数为 0 的 regiment 不崩、不出负数。
- [ ] **Step 2: `RUN test_battle_resolve`**,预期 FAIL(类不存在)。
- [ ] **Step 3: 实现上述签名**,分摊用与 `MapManors.people_table` 同样的最大余数法(余数大者优先,同余数按 code / 兵种字典序)。
- [ ] **Step 4: `RUN test_battle_resolve`**,预期 PASS。
- [ ] **Step 5: Commit** `git commit -m "feat: BattleSystem round resolution"`

### Task 4: 战斗生命周期、姿态、战中命令与增援

**Files:**
- Modify: `scripts/engine/battle_system.gd`, `scripts/engine/action_system.gd`, `scripts/engine/tick_engine.gd`, `scripts/engine/army_system.gd`(regiment 状态加 `stance` 字段,默认 `steady`,老档补默认)
- Modify: `data/action_signatures.csv`、`data/order_costs.csv`、`data/policy_actions_court_additions.csv`(照 `ARMY_GARRISON` 行加 `ARMY_STANCE`)、`data/army_orders.csv`(菜单项)
- Test: `tests/engine/test_battle_lifecycle.gd`, `tests/engine/test_army_stance_order.gd`

**Interfaces:**
- Consumes: Task 3 的全部纯函数。
- Produces:
  - `BattleSystem.settle_day(repo: DataRepository, state: GameState) -> Array`(返回当天战斗事件字典数组 `{kind: "start"|"round"|"end", battle_id, ...}`,供战报)。顺序:`detect_contacts` → 对每场进行中的战斗(`battle_id` 升序)按 §4.1 打一轮 → 结束判定。
  - `BattleSystem.detect_contacts(repo, state) -> void`:野战接触(距离 ≤ `battle_contact_km`)与城战接触(敌在玩家持有城镇的 `army_town_reach` 内且 `SupplySystem.garrisoned_in` 有守军);已在战斗中的 regiment 不重复入战;接触到已有战斗的己方则 `join`。
  - `BattleSystem.join(state, battle_id, code, side) -> bool`(每方上限 `battle_max_units`)。
  - 战斗字典:`{id, att: Array, def: Array, start_day, rounds, place_x_m, place_y_m, town}`。
  - `ActionSystem` 的 `ARMY_STANCE {regiment, stance}`:同 `ARMY_GARRISON` 经 `_send_courier` 送出,信使抵达时把 `stance` 写入 regiment 状态;抵达日在战斗中则**下一天**起生效(结算在 `CourierSystem.ride_day` 之后、`BattleSystem.settle_day` 之前已保证)。
- 结束条件:某方全部 regiment 退出/溃败、打满 `battle_max_rounds`、或 `避战`姿态方接触首日脱离;脱离 = 该 regiment 从战斗移除并设 `ORDER_MARCH` 向己方最近城镇。战中被 `ARMY_MARCH` 离开的 regiment 同理移出,且战斗某方空了就结束,不留空战斗。

- [ ] **Step 1: 写失败的测试**
  - `test_field_contact_starts_one_battle`:摆一玩家 regiment 与一 foe 在 `battle_contact_km` 内 → `settle_day` 后 `state.battles.size() == 1`;两 regiment 的 `order` 不再行军。
  - `test_no_contact_no_battle`、`test_town_contact_needs_a_garrison`。
  - `test_round_matches_hand_computed_tier`:构造固定 power(把 `battle_variance_permille` 设 0 并固定 odds),断言第一轮后双方损失等于 `battle_outcomes` 对应档的 `split_losses`。
  - `test_battle_ends_after_max_rounds_or_rout`。
  - `test_evade_stance_leaves_on_first_contact`、`test_hold_stance_never_retreats`、`test_steady_retreats_below_retreat_odds`(姿态表数值断言来自 `repo.battle_stances`)。
  - `test_reinforcement_joins_and_is_capped`(`battle_max_units`)。
  - `test_stance_order_lands_after_day_end_and_applies_next_day`:`ARMY_STANCE` 的信使在第 N 天抵达,第 N 天战斗结算仍用旧姿态,第 N+1 天用新姿态。
  - `test_march_away_mid_battle_removes_unit`;`test_battle_with_one_side_emptied_ends`(Review Focus)。
  - `test_battle_state_is_deterministic`:同存档同输入跑 5 天,两遍 `battles` 与 regiment 状态逐项相等。
- [ ] **Step 2: `RUN test_battle_lifecycle`**,预期 FAIL。
- [ ] **Step 3: 实现。** `BattleSystem.settle_day` 与 `detect_contacts` 如上签名;`ARMY_STANCE` 在 `action_system.gd` 里照 `ARMY_GARRISON` 分支(`action_system.gd:171` 起、`:600` 附近)加分支与参数校验(姿态必须在 `battle_stances`、regiment 必须是玩家的);`order_costs.csv` 给一行成本(inv.8);`army_orders.csv` 加菜单项。
- [ ] **Step 4: `RUN test_battle_lifecycle`、`RUN test_army_stance_order` 通过。**
- [ ] **Step 5: Commit** `git commit -m "feat: battle lifecycle, stances, mid-battle orders, reinforcements"`

### Task 5: 战报 missive、`TickEngine` 挂接与 P1 验收

**Files:**
- Modify: `scripts/engine/tick_engine.gd`, `scripts/engine/missive_writer.gd`, `data/templates.csv`
- Test: `tests/engine/test_battle_report.gd`

**Interfaces:**
- Consumes: `BattleSystem.settle_day` 的事件数组。
- Produces: `MissiveWriter.battle_report(repo: DataRepository, state: GameState, events: Array) -> Dictionary`(与 `supply_dispatch` 同形,一天多场合并为一封);`TickEngine.day_battles: Array`(同 `day_supply` 模式)。
- `_end_day` 顺序:march(含 foes 第二遍,见 Task 6)→ `CourierSystem.ride_day` → **`BattleSystem.settle_day`** → 补给线 → 吃饭 → ……

- [ ] **Step 1: 测试**:`test_battle_day_writes_one_missive`;`test_report_numbers_come_from_the_engine`(missive 里的阵亡/伤兵数 == `apply_round` 返回值);`test_report_text_uses_templates_and_no_realm_names`(文本含 `battle_*` 模板输出,不含 pack 的王国名);`test_calm_day_writes_nothing`;`test_every_morale_change_carries_a_reason`(战后翻 regiment 的原因记录)。
- [ ] **Step 2: `RUN test_battle_report`**,预期 FAIL。
- [ ] **Step 3: 实现**:`templates.csv` 加 `battle_start`、`battle_round`、`battle_end_*` 键,文字写 `{player_realm}` / `{raider_realm}`;`tick_engine.gd` 挂接并保存 `day_battles`。
- [ ] **Step 4: `./run_tests.sh --fast` 全绿。**
- [ ] **Step 5: Commit** `git commit -m "feat: battle reports and tick hook (P1 done)"`

---

## Part 2 — 敌军 AI(spec P2)

### Task 6: 敌军出兵与行军

**Files:**
- Create: `scripts/engine/enemy_ai.gd`
- Modify: `scripts/engine/army_system.gd`(`march_day` 第二遍对 `foes` 按 code 序行军,复用 `_march_one`)
- Test: `tests/engine/test_enemy_spawn.gd`

**Interfaces:**
- Produces:
  - `EnemyAi.spawn(repo, state, host: Dictionary) -> void`:为 host 的每个 regiment 在 `state.foes` 建条目(`ArmySystem.starting_state` 的同形状 + `x_m/y_m` 取 host 起点整米 + `order = ORDER_STANDBY` + `host` 键),并建 `state.ai_hosts[host_code] = {mode: "ASSEMBLE", target_kind: "", target_id: "", think_day: 0, plunder: 0, siege_progress: 0}`。
  - `EnemyAi.step_day(repo, state) -> Array`(事件数组):`ASSEMBLE` 到 `appear_day` 转 `ADVANCE`。
  - `EnemyAi.host_codes(state) -> Array`(字典序)。
  - `EnemyAi.regiments_of(state, host_code) -> Array`。
- `NewGame` / `GameState.new_campaign` 调 `EnemyAi.spawn` 为 `repo.raid_hosts` 每行出兵(越境前它们站在集结点)。

- [ ] **Step 1: 测试**:`test_new_campaign_spawns_every_host`;`test_foes_are_not_in_player_regiments`(Review Focus 一);`test_assemble_waits_until_appear_day`;`test_foe_marches_with_the_same_even_step`(给 foe 一个目的地,`march_day` 的到达天数 == `ArmySystem.march_days_between`);`test_supply_lines_and_ledger_do_not_see_foes`(调用 `SupplyLines.day_step` 与 `ledger_resolvers` 的遍历不会因 foe 出错、输出不含 foe code)。
- [ ] **Step 2: `RUN test_enemy_spawn`**,预期 FAIL。
- [ ] **Step 3: 实现**;`march_day` 第二遍只对 `state.foes` 里 `order == ORDER_MARCH` 的条目调用 `_march_one`,到达则 `order = ORDER_GARRISON`,到达记录**不进** `day_arrivals`(foreign column 不是新闻)。
- [ ] **Step 4: `RUN test_enemy_spawn` 通过。**
- [ ] **Step 5: Commit** `git commit -m "feat: raid hosts spawn and march as foes"`

### Task 7: 选目标打分、决策节奏与多 host 协调

**Files:**
- Modify: `scripts/engine/enemy_ai.gd`
- Test: `tests/engine/test_enemy_ai_targets.gd`

**Interfaces:**
- Produces:
  - `EnemyAi.score(value: int, distance_days: int, defence: int, overlap: int, doctrine: Dictionary) -> int` = `value × greed_permille / 1000 − distance_days × dist_cost − defence × caution_permille / 1000 − overlap`。
  - `EnemyAi.candidates(repo, state, host_code) -> Array[Dictionary]`(`{kind: "manor"|"town", id, value, distance_days, defence}`,限 `ai_target_reach_km` 内、玩家持有、AI 看得见的守军;`defence` 为可见守军 `power` × `ArmySystem` 城防倍率)。
  - `EnemyAi.think(repo, state, host_code) -> void`:仅当 `state.absolute_day() − think_day ≥ ai_think_days`(或尚无目标)时重选;`reserve` 跟随 main 的目标;已被他 host 选中的目标对其 `overlap = score_base × ai_target_overlap_permille / 1000`;最高分 ≤ 0 → `mode = "WITHDRAW"`;平局 id 字典序。设目标后 `mode = "ADVANCE"` 并对 host 全部 regiment 下行军令(即时,不经信使)。
  - `EnemyAi.engages(repo, state, host_code, seen_player_codes: Array) -> bool`(§3.4 第 1 条:估 `odds_permille ≥ engage_odds_permille`)。
  - `EnemyAi.should_retreat(repo, state, host_code) -> String`(`""` / 原因串;低士气或 `ArmySystem.days_in_hand < ai_retreat_supply_days`;战败由 Task 4 的结束事件触发)。

- [ ] **Step 1: 测试**(手算):
  - `test_score_formula`:`score(5000, 3, 2000, 0, {greed 1000, caution 500, dist_cost 200}) == 3400`;含 `overlap 800` 得 `2600`。
  - `test_rich_weak_beats_rich_strong`;`test_raider_prefers_undefended_manor_main_prefers_town`(两作风取不同行)。
  - `test_two_hosts_do_not_pick_the_same_target`(Review Focus 四);`test_no_candidates_withdraws`。
  - `test_think_interval`:第 1–2 天不改目标,第 3 天才可改;`test_same_save_same_target`(确定性,无 rng)。
  - `test_reserve_follows_main`;`test_engage_threshold`;`test_retreat_on_low_morale_and_on_hunger`。
  - `test_ai_sees_only_what_is_in_sight`(视野外的玩家兵不入 `defence`)。
- [ ] **Step 2: `RUN test_enemy_ai_targets`**,预期 FAIL。
- [ ] **Step 3: 实现**:`value` 取 `MapManors.value_of_line`,城镇加 `town_bonus`;距离用 `ArmySystem.march_days_between`;全整数。
- [ ] **Step 4: `RUN test_enemy_ai_targets` 通过。**
- [ ] **Step 5: Commit** `git commit -m "feat: enemy AI target scoring and coordination"`

### Task 8: 预警事件、越境接线与 P2 验收

**Files:**
- Modify: `scripts/engine/enemy_ai.gd`, `scripts/engine/tick_engine.gd`, `scripts/engine/missive_writer.gd`, `data/templates.csv`, `data/chapter_events.csv` / `chapter_event_choices.csv` / `chapter_branches.csv`(若走章节链)与 `game_story/chapter_0/chapter_0_events.md`(固定散文)
- Test: `tests/engine/test_enemy_invasion.gd`

**Interfaces:**
- Produces:
  - `EnemyAi.warnings(repo, state) -> Array`:在 `appear_day − raid_rumour_lead_days` 发一封"传闻"missive(含糊,来源标"传闻");斥候(`SPY_SEND`)报告到达时若报告点附近有 foe,按 `intel_facts.csv` 机制给估计(沿用 `SpySystem`,不新开路径)。
  - `TickEngine._end_day` 在 `BattleSystem.settle_day` 之前调 `EnemyAi.step_day` 与 `EnemyAi.think`(整除 `ai_think_days` 之日由 `think` 自行判断)。
- 战前文字全是固定散文,`Voicer` 没有任何路径把预警或战报数字交给模型(`Voicer.voice_event` 本就不通 API)。

- [ ] **Step 1: 测试**:`test_rumour_arrives_before_the_invasion`(`appear_day − lead` 天出现且文字不含数字);`test_scout_report_names_a_credible_estimate`;`test_invasion_runs_headless_for_thirty_days`(`SuiteData.campaign` 推进 30 天:foe 在第 `appear_day` 离开 ASSEMBLE、向目标行军、至少一次 `battles` 非空或围城开始;全程无错误、两次运行状态逐项相同);`test_foes_withdraw_when_nothing_is_worth_it`。
- [ ] **Step 2: `RUN test_enemy_invasion`**,预期 FAIL。
- [ ] **Step 3: 实现**接线与预警;散文写进章节文档并通过 `StorySource` 的 heading / `**Scene:**` 契约(`test_chapter_zero.gd` 与内容测试必须仍绿)。
- [ ] **Step 4: `./run_tests.sh --fast` 全绿。**
- [ ] **Step 5: Commit** `git commit -m "feat: invasion timeline, rumours and AI wiring (P2 done)"`

---

## Part 3 — 围城、劫掠与战败后果(spec P3)

### Task 9: 围城

**Files:**
- Create: `scripts/engine/siege_system.gd`
- Modify: `scripts/engine/tick_engine.gd`, `data/templates.csv`
- Test: `tests/engine/test_siege.gd`

**Interfaces:**
- Produces:
  - `SiegeSystem.step(attack_power: int, defend_power: int, rate: int) -> int` = `rate × attack_power / (attack_power + defend_power)`(`A + D == 0` → 0)。
  - `SiegeSystem.settle_day(repo, state) -> Array`(事件数组):对 `mode == "SIEGE"` 的 host(host_code 序):守军 = `TownStores` / `SupplySystem.garrisoned_in` 该城的 regiment,`defend_power` 含 `army_town_defence` 倍率;累加 `siege_progress`;每 `siege_assault_days` 天发起强攻(借 `BattleSystem` 起一场以该城为 `town` 的战斗,结果影响进度:攻方受挫减、守方溃败加满,幅度取 `battle_outcomes` 附加列或 `siege_*` 键);断粮:城存粮耗尽则进度加速 `siege_starve_bonus_permille`,敌自身断粮由 `should_retreat` 处理;`siege_progress ≥ 1000` 或守军全灭 → `capture(repo, state, host_code)`。
  - `SiegeSystem.capture(repo, state, host_code) -> void`:`MapOwnership.set_owner`(城镇所在省的移交遵循现有省级 API)与 `MapManors.set_owner`(周边庄园),reason 如 `"taken by <host label>: siege of <town>"`;host `mode = "HOLD"`;触发 `DefeatSystem.on_town_lost`(Task 11)。
  - `SiegeSystem.relieved(repo, state, host_code) -> bool`:玩家夺回(城已回到玩家手)或守方在战斗中 `守方溃败的反面` 使敌撤退 → host `mode = "RETREAT"`,`siege_progress = 0`。
- 围城中若城已易主或守军已被调走:不累加、不二次换主(Review Focus 五)。

- [ ] **Step 1: 测试**(手算):
  - `test_siege_step`:`step(3000, 1000, 100) == 75`;`step(0, 0, 100) == 0`。
  - `test_progress_accumulates_daily`、`test_capture_at_1000_changes_owner_with_a_reason`(territory log 含 reason)。
  - `test_assault_cadence`、`test_failed_assault_lowers_progress`、`test_routed_defender_adds_the_rest`。
  - `test_starving_town_speeds_the_siege`、`test_starving_besieger_retreats`。
  - `test_relief_force_joins_battle_and_can_lift_siege`。
  - `test_no_double_capture_and_no_progress_after_loss`;`test_recaptured_town_sends_hold_host_retreating`(Review Focus 五、六)。
  - `test_siege_is_deterministic`。
- [ ] **Step 2: `RUN test_siege`**,预期 FAIL。
- [ ] **Step 3: 实现**;围城战报并入 Task 5 的 `battle_report`。
- [ ] **Step 4: `RUN test_siege` 通过。**
- [ ] **Step 5: Commit** `git commit -m "feat: siege progress, assaults, starvation, capture"`

### Task 10: 劫掠、危险区与战利品

**Files:**
- Create: `scripts/engine/raid_system.gd`
- Modify: `data/hazard_kinds.csv`(加 `Raided` 行:`months`、`public` 1、`wounds_permille`、`morale`、`supply_loss_permille`、`pace_permille`),`scripts/engine/tick_engine.gd`
- Test: `tests/engine/test_raid.gd`

**Interfaces:**
- Produces:
  - `RaidSystem.day_take(repo, state, host_code) -> int`:`mode == "RAID"` 且 host 站在目标庄园上时,抽走 `ManorEconomy.line_of` 月产出的 `raid_plunder_permille / 30`(整数,逐日;累计不超过该庄园月产出),计入 `ai_hosts[host]["plunder"]` 并入 host regiment 的 `supplies`(补给);首次劫掠该庄园时 `Hazards.add(state, id, "Raided", ...)`(id 含庄园 cell,幂等)。
  - `RaidSystem.spoils(repo, state, host_code, winner: String) -> int`:击败 host 时按 `battle_spoils_permille × plunder / 1000` 记入国库 `strategic`,带原因 `"spoils: <host label> routed at <place>"`。
  - `RaidSystem.settle_day(repo, state) -> Array`。
- 玩家的 `ManorEconomy` 月结算须看见被劫掠的损失:通过 `GameState` 已有的 manor 效果通道(沿用 `Hazards.wounds/morale/supply_loss` 路径),不改 `line_of` 的取整点(inv.11)。

- [ ] **Step 1: 测试**:`test_daily_take_is_whole_gold_and_capped`(手算:月产出 3000、`raid_plunder_permille` 600 → 一天 60,满 30 天封顶 1800;断言取整与封顶);`test_plunder_feeds_the_host`;`test_hazard_added_once_and_known`;`test_spoils_into_strategic_with_reason`(手算:plunder 1800、`battle_spoils_permille` 500 → 900);`test_routed_raider_with_no_plunder_yields_nothing`;`test_raid_is_deterministic`。
- [ ] **Step 2: `RUN test_raid`**,预期 FAIL。
- [ ] **Step 3: 实现**并挂入 `_end_day`(`BattleSystem` 之后、`SiegeSystem` 同段)。
- [ ] **Step 4: `RUN test_raid` 通过。**
- [ ] **Step 5: Commit** `git commit -m "feat: raiding, raided hazard, spoils"`

### Task 11: 战败后果

**Files:**
- Create: `scripts/engine/defeat_system.gd`
- Modify: `data/templates.csv`, `data/chapter_events.csv` / `chapter_event_choices.csv`(丢城固定散文事件,走现有 `EventSystem` 链)
- Test: `tests/engine/test_defeat.gd`

**Interfaces:**
- Produces:
  - `DefeatSystem.on_town_lost(repo, state, town_code: String, host_code: String) -> Array`:① 国库扣 `battle_defeat_treasury_permille`‰(整数,带原因的账目,经现有 ledger 行通道,不新开写路径);② 全国民心 `battle_defeat_morale`(经 `WorldLedger.apply` 的 schema 路径,原因串 `"−8: lost <town> to the raiders"`,走 `data/world_schema.csv` 已列的民心路径,若无对应路径则在该 CSV 加一行并带 `llm_cap`);③ 对每个议会席位调 `Character.change_opinion(delta, reason, tick)`,delta 由席位 ideology / 个性查现有 `opinion_drift` 表机制(不新建表,复用 `OpinionDrift.apply` 的签名与 reason 约定);④ 排程丢城事件。同一城同一次失守只触发一次(幂等,以 `territory_log` 条目为键)。
  - 夺回不退款(`DefeatSystem` 对夺回无动作)。
- 不 Game Over:任何路径都不得终止战役。

- [ ] **Step 1: 测试**(手算):`test_treasury_hit`(国库 10000、`battle_defeat_treasury_permille` 100 → 扣 1000,账目含原因);`test_morale_hit_has_a_reason`;`test_every_councillor_opinion_change_has_a_reason`;`test_triggers_once_per_loss`;`test_recapture_refunds_nothing`;`test_campaign_continues_after_losing_a_town`(丢城后推进数天,状态机、时钟、存档均正常);`test_loss_event_is_scheduled_and_text_names_no_realm`。
- [ ] **Step 2: `RUN test_defeat`**,预期 FAIL。
- [ ] **Step 3: 实现**并接入 `SiegeSystem.capture`。
- [ ] **Step 4: `./run_tests.sh --fast` 全绿。**
- [ ] **Step 5: Commit** `git commit -m "feat: defeat consequences (P3 engine done)"`

### Task 12: 指南、隔离与整体验收

**Files:**
- Create: `scripts/engine/guide/battle_and_ai.md`
- Modify: `scripts/engine/CLAUDE.md`(仅 Topic guides 加一行索引,点名 `BattleSystem` / `EnemyAi` / `SiegeSystem` / `RaidSystem` / `DefeatSystem`),`tests/engine/test_engine_isolation.gd`(若新类需登记则登记)
- Test: `tests/engine/test_invasion_end_to_end.gd`

- [ ] **Step 1: 写端到端测试**:`test_scripted_invasion_end_to_end`(`SuiteData.campaign` 无头推进 40 天,断言:预警 → 越境 → 至少一场战斗 → 围城或劫掠发生 → 所有事件带原因 → 存档在第 20 天序列化/读回后继续,与不间断运行的第 40 天状态逐项相同);`test_new_classes_are_engine_pure`(四个新类文件不含 `Game.` / `scripts/ui` / `scripts/llm` 字样)。
- [ ] **Step 2: `RUN test_invasion_end_to_end`**,预期:先 FAIL 则据此修复 Task 6–11 的接缝。
- [ ] **Step 3: 写指南**:按"规则的现状"写(无历史叙述),覆盖状态机、打分公式键名、战斗结算顺序、`foes` 与 `regiments` 的边界、战中命令生效时点、围城/劫掠/战败的键;数值只写键名不写值。
- [ ] **Step 4: 全量验证**:`./run_tests.sh`,预期错误数 0(或仓库预期的 2),`test_claude_md_size.gd` 绿。
- [ ] **Step 5: Commit 并推送** `git add -A && git commit -m "docs+test: battle and AI guide, end-to-end invasion test" && git push -u origin claude/lucid-edison-krwp7f`
- [ ] **Step 6: 收尾说明(写给用户)**:P1–P3 完成;P4(战斗标记、幽灵棋子、战报 UI)与任何视觉改动仍待本地会话的编辑器步骤和 `visual-review`。

---

## Self-Review

- **Spec 覆盖:** §2 数据/时间线 → Task 1、6、8;§3 AI → Task 6–8;§4 战斗与干预 → Task 3–5;§5 围城/劫掠 → Task 9–10;§6 战败 → Task 11;§7 数据与落点 → Task 1、12;§8 测试 → 各任务;§9 P4 → 明确排除。
- **与 spec 的唯一偏差:** 敌军状态放 `GameState.foes` 而非 `regiments`(Task 1 同步改 spec),原因是 `regiments` 有 30+ 处玩家专用遍历。
- **类型一致:** `BattleSystem` 的 `tier` 字典键、`ai_hosts` 的字段名(`mode / target_kind / target_id / think_day / plunder / siege_progress`)在 Task 1、7、9、10 同名;`EnemyAi.score` 与 `ai_doctrines` 的列名(`greed_permille / caution_permille / dist_cost`)一致。
- **比例:** 计划只写签名、手算断言与落点,不写函数体。
