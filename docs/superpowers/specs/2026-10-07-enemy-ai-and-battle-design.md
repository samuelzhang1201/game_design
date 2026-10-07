# 简易敌军 AI 与两军战斗系统 — 设计

Status: 设计草案 2026-10-07(brainstorm),待 owner 裁定 §9 的开放问题。**Default** 标记 owner 尚未裁定的选择。
接续 `2026-09-30-ledger-battle-design.md`(M4:`ARMY_ATTACK`、`battle_outcomes.csv`、哈希抽签、战利品)——本文把它从"需要第一支敌军才能落地"推进到"敌军和战斗一起落地",并补上敌方 AI。

## 1. 目标与边界

- 约第 15 天,{raider_realm} 的一支袭击军越境,沿路推进、围攻/劫掠,玩家要靠**信使延迟下的指挥**(调兵、补给、驻防)去应对。
- **简易**:一个确定性的有限状态机 + 打分选目标,没有寻路(沿用直线行军)、没有阵型微操、没有外交 AI。
- 不破坏任何不变量:引擎决定、LLM 只写战报文字(inv.1);无 `GameState.rng`、无墙钟(inv.2);纯 `RefCounted`、不碰 `Game`/`ui`/`llm`(inv.3);每个状态变化带原因(inv.4);数字全进 CSV(root rules)。

## 2. 敌军是什么(数据)

敌军 **就是普通 regiment**,不另造一套兵:
- 进 `GameState.regiments`(kingdom = `{raider_realm}`),所以 `ArmySystem.march_day` / `power` / `fit_permille` / 补给 `eat_day` / 地形 / 高度 / 城防全部原样复用,存档不需要新格式。
- 敌方"阵营"关系已有:`army_hostile_stances.csv` 的 `Enemy` 立场。
- 新增 `GameState.ai_hosts`(saved,整数/字符串,无浮点):`host_code → {mode, target_kind, target_id, think_day, plunder, started_day}`。
- 出兵数据:`data/maps/<id>/military/raid_hosts.csv`(哪个王国、哪些 regiment 编成、出发点、`appear_day`),不改 `regiments.csv`。

## 3. 入侵时间线(默认)

| 天 | 事件 |
|---|---|
| 约 8 | 前哨/商旅**传闻**:边境有人聚兵(一条 missive,故意含糊,来源标"传闻") |
| 约 12 | 玩家若派了斥候(`SPY_SEND`)可得**可信**报告;否则只有传闻 |
| 15 | 袭击军越境(`appear_day`),此后每天按 §4 行动 |
| 15–25 | 推进 → 交战/围攻 → 玩家有约一周时间反应(信使往返 3–5 天,这是核心张力) |

`appear_day` 与预警天数都是 `balance.csv` 键(`raid_appear_day`、`raid_rumour_lead_days`),不写死。作为章节事件接入现有链(`TriggerDsl` + `branch:`),预警事件的文字是**固定散文**,不由模型生成(root CLAUDE.md)。

## 4. 敌方 AI

### 4.1 状态机(每个敌军 host 一个)

```
ASSEMBLE → ADVANCE → ENGAGE ⇄ SIEGE/RAID → WITHDRAW
                         ↓
                      (RETREAT)  ← 士气崩 / 断粮 / 被击溃
```

- **ASSEMBLE**:越境前在集结点停留,到 `appear_day` 转 ADVANCE。
- **ADVANCE**:向当前目标直线行军(现成 `ARMY_MARCH` 的引擎路径,敌方**不经信使**,令即时生效——AI 的指挥官就在军中)。
- **ENGAGE**:与玩家 regiment 接触 → §5 战斗。
- **SIEGE**:到达守军城镇后围城,见 §6;**RAID**:目标是无城防的庄园,劫掠。
- **WITHDRAW/RETREAT**:撤向出发点,途中不再选新目标。

### 4.2 决策节奏与确定性

