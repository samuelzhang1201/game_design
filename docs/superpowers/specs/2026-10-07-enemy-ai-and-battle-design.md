# 敌军 AI 与两军战斗系统 — 设计

Status: 设计已在 brainstorming 中逐段确认(2026-10-07),待 owner 审阅本书面 spec。接续 `2026-09-30-ledger-battle-design.md`(M4:`ARMY_ATTACK`、`battle_outcomes.csv`、哈希抽签、战利品),把它从"需要第一支敌军才能落地"推进到"敌军、战斗、围城一起落地"。**Default** 标记 owner 尚未明确裁定的数值或选择;所有数值最终是 CSV / `balance.csv` 键,不进脚本。

## 1. 目标、范围与成功标准

**定位(owner 选 A):** 教程章节里的一次性压力事件,不是通用战争框架。第 15 天前后,{raider_realm} 的多支部队越境,玩家要在信使延迟与迷雾下组织防御。

**范围内:**
- 敌军多支部队(默认 3 支:主力、劫掠队、后队),各有决策。
- 两军战斗系统,**允许玩家干预**(战前姿态 + 信使送达的战中命令 + 增援)。
- 围城的完整过程(进度、强攻、断粮、解围);劫掠;战利品。
- 战败后果:丢一座城,国库与民心各扣一笔,走已有的议会反应。**不 Game Over。**

**范围外(不做):** 夺城之后的治安与占领区行政;外交 / 宣战状态;战术阵型;寻路(沿用直线行军);敌国多作风的现成内容(只留 `ai_doctrines.csv` 加一行即可扩展的数据接口)。

**成功标准:** 敌军行为可读(玩家能从传闻和斥候猜到它想打哪里)、可应对、结果确定;存档往返一致;不破坏任何不变量。

**不变量对照:** 引擎决定、LLM 只写战报文字(inv.1);无 `GameState.rng`、无墙钟,抽签用哈希(inv.2);新类 `RefCounted`,不引用 `ui` / `llm` / `Game`(inv.3);每个状态变化带原因串(inv.4);故事文字用 `{raider_realm}` 等占位,不点名王国(inv.5);存档仍是一个 JSON(inv.7);每道命令有成本,沿用 `order_costs.csv`(inv.8);成本纪律,战报以模板为主(inv.9);整数,无浮点入存档(inv.2、inv.11)。

## 2. 敌军的数据模型与入侵时间线

**敌军就是普通 regiment 的形状。** 条目放进 `GameState.foes`(与 `regiments` 同形状,所属 `{raider_realm}`),**不**放进 `regiments`:后者有三十多处遍历默认只含玩家的兵(补给线、LEDGER、危险区、地图)。`ArmySystem.state_of` 与 `march_day` 额外接纳 `foes`,行军、`power`、地形、高度、城防因此全部复用 `ArmySystem`;敌军补给由 `EnemyAi` 自己结算。敌对关系已有:`army_hostile_stances.csv` 的 `Enemy`。

**编成:** `data/maps/<id>/military/raid_hosts.csv`,一行一个 host:`host_code, regiments, appear_day, role, start_x, start_y`。`role` 取三值:
- `main` 主力:偏向富裕城镇,主要围城对象。
- `raider` 劫掠队:偏向无防庄园,速度快、兵少。
- `reserve` 后队:无自己的目标,跟随主力,主力受挫或围城停滞时才前出。

默认 3 支(1 主力、1 劫掠队、1 后队),数量是数据。

**AI 状态(存档)**:`GameState.ai_hosts`:`host_code → {mode, target_kind, target_id, think_day, plunder, siege_progress}`;进行中的战斗 `GameState.battles`(见 §4)。全是整数和字符串。

**时间线(`balance.csv` 键 `raid_*`,Default):**

| 天 | 事件 |
|---|---|
| 约 8 | 边境传闻:有人聚兵(一封含糊的 missive,来源标"传闻") |
| 约 12 | 派了斥候(`SPY_SEND`)则得可信报告:几支、大概多少人 |
| 15 | `main`、`raider` 越境 |
| 约 18 | `reserve` 越境(由其 `appear_day` 决定) |
| 15–30 | 推进 → 交战 / 围城 / 劫掠;玩家约有一周反应 |

`appear_day` 是战役的**绝对天数**,不挂在某个章节事件上。预警事件是固定散文(不由模型写),经现有章节链(`TriggerDsl`、`branch:`)接入。

**迷雾对称:** AI 只看得见 `ai_sight_km` 内的玩家 regiment 和已知城镇;玩家这边敌军是"幽灵",数字永远是估计,来源与日期标明(`Intel`)。

## 3. 敌方 AI

### 3.1 状态机(每个 host 一个)

```
ASSEMBLE → ADVANCE → ENGAGE ⇄ SIEGE / RAID → HOLD
                       ↓
                    RETREAT      (士气崩 / 断粮 / 战败)   →  WITHDRAW
```

- **ASSEMBLE**:在集结点待命,到 `appear_day` 转 ADVANCE。
- **ADVANCE**:向当前目标直线行军;敌方指挥官在军中,命令即时生效,不经信使。
- **ENGAGE**:与玩家 regiment 接触后进入 §4 的战斗。
- **SIEGE / RAID**:见 §5。**HOLD**:夺城后停留城中,不再前进。
- **RETREAT / WITHDRAW**:撤回出发点,途中不再选新目标。

### 3.2 决策节奏与确定性

- 每 `ai_think_days`(Default 3)天重新决策一次;期间沿用上次目标,玩家可"读到"意图。
- 决策**不用随机数**;平局按 id 字典序。唯一抽签处是战斗(§4),用哈希。

### 3.3 选目标:一个打分公式

对 `ai_target_reach_km` 内每个候选目标(玩家庄园或城镇):

```
score = value × greed − distance_days × dist_cost − defence × caution − overlap
  value    = MapManors.value_of_line(...)(城镇另加 town_bonus)
  defence  = AI 看得见的守军 power × 城防倍率(army_town_defence.csv)
  distance = ArmySystem.march_days_between(...)
  overlap  = 已被另一支 host 选中的目标,按 ai_target_overlap_permille 打折
```

`greed`、`caution`、`dist_cost`、`engage_odds`、`retreat_morale` 取自 `data/ai_doctrines.csv` 中该 host `role` 对应的一行;取分最高者,最高分不大于 0 → WITHDRAW。`reserve` 无自己的目标,跟随主力。多 host 因此会分兵,玩家也被迫分兵。

### 3.4 遇敌与撤退(每天检查)

1. 视野内出现玩家 regiment,AI 用自己看到的数字估 `odds`:不低于 `engage_odds`(Default 0.45)→ ENGAGE;否则绕开,或继续原目标。
2. 自身士气低于 `retreat_morale`,或补给低于 `ai_retreat_supply_days` 天 → RETREAT。
3. 战败(战斗溃败档)→ RETREAT,保留残兵。

### 3.5 补给

敌军开局带 `army_start_supply_days` 天口粮;劫掠所得庄园补给其粮;围城久了会断粮。玩家反制:切补给线、焚烧或转移存粮、拖延。

## 4. 战斗系统(允许玩家干预)

**核心矛盾:** 命令靠信使,战斗不能等。解法:**战斗打多天,命令靠信使在战斗中途送到,另有战前设好的姿态**。干预是提前部署加延迟补救,不是实时操作。

### 4.1 触发与时长

每天 `TickEngine.advance_day` 在所有 regiment 行军结算之后检查接触:野战是两个敌对 regiment 距离不超过 `battle_contact_km`;城战是敌军在玩家持有城镇的 `army_town_reach` 内且城里有守军。接触后开始一场**战斗**(`GameState.battles`:参战双方 regiment 列表、起始日、已打轮数),每天一轮,最多 `battle_max_rounds`(Default 5)轮;一方溃败、撤退或打满轮数即止。战斗中的 regiment 不行军,只吃补给。

### 4.2 一轮的计算(全整数)

```
A = Σ power(攻方各 regiment,"attack") × 高度系数 / 1000      ← 沿用 ArmySystem.battle_odds 内部
D = Σ power(守方各 regiment,"defend") × 高度系数 / 1000      ← 地形、城防已含在 power_on 里
odds = A / (A+D) × 姿态修正
roll = hash(seed, 双方代码, 绝对日, 轮次) % 1000
eff  = clamp(odds_permille + (roll − 500) × battle_variance_permille / 1000, 0, 1000)
结果 = battle_outcomes.csv 中 eff 所在的档
```

抽签独立于 `GameState.rng`(同存档同输入同结果,且不扰动经济流)。兵种克制由 `army_matchups.csv` 经 `power_on` 自动带入。

### 4.3 结果档(`data/battle_outcomes.csv`)