- 每 `ai_think_days` 天(Default 3)才重新决策一次;期间沿用上次目标。这既省算力,也让玩家能"读到"敌军意图。
- 决策**不用随机数**。平局按 id 字典序。需要抽签处(战斗)用 §5 的哈希,不碰 `GameState.rng`。
- 敌军**只看见它能看见的**:`ai_sight_km` 内的玩家 regiment 和已知城镇(双向迷雾:AI 不作弊,玩家也靠 `Intel`)。

### 4.3 选目标:一个打分公式

对每个候选目标(越境后 `ai_target_reach_km` 内的玩家庄园/城镇):

```
score = value × greed − distance_days × dist_cost − defence × caution
  value    = MapManors.value_of_line(...)(城镇另加 town_bonus)
  defence  = 估计守军 power × works 倍率(army_town_defence.csv),只算 AI 看得见的
  distance = ArmySystem.march_days_between(...)
```

`greed`、`caution`、`dist_cost` 来自 `data/ai_doctrines.csv`(一行一个"作风":`raider` 贪、怕硬仗;以后可加 `conqueror`)。选分最高者;若最高分 ≤ 0 → WITHDRAW。
效果:袭击军**专挑富而弱的软柿子**,绕开重兵城池,玩家的驻防决策因此有意义(把兵放在值钱的地方 vs 放在路口)。

### 4.4 遇敌规则(每天)

1. 视野内出现玩家 regiment:估计 `odds`(§5 公式,用 AI 眼中的信息),`odds ≥ ai_engage_odds`(Default 0.45)→ 转攻;否则绕开/继续目标。
2. 自身 `morale < ai_retreat_morale` 或 `days_in_hand < ai_retreat_supply_days` → RETREAT。
3. 战败(§5 的溃败档)→ RETREAT,并保留残兵(不是原地消失)。

### 4.5 补给(让战役有"尾巴")

敌军开局带 `army_start_supply_days` 同类的口粮;**劫掠到手的庄园补给其粮**(plunder → supplies),围城久了会断粮。玩家的反制手段:切其补给(已有 `SupplyLines` 概念)、焚烧/迁移存粮、拖延。

## 5. 战斗系统

### 5.1 触发

每天 `TickEngine.advance_day` 在**所有 regiment 行军结算之后**检查接触:
- 野战:两个敌对 regiment 距离 ≤ `battle_contact_km`;
- 城战:敌军在玩家持有城镇 `army_town_reach` 内且有守军(`SupplySystem.garrisoned_in`)。

接触后进入**战斗**,一天打一轮,最多 `battle_max_rounds` 轮(Default 3);任一方溃败即止。玩家**不能**在战斗中下令(信使太慢)——战前准备才是玩家的操作面。

### 5.2 一轮的计算(全是整数)

```
A = power(attacker, "attack")  × height_factor(Δh) / 1000        ← 已有 battle_odds 内部
D = power(defender, "defend")  × height_factor(−Δh) / 1000        ← 地形、城防 works 已含在 power_on 里
odds = A / (A + D)                                                  ← 已有 battle_odds,转为正式实现
roll = hash(seed, attacker_code, defender_code, absolute_day, round) % 1000
eff  = clamp(odds_permille + (roll − 500) × battle_variance_permille / 1000, 0, 1000)
tier = battle_outcomes.csv 里 eff 所在的档
```

- **兵种克制**:`army_matchups.csv` 已经由 `power_on` 的 `_arm_base` 吃进去,无需新表。
- **方差**很关键:`battle_variance_permille`(Default 300)让 2:1 优势基本稳赢、势均力敌才真有悬念;不是纯骰子。
- 抽签**独立于 `GameState.rng`**(同 `2026-09-30-ledger-battle-design.md` §1):同存档同输入 ⇒ 同结果,且战斗不会扰动经济随机流。

### 5.3 结果档(`data/battle_outcomes.csv`)