五档:攻方溃败 / 攻方受挫 / 僵持 / 守方受挫 / 守方溃败。列:`eff_min, eff_max, attacker_loss_permille, defender_loss_permille, wounded_share_permille, attacker_morale, defender_morale, rout`(攻 / 守 / 无)。损失先转为伤兵(`wounded`,按 `army_wound_recovery_permille` 逐月恢复),其余才是阵亡,从各兵种头数里按比例扣(最大余数法,整数,与 `MapManors.people_table` 同法)。战败 / 溃兵不消失,残兵走 `army_formations.csv` 的"残兵"档,仍是可用 regiment。

### 4.4 玩家干预:两层

**(a) 战前姿态(`data/battle_stances.csv`),regiment 的常驻命令,通过现有信使设定:**

| 姿态 | 效果 |
|---|---|
| 死守 | 防御修正提高,士气下降较慢,**不会主动撤退** |
| 稳扎 | 无修正;`odds` 低于 `retreat_odds` 时自动撤退 |
| 避战 | 防御降低;接触第一天即脱离撤退 |

**(b) 战中命令,靠信使:** 命令照常经 `CourierSystem` 送出,到达时刻是**当天结算之后**,下一天的战斗按新命令执行:撤退(`ARMY_MARCH` 离开,可能受追击损失)、增援(`ARMY_MARCH` 到战场,抵达的友军加入当前战斗)、改姿态(下一天起生效)。信使行程 3–4 天、战斗可达 5 天,所以近处的命令来得及打断战斗,太远的赶不上,这是战略失败而非规则漏洞。

**(c) 增援与多线:** 同一场战斗可合并多支友军 regiment(每方上限 `battle_max_units`);敌后队也可能在第 2 天加入——别把兵力全压在一座城。

### 4.5 战后

写一条战报 missive(`MissiveLog`):数字与结果由引擎给,叙述以 `templates.csv` 的 `battle_*` 模板为主,重大战斗可经 `Voicer` 润色但不得改数字(inv.1、inv.9)。每笔状态变化带原因串,如 `morale −15: lost the field at <place>`(inv.4)。

## 5. 围城与劫掠

### 5.1 围城(完整过程)

`main` 停在玩家持有的守军城镇外,进入 SIEGE,每天结算:

```
siege_progress += siege_rate × 敌军 power / (敌军 power + 守军 power × 城防倍率)
```

`siege_rate` 是 `balance.csv` 键。过程中三类事件都写战报 missive:
- **强攻**:每隔 `siege_assault_days` 天敌军强攻一次,走 §4 的战斗(守军有城防加成);攻方受挫则 `siege_progress` 减少,守方溃败则一次加满。
- **断粮**:守军吃城镇存粮(`TownStores`),敌军吃自己的口粮;哪边先断,哪边士气先跌;城里断粮则 `siege_progress` 加速。
- **解围**:玩家增援抵达后按 §4 加入战斗;敌军战败或撤退,围城中止。

`siege_progress` 达 1000 或守军被打光 → 城破。

### 5.2 夺城(只换主人)

城破时只在**庄园层**移交:城镇自身的庄园与同省内 `siege_capture_radius_km` 以内的周边庄园,经 `MapManors.set_owner` 归敌方家族,**必须带原因串**;**不**经 `MapOwnership.set_owner` 移交省份(省界、首都、他处城镇不动)。敌 host 转 HOLD,停在城中;它撤走或被击退时,这些庄园以"liberated"为由还给原家族。夺城后的治安、占领区行政、被占省份的经济变化**不做**。

### 5.3 劫掠与战利品

`raider` 占领无防庄园期间,每天按 `raid_plunder_permille` 抽走其月产出(取 `ManorEconomy.line_of` 的整数),计入 host 的 `plunder`,并产生"劫掠"危险区(`hazard_kinds.csv` 增一行:损失补给、拖慢行军、士气;玩家路过也受影响)。击败袭击军后,`battle_spoils_permille × plunder` 进国库 `strategic`(带原因),这是主动出击的奖励回路。

## 6. 战败后果(不 Game Over)

- **丢城**:§5.2。
- **国库**:一笔带原因的扣款,按 `battle_defeat_treasury_permille`。
- **民心**:全国扣一笔,键 `battle_defeat_morale`,原因串如 `−8: lost <town> to the raiders`。
- **议会反应**:走已有机制,各席位按 ideology / 个性对"丢城"产生 opinion 变化,每笔带原因;**不新建议会系统**。
- **事件**:丢城触发一个固定散文的章节事件(沿用 `chapter_events` 链,文字不由模型生成)。
- 玩家日后夺回城镇:恢复所有权并发 missive,上述扣除不退还。

## 7. 数据与代码落点

**新 CSV:** `data/battle_outcomes.csv`、`data/battle_stances.csv`、`data/ai_doctrines.csv`、`data/maps/<id>/military/raid_hosts.csv`;`hazard_kinds.csv` 加"劫掠"行;`templates.csv` 加 `battle_*`。
**新 `balance.csv` 键:** `battle_contact_km`、`battle_max_rounds`、`battle_max_units`、`battle_variance_permille`、`battle_spoils_permille`、`battle_defeat_treasury_permille`、`battle_defeat_morale`、`ai_think_days`、`ai_sight_km`、`ai_target_reach_km`、`ai_target_overlap_permille`、`ai_retreat_supply_days`、`siege_rate`、`siege_assault_days`、`raid_appear_day`、`raid_rumour_lead_days`、`raid_plunder_permille`。

**新引擎类**(`scripts/engine/`,均 `RefCounted`):
- `BattleSystem`:接触检测、一轮结算、结果应用、增援合并、战中命令生效。它取代 `ArmySystem.battle_odds` 的"占位"注释,公式本身保留。
- `EnemyAi`:状态机、打分、决策节奏、目标去重。
- `SiegeSystem`:围城进度、强攻、断粮、城破。

**挂接点:** `TickEngine.advance_day` 的顺序为 march → 信使抵达 → `EnemyAi.think`(整除 `ai_think_days` 的日子)→ `BattleSystem.settle_day` → `SiegeSystem.settle_day` → 战败后果。`GameState` 增 `ai_hosts` 与 `battles`,存读走 `_encode_values` / `_decode_values`。
**指南:** 落地时把规则写进 `scripts/engine/guide/battle_and_ai.md`,并在 `scripts/engine/CLAUDE.md` 的 Topic guides 登记(同时遵守 `test_claude_md_size.gd` 的上限)。

## 8. 测试(先写手算值)

- `battle_odds`:给定双方 power,手算 `A/(A+D)`,含姿态与高度修正、多 regiment 合并。
- 抽签:同 (seed, 双方代码, 天, 轮) 同结果;**调用前后 `GameState.rng` 状态不变**。
- 结果档:每档的损失、伤兵、士气;总数守恒(阵亡 + 伤兵 + 完好 = 原头数)。
- 战中命令:信使第 N 天抵达,第 N+1 天战斗按新命令执行;太远的命令不及。
- `EnemyAi`:同存档同输入同目标;富而弱的目标得分高于强而富的;多 host 不扑同一目标;断粮 / 低士气 → RETREAT;`ai_think_days` 节奏;`reserve` 跟随主力。
- 围城:`siege_progress` 逐日累加手算;强攻胜败对进度的影响;断粮加速;城破时 `set_owner` 带原因。
- 战败后果:国库扣数、民心扣数、议会 opinion 变化都带原因串。
- 劫掠与战利品:`plunder` 手算;战利品入 `strategic` 带原因。
- 存档往返:`ai_hosts` 与 `battles` 保存读取后行为一致(`SuiteData.campaign`)。
- `test_engine_isolation.gd`:新类不引用 `ui` / `llm` / `Game`。

## 9. 分期

- **P1 战斗核心**:`BattleSystem`、姿态、战中命令、增援、战报;用测试里手工摆的两支军验证。
- **P2 敌军 AI**:`EnemyAi`、越境事件、预警传闻、多 host 协调、撤退;无头跑通"敌军来、玩家守"。
- **P3 围城、劫掠、战败后果**:`SiegeSystem`、劫掠危险区、战利品、议会反应、丢城事件。
- **P4 呈现**:战斗标记、敌军幽灵棋子、战报 UI —— 需本地会话与 `visual-review`;云端会话只做 P1–P3。

## 10. 仍待 owner 确认的 Default

战斗最多 5 轮;默认编成 3 支;`ai_think_days` 为 3;`engage_odds` 为 0.45;`reserve` 约第 18 天越境;强攻间隔与影响幅度;战败时国库与民心的扣法;夺城后敌军留 HOLD。以上全是 CSV / `balance.csv` 数值,实现后可调,不影响结构。