| 档 | eff 区间(默认) | 攻方损失 | 守方损失 | 士气 攻/守 | 后果 |
|---|---|---|---|---|---|
| 攻方溃败 | 0–200 | 重 | 轻 | −/+ | 攻方 RETREAT |
| 攻方受挫 | 200–400 | 中 | 轻 | −/0 | 战斗继续 |
| 僵持 | 400–600 | 中 | 中 | 0/0 | 战斗继续 |
| 守方受挫 | 600–800 | 轻 | 中 | 0/− | 战斗继续 |
| 守方溃败 | 800–1000 | 轻 | 重 | +/− | 守方撤退/失城 |

列:`attacker_loss_permille, defender_loss_permille, wounded_share_permille, attacker_morale, defender_morale, rout(攻/守/无)`。
损失先转为**伤兵**(`wounded`,按 `army_wound_recovery_permille` 逐月恢复),`wounded_share` 之外的才是阵亡(从各兵种头数里按比例扣,整数、最大余数法,和 `MapManors.people_table` 同法)。战败/溃兵不是"消失":残兵走 `army_formations.csv` 的"残兵"档,仍是可再用的 regiment。

### 5.4 战后

- 每次战斗写一条**战报 missive**(`MissiveLog`):结果档、双方损失、是谁的报告(指挥官的转述,可带 `glory/blame/silence` 失真——`intel` 设计里已有)。**战报的文字**:模板(`templates.csv`,`battle_*` 键)为主,重大战斗可走 `Voicer` 润色叙述,但**数字与结果由引擎给**(inv.1,模型只写话)。
- 士气、伤兵写入 regiment 状态,每笔带原因串(inv.4),如 `"morale −15: lost the field at <place>"`。
- 议会反应:败仗/失城触发已有机制的 opinion 变化(带原因),不新建 opinion 系统。

## 6. 围城与劫掠(简易版)

- **围城**:敌军停在玩家持有城镇外,每天 `siege_progress += siege_rate × (敌 power / (敌 power + works 倍率后的守军 power))`;`progress ≥ 1000` → 城破:`MapOwnership.set_owner` / `MapManors.set_owner`(**必须带原因**,inv.4)。守军被打光或士气崩提前破城。
- **劫掠**:占领无防庄园期间,每天按 `raid_plunder_permille` 抽走其月产出(`ManorEconomy.line_of` 的整数),计入 host 的 `plunder`,并产生 `Hazards` 里的"劫掠"类危险区(`hazard_kinds.csv` 增一行:损失补给、士气、拖慢行军),玩家路过也受影响。
- **战利品**(沿用 M4 §1):击败袭击军 → 夺回 `battle_spoils_permille × plunder` 进国库 `strategic`。**这是玩家的奖励回路**,让"主动出击"值得。

## 7. 玩家的操作面

不加新的"战斗界面"——全部用已有杠杆,让**信使延迟 + 迷雾 + 补给**自己出戏:
1. 预判:斥候(`SPY_SEND`)、传闻 → 猜敌军目标(AI 的打分规则是"可读"的:专挑富而弱)。
2. 调兵:`ARMY_MARCH`(信使送令,3–5 天)、`ARMY_GARRISON` 进城、`ARMY_ATTACK`(M4,新增)。
3. 备战:补给线(`SupplyLines`)、`army_carry` 载粮、训练(`war_drills.csv`)、城防(`MANOR_BUILD` 城墙)。
4. 议会:元帅(Marshal)席位提出**真实的** `action_code` 建议(inv.1,永远合法可负担);点击建议不调模型(inv.9)。
5. 战地呈现:WAR ROOM 的棋子/标记显示敌军 host 为"幽灵"(按 `intel` 设计,其数字永远是**估计**,来源与日期标明);战斗发生时在地图上放一个临时战斗标记。**视觉部分需本地会话 + `visual-review`**,云端不做。

## 8. 数据与代码落点

**新 CSV**:`data/battle_outcomes.csv`、`data/ai_doctrines.csv`、`data/maps/<id>/military/raid_hosts.csv`;`hazard_kinds.csv` 加"劫掠"行;`templates.csv` 加 `battle_*`;`balance.csv` 新键:`battle_contact_km`、`battle_max_rounds`、`battle_variance_permille`、`battle_spoils_permille`、`ai_think_days`、`ai_sight_km`、`ai_engage_odds`、`ai_retreat_morale`、`ai_retreat_supply_days`、`ai_target_reach_km`、`siege_rate_permille`、`raid_appear_day`、`raid_rumour_lead_days`、`raid_plunder_permille`。

**新引擎类**(均 `RefCounted`,`scripts/engine/`):
- `BattleSystem` — 接触检测、一轮结算、结果档应用(取代 `ArmySystem.battle_odds` 的占位注释,公式本身保留)。
- `EnemyAi` — 状态机、打分、决策节奏;只读 `GameState`+`DataRepository`,通过 `ArmySystem`/`MapOwnership` 现有入口改状态。
- `SiegeSystem`(可并入 `BattleSystem`)。

**挂接点**:`TickEngine.advance_day`:march → `EnemyAi.think`(整除 `ai_think_days` 的日子)→ `BattleSystem.settle_day` → couriers。`GameState` 加 `ai_hosts`(存/读都走 `_encode_values`/`_decode_values`)。
**指南**:落地时把规则写进 `scripts/engine/guide/regiments.md`(或新开 `guide/battle_and_ai.md` 并在 `CLAUDE.md` 的 Topic guides 登记)。

## 9. 开放问题(请 owner 裁定;每条附推荐)

1. **"约 15 天"指什么?** 推荐:新战役第 15 天越境(绝对天数,`raid_appear_day`),不挂在某个章节事件上;若想挂在 C0 的某一幕,改成"该幕后第 15 天"。
2. **战斗是否可由玩家实时干预?** 推荐:**否**(见 §5.1),玩家的操作面在战前;否则就要做战术界面,和"信使延迟"的核心设定冲突。
3. **城破后的后果**:推荐 v1 只做"围城 + 劫掠 + 夺城(换主人)";占领区治安、解放战争留到后续。
4. **敌军数量**:推荐 1 支主力 + 1 支偏师(共 2 个 host),玩家兵力被迫分兵;做 1 支更简单、更好调。
5. **战败是否能 Game Over?** 推荐:**否**(章节是教程),上限是丢一座城 + 国库/民心打击,败仗走已有的议会反应。
6. **敌军是否消耗信使/走道路?** 推荐 v1 沿用"直线行军、无寻路",与玩家军一致;道路加速已由 `army_road_reach_m` 处理。

## 10. 测试(先写手算值,inv. Done-means #2)

- `battle_odds`:给定双方 power,手算 `A/(A+D)`,含高度修正。
- 抽签:同 (seed, 两个 code, 天, 轮) → 同结果;**调用前后 `GameState.rng` 状态不变**。
- 结果档:每档的损失/伤兵/士气,整数、总数守恒(阵亡+伤兵+完好 = 原头数)。
- `EnemyAi`:同存档同输入 → 同目标;打分表(富而弱的目标胜过强而富的);无目标 → WITHDRAW;断粮/低士气 → RETREAT;`ai_think_days` 节奏。
- 围城:`progress` 累加手算;城破时 `set_owner` 带原因。
- 劫掠:`plunder` = 手算月产出份额;战利品入 `strategic` 带原因。
- 存档往返:`ai_hosts` 保存/读取后继续行为一致(`SuiteData.campaign`)。
- `test_engine_isolation.gd`:新类不引用 `ui`/`llm`/`Game`。

## 11. 分期(每期可独立验收)

- **P1 战斗核心**:`BattleSystem` + `battle_outcomes.csv` + 接触检测 + 战报 missive;用测试里手工摆两支军验证。
- **P2 敌军 AI**:`EnemyAi` + 越境事件 + 预警传闻 + 撤退;能完整跑一场"敌军来、玩家守"的无头模拟。
- **P3 围城/劫掠/战利品**:`SiegeSystem`、劫掠危险区、战利品回路、议会反应。
- **P4 呈现**:战斗标记、敌军幽灵棋子、战报 UI —— 本地会话 + `visual-review`。
