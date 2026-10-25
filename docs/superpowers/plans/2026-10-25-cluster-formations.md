# 多单位集群阵型 Implementation Plan

> **DRAFT / CF02-rollout-plan：待人类明确批准。** 下文原批准任务及 acceptance 保留有效；新增“提议的有限分阶段接入”仅供审阅，不是执行或登记授权。原 CF02 仍 incomplete / boundary-blocked，唯一实施者 `01a17401-321b-71a2-9908-32857c8ef4f8` 不变；不能以被动基础宣告原 CF02 完成。即使本草案 CI 与文档 Review 通过，也必须等待人类明确批准 staging、验收和 ownership 处理后才能合并。证据、逐步文件和待决项见 `docs/reviews/cluster-formations/cf02-rollout-boundary.md`。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 仓库固定实施／唯一 Review 两人规则优先；不得采用另加实现、架构或嵌套 reviewer 的执行方式。

**Goal:** 在唯一 3D 地图实现固定十兵人占地、全过程身体避碰、真实传令的多 unit 集群及八种条件式接敌预案。

**Architecture:** 复用人员账、整数米代表组、DayResolution 子步、现有军令／信使和 BattleStrength 来源账。先把单位显示模板与身体运动从旧内部阵型解耦，再建立跨战场的集群记录、部署和已送达行为；界面只提交命令和读取获准投影。空间检查统一收口，任何自动预案不能增加第二份移动预算或绕过军法。

**Tech Stack:** Godot 4.7 / typed GDScript / GUT / CSV / JSON 单文件保存；不新增依赖、物理时钟、LLM 战术、疲劳度或地图。

**Spec:** `docs/superpowers/specs/2026-10-25-cluster-formations-design.md`（PR #181，merge `b1a6402cdc374c79b0de5ba292bcc74bf4f9f324`）。本计划基于该已合并 HEAD；计划不是产品实现或启动授权。

## Global Constraints

- 满员 unit 显示 **10 个兵人**；减员减少兵人数，**不缩小该 unit 的部署范围**。
- 取消 unit 内部战术阵型；内部排列只用于显示人数。
- 任何兵人不能身体重叠或穿体，移动全过程也不例外。
- 友军 unit 的部署范围可以交叠；兵人通过局部让行、侧移、必要的短暂等待完成穿插，再归位。
- 鼠标左键框选至少 **3 个军事单位**时显示集群阵型选项。
- 有阵型先就近集结，再以**最慢成员当前有效速度**共同移动；局部包抄、接应、补位按自身有效速度。
- 没有疲劳度。敌方受相同空间、通信、兵种资格和准备约束。
- `ceil(可战人数 / 100)`，0→0；末组保留精确人数；人员、伤兵、俘虏、成本不重复结算。
- 军法、停战、受保护撤离及已送达追击边界优先于自动预案。设计值进 `data/`；静态外观通过 gdai 编辑器保存。
- 每步独立 `codex/` 分支、工作树、PR 和固定实施／Review；Review 只审查、复审、合并。视觉 critic 由该唯一 Review 承担，不增加第三人。

## Review Focus

1. 高速相向、交叉和转身即使子步端点不相交，途中仍可能穿体：CF03/04 检查完整扫掠及渲染轨迹。
2. 子步保存、旧冻结事务与损坏／重叠旧档：CF02/07/25 验证不重复移动、费用和人员，不静默修位置。
3. 预览时改动隐藏敌人或敌方精确人员：CF08/23 的已知信息投影必须完全不变。
4. 迟到旧令、部分脱队、国王离开及跨集群重发：CF09/10/13 必须维持单归属、旧任务延续和单次扣费。
5. 必需单位损失、窄口与增援受袭：CF11/14–21 验证局部失效、合法自卫、有限失败和无隔空收益。

---

## 现有接口、替换范围与启动条件

调查 HEAD 为上述 merge；执行每步前只重查其调用者及前置 PR 差异，不重新设计。

- `BattleGroups.counts(n: int, size: int) -> Array[int]` 已支持 1000→10。`refresh` 保存 `battle.groups[unit] = [{slot,count,role,x_m,y_m,path_m?}]`，`group_next_slot` 单调；当前 `layout/deployment` 仍依赖 `BattleFormation.slots`，`engaged_permille` 对未接敌者仍给 `battle_reserve_permille`。
- `BattleFormation.request/refusal/effects/slots` 和 `data/battle/formations.csv` 仍是 line/wedge/diamond/double_rank。调用方包括 `BattleSystem`、`BattleRules`、`BattleTaskSystem`、`CourierSystem`、`MilitaryBootstrap`、`WarFolio`、`Map3DFormation`、`WarFormationDots`。CF07 逐项移除内部战术语义，不能只换按钮。
- `ArmySystem.day_walk_budget(repo,state,code)`、`day_march_at(...)`、`march_day_saved(repo,state,pace_divisor,substep_index,saved_entries,day_budgets)` 已有预算和恢复路径。`TickEngine._resolve_phase` 的 `MARCH_ORDERS_AND_ROUTE_SETUP` 冻结每日记录；`_resolve_battles` 先移动再接触。新增进度必须进入这个事务，不开另一时钟。
- `BattleTaskSystem.issue_task/deliver_task/current/combat_action` 已提供任务、序列和收令；`BattleOrders.issue/deliver` 处理全军战场令；`CourierSystem` 现有 battle/task 送达分支可复用物理载体。
- `KingSystem.can_command` 当前只查距离，不等于本设计的“实际随阵”。新增集群判断不可全局削弱其他合法本地命令。
- `GameState.SAVE_VERSION = 7`、`MIN_SAVE_VERSION = 6`，`to_dict/from_dict`、`MilitaryBootstrap.migrate`、`MilitaryReorganization.reconcile`、`Game.load_campaign` 是保存／发布边界；`SaveLoad.state_hash` 可复用。新增结构显式版本化，不能提高最低版本来丢掉兼容验收。
- `Map3DView` 实际位于 `scripts/map3d/map3d_view.gd`，复用 `selected_armies/select_box/apply_battle_snapshot`；`Map3DInput` 当前 Shift+左拖框选、普通左拖平移。CF22 明确替换普通左拖的军事框选语义，并保留可用的平移手势和路线编辑优先级。
- `Map3DFormation.fit_tier` 近景已经按可战人数取整；`army_formations.csv`、`tier_of`、WAR ROOM 仍有 3/6/9 档，不可据此宣称十人合同完成。

**p4.N1 替代接入门禁：**PR #178 不再是 CF 的“合并且验收”前置。原固定 pair 的 Audit 2 只通过迁移保全，不能证明运行、视觉或性能通过。必要基础要求迁入已有 CF02–06，精确接收文件、失败继承和 source/commit/patch/hash 索引见 `docs/reviews/cluster-formations/n1-migration.md`。CF02 从当时 `origin/main` 按 #181/#182 实现，不套用 #178 未合并树、整包 patch 或旧四阵型 allocator；后续依次等待 CF02→03→04a→04b→04c→05→06 的当前 HEAD CI 与各自适用验收通过并合并，CF07 才退役旧语义。每步必须证明自己接收的基础要求，保全文档不能替代 runtime 门禁。

#178 的原实施／唯一 Review、工作树、分支、失败证据仍保留；其产品开发、测试及整包合并仍暂停。只有原 controller 与原 pair 在实际替代依赖落地并明确 close-ready 后处理 superseded、关闭及 ownership release；本计划不宣称这些操作完成。CF01/CF08 已有 owner 继续，不重派、不唤醒旧产品 owner；其他步骤仍须由唯一派工方核对共享 registry 的活跃文件归属、解除冲突及前置验收后登记，不能借文档改门禁抢占尚未释放的文件。

**旧规范冲突登记：**本 spec 优先于 `2026-10-16-battle-system-design.md` 的 unit 四阵型、部署缩放与旧显示约定，以及 `2026-10-17-unit-behavior-and-battlefield-design.md` §6/§16/§18 的 50 人分档、按队内 front/reserve 推导战术、无接触比例近战。CF07 在旧规范相应节加简短替代指针，保留未冲突的 120% 步跑、130% 消耗、人员／军法／事务规则；不重写历史设计。当前规则只在实际落地的 guide 更新。

## 文件和契约边界

所有下列新增类为 `RefCounted`，除特别注明均为 `static func`，签名中 `repo: DataRepository, state: GameState` 不省略于代码。新脚本及测试的 `.gd.uid` 随其文件归同一步；新 CSV 必须进入 `data/tables.csv`，loader 和数据测试在引入该表的同一步。不创建空骨架 PR。

- `unit_bodies.gd`：身体行、固定模板、身体包络及单一存储访问；`body_motion.gd`：无场景依赖的扫掠和让行。复用已有代表组身份，不再另造人数账。
- `battle_clusters.gd`：集群记录与资格；`cluster_orders.gd`：付费、版本、成员送达；`cluster_movement.gd`：阶段和预算；`cluster_tactics.gd`：预案决策；`cluster_support.gd`：条件事实。均在 `scripts/engine/`，按任务引入实际功能。
- `ClusterLayout` 是唯一集群布局查询；`BattleFormation` 在 CF07a 中停止旧战术收益、CF07b 完成消费者迁移后删除无调用的旧接口，不另造无消费者门面。`BattleGroups` 继续代表精确人员及实际接触。
- `data/army/unit_footprints.csv`：`arm,body_radius_m,deploy_width_m,deploy_depth_m,slot_pitch_m,rank_pitch_m`，均正整数；十空位的包络须落在固定范围内并留合法通道。圆包络必须保守包含骑马和器械旋转的身体，不含伸出武器的攻击触点。
- `data/battle/cluster_formations.csv`：`formation,label,recipe,behavior`。八 code 固定为 `steady_line,archer_infantry,double_envelopment,cavalry_charge,depth_defence,strong_wing,lure_counter,artillery_hold`。`recipe` 是 OR 分隔的整数下界组合（如 `infantry:1+cavalry:2`；骑兵突击 `cavalry:3|cavalry:2+infantry:1`）；都另验总数≥3，不按人员数或模型数算 unit。
- `data/battle/cluster_slots.csv`：`formation,arm,role,lateral,depth,priority`，整数逻辑格；格距由固定范围及通道推导，额外单位按同兵种职责、邻接预备稳定填充。强翼以镜像表达，不另造左右阵型。
- `data/battle/cluster_effects.csv`：`formation,condition,channel,amount_key,source,reason`；具体系数在 CF24 才完成平衡，不沿用旧永久光环。准备、邻接、停滞、路线重算等值为 `battle/balance.csv` 的 `cluster_*` 键；不把未测数值写死在计划中。

### 共用验证与每个 PR 的结束动作

每个任务下的红灯断言是新增 GUT 测试必须锁定的合同，测试使用 `SuiteData.repo()/campaign`、现有 `tests/engine/personnel_helpers.gd` 和 pack 派生位置。不得复用关闭 clearance 的抽象 fixture 证明避碰。红灯必须是行为／缺接口失败，不能语法错误；再最小实现、绿灯。测试命令 `./run_tests.sh --test PATH`，先暂存新增测试或显式路径；运行时外层统一使用共享锁：

```sh
/Users/samuelzhang/game_design-wt/godot_lock.sh ./run_tests.sh --test tests/engine/test_cluster_state.gd
```

锁外包超时：`godot_lock.sh python3 tools/run_with_timeout.py 300 GODOT ...`；禁止同时启动另一重型 Godot，不结束他人编辑器。共享锁不可用时先解决调度，不能改用私有锁并发。每步最终代码上运行所属测试和所列既有回归，再按 selector 跑必要功能类别一次，保留命令、输入 hash、日志、HEAD；不例行全量 GUT。公式用手算，待值的生产平衡不用“观测值回填期望”冒充手算。

各任务最后的“提交／PR”统一指：`git diff --check`；`git add` 仅该步拥有路径；`git commit -m "<任务给定信息>"`；push 自己 `codex/cluster-cfNN-*` 分支并创建 main PR。登记唯一实施／Review、工作树、依赖已合并证据、确切文件、验证 hash、未提交文件／进程／风险；交唯一 Review 后等待。CI 当前 HEAD 必需 `harness-checks`、`gut-tests` 及选中矩阵均成功才可合并。不是“测试写好就可启动后续”。

## Task CF01：实测模型身体与十空位范围

**依赖：**设计 #181；可与无重叠文件的 CF08 并行。**拥有：**新建 `tools/units3d/measure_unit_bodies.gd`、`tests/map3d/test_unit_body_measurement.gd`、`docs/reviews/cluster-formations/measurements.md`。只测量，不修改模型、N1 工具或生产 CSV。

**Interfaces:** 新 `measure(scene: PackedScene, art: Dictionary) -> Dictionary` 返回 `{model_hash, scale_inputs, radius_m, sampled_clips, deploy_min_width_m, deploy_min_depth_m}`。调用现有 `Map3DUnits.model_size/stand_extent/scale_for` 和 `GameArt.ARMY_MODELS`，按世界米校准；不得把源模型本地单位直接当仿真米。

- [ ] 红灯 `test_body_measurement`: 合成两倍缩放模型的保守半径是原来的两倍；骑兵含坐骑；炮兵暂用用户批准的步兵 placeholder，报告明确该输入和限制，换真实火炮后重测含器械包络；旋转及行走/待命采样均被包络包含；缺模型明确失败。
- [ ] 运行 `test_unit_body_measurement.gd` 看到上述缺接口失败，再实现测量导出；记录输入 GLB/scene/art/scale hash、十空位与通路计算、未覆盖动作。
- [ ] 绿灯并真实窗口按 visual-review 比较原尺度及两种间距；唯一 Review 独立批评全图/裁图。输出各兵种可配置尺寸及性能测量方法；尚不声称动画全阶段已验收。
- [ ] 提交／PR：`docs: measure unit body envelopes for clusters`。模型或缩放输入变化使本证据失效。

## Task CF02：固定占地、持久身体与安全迁移

**依赖：**CF01 已合并且实测验收通过；N1 替代接入门禁及活跃文件归属冲突已解除（见迁移索引），不依赖 #178 合并。**拥有：**新 `scripts/engine/unit_bodies.gd`、`data/army/unit_footprints.csv`、`tests/engine/test_unit_bodies.gd`；修改 `battle_groups.gd`、`battle_system.gd`、`battle_merge.gd`、`game_state.gd`、`military_reorganization.gd`、`data_repository.gd`、`data/tables.csv`、`scripts/ui/game.gd`、`guide/battle_groups.md`。新增 guide 放 `scripts/engine/guide/cluster_formations.md`，由 engine `CLAUDE.md` 索引。

**Interfaces:** `UnitBodies.rows(repo,state,unit: String) -> Array`；`footprint(repo,unit: String,state) -> Vector2i` 返回固定宽深；`home_slots(repo,state,unit: String) -> Array[Vector2i]` 总是十空位；`migrate(repo,state) -> Dictionary` 返回 status/error/reason。

单一权威：在战斗中复用 `battle.groups[unit]`，非战斗放 unit entry 的 `body_groups`；进入/离开战斗原子转移，绝不保留两份可写身体。稳定 slot 不等于 home index，行保存 `home_slot`、整数路径及 facing。战斗 merge 仍复用原 rows。明确接入 `BattleSystem._start` 的入战、成员撤出/`_end`/`call_off` 的出战，以及 `BattleMerge` 的存活战场转移；必须在删除战场/成员前转出身体，不能等下一次 refresh 补救。`call_off` 现有可空 repo 路径转移保存行时不得依赖配置重新排位。兼容查询不凭空生成第二套位置。

- [ ] 红灯 `test_count_and_fixed_footprint`: 1000/901/900/1/0→10/10/9/1/0；准确 count 总和等于 fit；901→900 生还 slot/点不变，固定宽深不变，退役 slot 不重用。十空位来源为 CF01 正整数配置。
- [ ] 红灯 `test_transfer_and_load`: 非战斗→战斗→merge→正常结束/取消战场/单成员撤出 rows/人员守恒且只有一个存储，转移后再次JSON加载保持点/路径/slot；JSON 后等价；旧非重叠档原点保留；已重叠旧档 load 明确拒绝、原文件 hash 不变、当前运行 state 不发布。未完成旧事务保留冻结数据，在安全边界迁移；若恢复会产生非法重叠则明确拒绝恢复，不静默瞬移。
- [ ] 先跑新测试确认红灯；实现候选副本迁移、保存结构版本与 `Game.load_campaign` 发布前验证（map 回滚沿用现有路径）；无效／未来版本 fail closed。新集团字段后续加入，此步不生成集团。
- [ ] 绿灯；回归 `test_battle_groups.gd`、`test_group_size_migration.gd`、`test_living_cap_battle_migration.gd`、`test_battle_save.gd`。最终宽深取实测值，测试用明确小 fixture 手算其十空位包络。
- [ ] 提交／PR：`feat: preserve fixed unit footprints and physical rows`。

## Task CF03：全过程身体扫掠与确定性让行

**依赖：**CF02。**拥有：**新 `scripts/engine/body_motion.gd`、`tests/engine/test_body_motion.gd`；修改 `data/battle/balance.csv`（仅新运动键）、cluster guide。

**Interfaces:** `BodyMotion.plan(repo,state,intents: Array,abs_day: int,substep: int) -> Dictionary`，intent `{unit,slot,path_m,budget_m,hostile}`；返回 `{moves,blocked,reasons,cursor}`，moves 含完整整数折线路径和实际已用米数，纯查询不发布。`BodyMotion.commit(repo,state,plan: Dictionary) -> Dictionary` 原子验证并发布，重复同 cursor 惰性。

- [ ] 红灯 `test_swept_crossing`: 半径 fixture 10m，两中心最小距≥20m；A 从(-100,0)到(100,0)、B 反向或垂直交叉，不能交换端点穿越。扫掠圆/胶囊查相对运动，不只查终点；静止转身采用 CF01 保守旋转包络。
- [ ] 红灯 `test_yield_and_stall`: 友军部署矩形交叠而身体合法可通行；三队交叉稳定排序；对向窄道选定一批通过，另一批等待；无出口有限重算后报 blocked，不穿体、不无限互退；重排 intent 输入和 JSON 恢复结果相同。敌人不能得到友军穿插待遇。
- [ ] 先红灯；实现稳定 `(unit,slot)` 排序、保留通行优先权的 cursor、局部侧移／等待／回位；绕行实际长度≤budget，不从“预留”重复扣步跑消耗。
- [ ] 绿灯；新增 `test_invalid_plan_atomic`：负预算、非整数路径、重复身份拒绝，state/RNG 不变。提交／PR：`feat: plan swept body movement with stable yielding`。

## Task CF04a：普通行军事务接入身体轨迹

**依赖：**CF03。**拥有：**`army_system.gd`、`tick_engine.gd`、`day_resolution.gd`、新 `tests/engine/test_body_marches.gd`、regiments guide。

**Interfaces:** `UnitBodies.rows` 成为活跃军事身体查询；已有 `march_day_saved` 和普通/预测 march 签名保留；预测只在副本规划。Map 消费已提交路径及 cursor，以路径分段插值，不能在合法折线两端直线插值穿人。

- [ ] 红灯：非战斗友军对穿、三队路口、敌对拦截查扫掠；不得用固定部署框拒绝所有友军穿插。成员在同子步只移动一次，重复cursor和JSON恢复不重复移动。
- [ ] 先跑 `test_body_marches.gd` 红灯；统一既有路径入口调用 CF03，预算/补给仍由原 writer 提交，体行与 anchor 同事务发布；新游戏和敌方适用同规则。
- [ ] 绿灯及 `test_army_clearance.gd`、保存march事务回归；此步只接受已有效初始化身体的行军，尚不宣称所有生成/显示接入。
- [ ] 提交／PR：`feat: route marches through physical bodies`。

## Task CF04b：生成与停驻接入合法身体空位

**依赖：**CF04a。**拥有：**`army_ground.gd`、`army_split.gd`、`enemy_ai.gd`；新 `tests/engine/test_body_placement.gd`；regiments guide。**Interfaces:** 沿用已有spawn/camp入口，内部通过 `UnitBodies.home_slots` 和 `BodyMotion.plan/commit` 发布身体；没有第二份位置writer。

- [ ] 红灯：扎营/离营/新兵/敌方生成十空位合法；友军部署框可交叠；空间不足等待或带原因失败，不重叠硬塞、不静默传送；同输入/JSON保持人员及slot守恒。
- [ ] 跑 `test_body_placement.gd` 红灯，接入最小合法空位搜索，绿灯及 `test_army_ground.gd`、`test_army_seat.gd`、`test_enemy_spawn.gd`。
- [ ] 提交／PR：`feat: place new and camped bodies in lawful free space`。

## Task CF04c：身体折线路径的地图消费者

**依赖：**CF04b。**拥有：**`scripts/map3d/map3d_battle_groups.gd`、`map3d_layer_units.gd`、`map3d_formation.gd`；新 `tests/map3d/test_body_paths.gd`；map3d guide。**Interfaces:** 消费 `UnitBodies.rows` 和CF03已提交path/cursor，转世界坐标后按合法折线插值；仅获准显示对象进入路径查询。

- [ ] 红灯：L形避让中点落在折线而非对角捷径；0/1/9/10人身份稳定、非战斗与入战转移不闪跳；镜头/帧率不改变仿真，幽灵不读hidden路径。
- [ ] 跑 `test_body_paths.gd` 红灯，实现消费者，绿灯及 `test_map3d_units.gd`、`test_map3d_battle_groups.gd`；真实窗口近/远、暂停/1x/4x全程录制对穿/交叉/转弯，不能用端点合法代替画面无穿体。
- [ ] 提交／PR：`feat: render committed body detours without corner cutting`。CF04统一完成指a/b/c全部合并且视觉验收通过。

## Task CF05：战斗机动统一占位及敌军接触

**依赖：**CF04。**拥有：**`battle_groups.gd`、`battle_charge.gd`、`battle_task_system.gd`、`battle_merge.gd`、`battle_system.gd`；新 `tests/engine/test_body_battle_motion.gd`；battle_groups/charge/merge guides。

**Interfaces:** `BattleGroups.translate/follow_anchor` 保留外部入口但只能提交已扫掠计划；`BattleCharge.move`、`BattleTaskSystem.deploy_flank` 生成 intent 交 CF03；撤退/溃败同入口。`BattleSystem.discover_contacts` 和 BattleMerge 判定依据实际敌军接触，不依据友军部署框。

- [ ] 红灯：冲锋、包抄、部署、撤退路径途中不穿敌/友；有未占据缺口可绕行；敌军隔身体距离接战；友军框交叠不建战场/不合并。有效停战、受保护撤离仍阻攻击，不能据此当不存在的身体。
- [ ] 红灯：冲击失败不能从敌群体内滑出；same cursor 调两次不追加 runup/位移；合并保留 slot/path、任务和既有 bilateral parties。
- [ ] 先红后最小接入再绿；回归 `test_charge_runup.gd`、`test_battle_task_retreat.gd`、`test_battle_merge_warrants.gd`、`test_battle_terms_scope.gd`。
- [ ] 提交／PR：`feat: constrain battle manoeuvres by actual body contact`。

## Task CF06：接触人数伤害与实际直接射击

**依赖：**CF05。**拥有：**`battle_groups.gd`、`battle_ranged.gd`、`battle_system.gd`、`battle_strength.gd`、`data/battle/balance.csv`；新 `tests/engine/test_physical_damage.gd`；ranged/groups guides。

**Interfaces:** 新 `BattleGroups.melee_counts(repo,state,battle: Dictionary,unit: String,enemies: Array) -> Dictionary` 返回 `{engaged,fit,reason}`，从实际身体及合法距离判定，不按旧 front 标签；既有 `BattleRanged.counts/clear_shot` 改用实际包络遮挡。防御／组织和造成近战伤害的人员分开，不能把“contact factor=0”夹到最小乘数后仍隔空伤害。

- [ ] 红灯手算：fit=1000，实际投入100，近战输出基数只来自100；未接敌900贡献0近战；全未接敌输出0但仍可合法自卫/承伤。末组1人只算1人。
- [ ] 红灯：射程边界内含/外一米、朝向、地形遮挡、友军马/炮包络挡线；移动出射程停止，错列间隙可射；不新增曲射。接触目标受协议保护不得伤害。
- [ ] 先红灯后移除 reserve 伤害兜底，保留合法组织支持入口给 CF21；绿灯及 `test_group_contact_strength.gd`、`test_ranged_fire_geometry.gd`、`test_ranged_contact_merge.gd`、`test_battle_conservation.gd`。
- [ ] 提交／PR：`fix: limit damage to actual contact and direct fire`。

## Task CF07a：退役 unit 内战术收益与旧令

**依赖：**CF06。**拥有：**`battle_formation.gd`、`battle_groups.gd`、`battle_system.gd`、`battle_rules.gd`、`battle_task_system.gd`、`courier_system.gd`、`action_system.gd`、`military_bootstrap.gd`、`data/battle/formations.csv`、`data/realm/order_costs.csv`；相关现有 formation/parley 测试及新 `tests/engine/test_legacy_formation_retirement.gd`，两份旧设计冲突指针和 deployment/data guides。

**Interfaces:** `UnitBodies.home_slots` 替代队内 `BattleFormation.slots`；旧 `BATTLE_FORMATION` 与 task 的旧 `formation` 参数明确拒绝／旧在途回执“不再适用”。CF08 的 `ClusterLayout.options/layout` 为新集群查询，CF09及CF22直接消费；旧 effects 不再调用，不能保留默认 double_rank 光环。不要把单 unit 旧令解释成新 cluster。

- [ ] 红灯：四旧阵型字段不改变输出/身体模板；旧合法 primary task 仍有效；仅其退役 formation 子项留回执；已付钱不退扣、不二次结算；已送达旧收益消失但原点/人员不变。迟到旧 courier 惰性终止。
- [ ] 先红灯；逐个调用者改到显示模板/中性状态，旧门面暂以中性固定显示模板兼容消费者；删除无调用旧数据/成本行前检查在途保存兼容；迁移幂等且不降低 MIN_SAVE_VERSION。
- [ ] 绿灯；跑旧 formation/task/encounter/folio 消费者测试（将已被设计替代的断言显式换为新合同，不删人员/权限断言）、`test_battle_save.gd`；旧UI在CF07b前提交退役令只能收到明确拒绝。
- [ ] 提交／PR：`refactor: retire per-unit tactical effects and warrants`。

## Task CF07b：旧阵型显示与控件退役

**依赖：**CF07a。**拥有：**`war_folio.gd`、`scripts/ui/war_formation_dots.gd`、`battle_encounter_panel.gd`、`scripts/map3d/map3d_formation.gd`、`battle_formation.gd`（删除中性兼容旧slots入口）、`data/army/army_formations.csv`、`scenes/panels/battle_encounter_panel.tscn`、现有map/folio/parley测试、新 `tests/ui/test_formation_retirement.gd`、ui/map guides。

- [ ] 红灯：旧四阵型控件不再发旧令；WAR ROOM/map用相同100人映射与固定home模板，10→9不缩部署范围；0活跃不画兵；舰队、ghost、原unit选择信号不退化。
- [ ] 跑 `test_formation_retirement.gd` 红灯；编辑器移除旧控件，消费者改用 `UnitBodies.home_slots`，确认无调用后删旧slots门面和过时tier行；绿灯及map/folio/parley消费者、editor-owned守卫。
- [ ] 真实窗口visual-review验证模板与控件改变，唯一Review批评；提交／PR：`refactor: retire internal formation controls and figure tiers`。CF07统一完成指a/b两PR均合并。

## Task CF08：八阵型资格及纯布局

**依赖：**#181；可先独立实现新 `cluster_layout.gd`，不改 N1 的 `BattleFormation`；CF09/22直接调用本步接口，不安排额外旧类门面接入。**拥有：**新 `scripts/engine/cluster_layout.gd`、两张 cluster_formations/cluster_slots CSV、`tests/engine/test_cluster_layout.gd`；`data_repository.gd`、`data/tables.csv`、`data/CLAUDE.md`。

**Interfaces:** `ClusterLayout.options(repo,units: Array) -> Array`（units 是获准投影 `{unit,arm,controllable,fit}`）；`layout(repo,formation: String,units: Array,origin: Vector2i,facing: int,strong_side: String) -> Dictionary` 返回 `{slots,roles,missing,blocked,reason}`。单位范围通过投影的 footprint 传入；全功能实际地形可达校验在 CF11，不假定格阵一定可放。

- [ ] 红灯：每阵型刚好满足/缺一/额外单位；骑兵突击两个 recipe 都成立；总数2失败；0 fit、不可控、king/courier不凑数。可选前排，拒绝项具体“缺1支骑兵”。
- [ ] 红灯：八种角色部署遵守 spec §6；余量同兵种/邻接 reserve；输入顺序不同输出相同；强翼左右镜像，同可达面积按稳定 side 规则；没有位置者不生成假伤害。
- [ ] 先红后 loader/纯布局实现再绿；`test_battle_data.gd`、`test_data_layout.gd`。本步只是已测试的规划查询，无 UI、无执行、无全军 buff。
- [ ] 提交／PR：`feat: describe eight cluster layouts and eligibility`。

## Task CF09：集群保存与成员版本命令

**依赖：**CF07、CF08。**拥有：**新 `battle_clusters.gd`、`cluster_orders.gd`、`tests/engine/test_cluster_state.gd`、`test_cluster_orders.gd`；`game_state.gd`、`action_system.gd`、`data/realm/order_costs.csv`、`action_signatures.csv`、cluster guide。

**Interfaces:** `BattleClusters.get(state,id: String) -> Dictionary`；`ClusterOrders.quote(repo,state,request: Dictionary) -> Dictionary`、`issue(repo,state,request: Dictionary) -> Dictionary`、`deliver(repo,state,request_id: String,unit: String) -> Dictionary`。typed actions `CLUSTER_SET` / `CLUSTER_CANCEL` 入口 `Game.try_execute`，canonical request `{request_id,members,formation,dest_x_m,dest_y_m,facing_deg,strong_side,mode,retain_cluster}`；mode 为 create/reform/reinforce/independent，取消仅 id/cluster。

保存 `state.battle_clusters`：稳定 id、选中冻结 members、receiver_unit、单调 version、formation/target/facing/strong_side、roles/home slots、phase/preparation/blocked_reason；unit 保存当前 cluster_id/latest_cluster_version，pending 令不改执行归属。保存独立 command receipt；旧档缺字段=空，不生成集群。

- [ ] 红灯：issue 只冻结成员，不改旧任务；deliver 单成员才替换，重复 request 原结果/费用一次，冲突 ID 拒绝；旧版本迟到不覆盖新版本；每 unit 唯一归属；旧档空、JSON 全字段等价、返回副本不可改 ledger。
- [ ] 先红灯再实现原子校验/费用/权限；复用 OrderCosts 和保留 reward gold 校验；初令 filing 按既有成员任务口径各收一次，转给接令单位的改阵只一次 filing；同一载体不重复收 courier fee。报价明确逐项金额，改变编组不得免费隐含替换旧令。
- [ ] 绿灯；`test_battle_task_dispatch.gd`、`test_battle_save.gd`、`test_battle_orders.gd`，新成本行必须通过 OrderCosts 守卫。提交／PR：`feat: save cluster membership and versioned warrants`。

## Task CF10：真实信使、接令单位与随阵国王

**依赖：**CF09。**拥有：**`cluster_orders.gd`、`courier_system.gd`、`king_system.gd`、`data/intel/courier_kinds.csv`（仅现有载体确需类型时）、`tests/engine/test_cluster_delivery.gd`、cluster guide。

**Interfaces:** 新 `KingSystem.can_command_cluster(repo,state,cluster_id: String,unit: String) -> bool`；新 `ClusterOrders.relay(repo,state,cluster_id: String,version: int) -> Dictionary`，复用实际路线和现有本地传令半径，不新建瞬时广播总线。

- [ ] 红灯：初令分成员到达，未到继续旧令；改阵先到真实 receiver；失联成员仍走物理传令；递送重新核验 realm/control/fit/资格/协议，失效留原因。多成员共骑复用已有 co-carriage，费用报价一致。
- [ ] 红灯：国王实际 follow/部署且在阵中才本地即时；仅距离接近、镜头观察、赶来均不算。国王即时不免集结/转向/炮准备，远处断联仍未收到；国王移动不让既有 courier 瞬达；丢失/过期令不二扣。
- [ ] 先红后最小接入再绿；`test_courier_orders.gd`、`test_courier_dispatch.gd` 和 `test_king_system.gd`；JSON 中途保存对照。提交／PR：`feat: deliver cluster orders through actual command paths`。

## Task CF11：集结、重组、受袭及失败状态机

**依赖：**CF10。**拥有：**新 `cluster_movement.gd`、`tests/engine/test_cluster_phases.gd`；`tick_engine.gd`、`day_resolution.gd`、`battle_clusters.gd`、`data/battle/balance.csv`、cluster guide。

**Interfaces:** `ClusterMovement.prepare_substep(repo,state,tx: Dictionary) -> Array` 只给 intent，不额外移动；`settle_substep(repo,state,tx: Dictionary,moves: Dictionary) -> void` 只在已提交结果推进。phase 固定 `pending,assembling,formed,engaging,recovering,invalid,failed`，保存 cursor、stall budget 和因果原因。

- [ ] 红灯：就近可达且十空位/通道足够才集结；朝向/必要准备未完成不能 formed；地形阻塞显示阵位/原因，不压缩、不换阵、不定时传送。预览用已知地形；执行 revalidate 可发现新阻塞但不事先泄漏。
- [ ] 红灯：必要成员被牵制时 blocked；受袭可自卫/伤亡/溃败；只移动重组者暴露，保持旧线者保留真实支持；暴露原因只算一次。stall 阈值后 failed 且不自动重试；全部失能立即失败；取消未送达仍执行旧令。
- [ ] 先红灯后实现；绿灯以及 encounter 暂停恢复/`tests/ui/test_game_battle_clock.gd`。手算准备累计：fixture 阈值3，已达位累计2不能成阵，第3个有效子步才成阵，重复 cursor 不累计。
- [ ] 提交／PR：`feat: assemble clusters from physical progress and failures`。

## Task CF12：共同最慢速度与无阵型到达

**依赖：**CF11。**拥有：**`cluster_movement.gd`、`army_system.gd`、`unit_gait.gd`、`tick_engine.gd`、`tests/engine/test_cluster_speed.gd`、cluster/regiments guides。

**Interfaces:** `ClusterMovement.budget(repo,state,cluster_id: String,unit: String,tx: Dictionary) -> int` 返回当前子步唯一预算上限；已成阵共同移动取成员当前有效预算最小值，局部机动 mode 用自己预算。复用整数余数累积，日/子步消费一次。

- [ ] 红灯手算 fixture：A/B/C 当前有效日预算100/80/60m，10子步共同每步≤6m，日总≤60；C局部地形变为40后立即取40对应剩余预算，不回溯赠送。任一必需成员停顿共同等待/接敌；步跑选项不能超过上限或重复130%消耗；不新乘士气/军纪速度。
- [ ] 红灯：无阵型从原地分别走100/80/60，无预先集结；到达次序填合法空位，同子步按unit ID；没有协同。骑兵出阵包抄按自身速度，返回共同 mode 再限速，不能删慢成员提速。
- [ ] 先红后预算接入再绿；`test_unit_gait_march.gd`、`test_march_blocked_runs.gd`、相关保存子步测试。提交／PR：`feat: share slowest cluster pace without extra movement`。

## Task CF13：增援、部分选取及跨集群切换

**依赖：**CF12。**拥有：**`battle_clusters.gd`、`cluster_orders.gd`、`cluster_movement.gd`、`tests/engine/test_cluster_membership.gd`、cluster guide。

**Interfaces:** `BattleClusters.preview_membership(repo,state,request: Dictionary) -> Dictionary` 纯查询；成员实际转移仍只经 CF09 `deliver`。reinforce 保留老成员阵位/任务，仅新成员分配临近同类或职责位。

- [ ] 红灯：选中半群/预览无状态变化；确认 independent/reform 后按实际收令离开旧群；跨群未指定 retain 或明确新阵型拒绝。旧/新令交叉到达、重发、取消皆无双重归属或双次行动。
- [ ] 红灯：增援不让全军重集结/全体受罚；新成员未实际入位无收益；非法玩家位置明确拒绝；必需兵种失去或unit数<3保留记录并 invalid，停专属协同，不因损失一个代表兵人立刻散阵；恢复成员仍须准备。
- [ ] 先红后实现再绿；CF09/10/11 全部新测试及 JSON retry。提交／PR：`feat: reinforce and split clusters on received orders`。

## 自动行为共用接口与顺序

CF14 引入 `ClusterTactics.intents(repo,state,cluster: Dictionary,known: Dictionary,tx: Dictionary) -> Array`，只读己方合法知识，返回 `{unit,role,mode,target_unit,path_m,reason}` 给 CF11/CF03；不直接写位置、不偷偷替换玩家任务。各阵型各有私有 `_steady_line/_archer_infantry/...` handler 同签名，后续一步只加自己的 handler/dispatch 分支和专属测试。

这些步骤共享 `cluster_tactics.gd`，因此 CF14→15→16→17→18→19→20→21 串行，每步独立 PR；不要为并行而造八个插件系统。每步继承“正常/受阻/必需单位失去”三例、敌我对称和军法/追击边界检查。收益暂只输出成立事实，由 CF21 的统一支持接口和 CF24 平衡定量。

## Task CF14：横线稳进及通用合法预案入口

**依赖：**CF13。**拥有：**新 `cluster_tactics.gd`、`tests/engine/test_cluster_steady_line.gd`；`cluster_movement.gd`、`battle_task_system.gd`、cluster guide。

- [ ] 红灯 `test_line_support`: 2步兵+第3合法unit，前沿协调推进、远程留间隙、骑兵护侧；窄地必要通道阻塞不成阵；必需步兵失去标invalid。横线不凭选择按钮提高全军伤害。
- [ ] 红灯共用 `test_plan_authority`: 未送达不自动行动、守区不越界、停战/受保护撤离不攻、无授权不追逃敌；改变隐藏敌真值不改变决策，敌方使用同接口。
- [ ] 运行红灯，最小实现上述入口并通过已有收到 task 的执行/权限路径；绿灯及 `test_battle_task_combat.gd`、`test_battle_task_retreat.gd`。
- [ ] 提交／PR：`feat: coordinate steady line contact plans`。

## Task CF15：弓步协同

**依赖：**CF14。**拥有：**`cluster_tactics.gd`、新 `tests/engine/test_cluster_archer_infantry.gd`、cluster guide。接口：`_archer_infantry`。

- [ ] 红灯：1步兵+1弓兵+第3unit；射程内合法射击，敌近步兵真实截击，射手按接近条件退到保护位；射界堵塞停火/侧移；无退路不穿兵；失步兵停止保护收益、合法独立射击仍保留。
- [ ] 跑红灯，实现真实路径接应（CF03预算），绿灯及 CF06 直接射击回归。
- [ ] 提交／PR：`feat: coordinate archers behind actual infantry protection`。

## Task CF16：两翼包抄

**依赖：**CF15。**拥有：**`cluster_tactics.gd`、`battle_task_system.gd`（复用 flank route 接口）、新 `tests/engine/test_cluster_double_envelopment.gd`、cluster guide。接口：`_double_envelopment`。

- [ ] 红灯：1步兵+2骑兵，中路牵制两翼各走真实合法侧路；到侧后接触才报该翼压力；一翼封堵该翼等待/自卫，另一翼可执行合法任务但不报双翼合围；失去必要骑兵即invalid。
- [ ] 跑红灯，实现复用实际 flank 路径和局部自身速度；绿灯及 `test_flank_destination.gd`、`test_target_tracking.gd`。
- [ ] 提交／PR：`feat: execute two wings through reachable flank routes`。

## Task CF17：骑兵突击

**依赖：**CF16。**拥有：**`cluster_tactics.gd`、`battle_charge.gd`、新 `tests/engine/test_cluster_cavalry_charge.gd`、charge/cluster guides。接口：`_cavalry_charge`。

- [ ] 红灯：3骑兵或2骑兵+1步兵，梯次真实助跑，速度/距离/方向达标才impact；成功步兵接防，失败合法脱离整队；贴脸无助跑无收益；障碍不穿、无脱离路径不滑出；失去最低组合停专属协同。
- [ ] 跑红灯，实现复用 BattleCharge runup/consume，已有 charge source只一份；绿灯及现有 runup/disengagement/save 测试。
- [ ] 提交／PR：`feat: coordinate mounted impact and lawful regrouping`。

## Task CF18：纵深守御

**依赖：**CF17。**拥有：**`cluster_tactics.gd`、新 `tests/engine/test_cluster_depth_defence.gd`、cluster guide。接口：`_depth_defence`。

- [ ] 红灯：2步兵+弓或炮，前沿/预备有别，实际经通道接替后局部防线恢复；后排未接敌近战输出0；堵路无接替收益，射界阻塞不射；失必要步兵失效；不越指定防区追敌。
- [ ] 跑红灯、实现、绿灯及 CF06 伤害回归。
- [ ] 提交／PR：`feat: rotate real reserves inside defensive depth`。

## Task CF19：斜线强翼

**依赖：**CF18。**拥有：**`cluster_tactics.gd`、新 `tests/engine/test_cluster_strong_wing.gd`、cluster guide。接口：`_strong_wing`。

- [ ] 红灯：3步兵，指定左右/默认可达大侧，面积同值稳定；强翼先接战弱翼延迟，真实突破才转卷击；弱翼先受袭可自卫，强翼久阻不伪造突破；失步兵资格invalid，转向扫掠和暴露成立。
- [ ] 跑红灯、实现、绿灯及 CF03 旋转/CF11 暴露回归。
- [ ] 提交／PR：`feat: stagger contact around the selected strong wing`。

## Task CF20：诱进反击

**依赖：**CF19。**拥有：**`cluster_tactics.gd`、新 `tests/engine/test_cluster_lure_counter.gd`、cluster guide。接口：`_lure_counter`。

- [ ] 红灯：步弓骑各1，弓兵射击后沿留出通道退接应线，敌实际追且步兵接住后才侧击；敌不追按有效射程射击/待命不无限后退；堵路/被追上可伤亡/真溃败，失必需成员停协同。
- [ ] 跑红灯、实现、绿灯；断言敌方没有被写入“强制追击”任务，JSON 中途回放相同。
- [ ] 提交／PR：`feat: counter only after a real pursuit into the relief line`。

## Task CF21a：炮兵据守

**依赖：**CF20。**拥有：**`cluster_tactics.gd`、新 `tests/engine/test_cluster_artillery_hold.gd`、cluster guide。**Interfaces:** `_artillery_hold` 沿用统一intents签名。

- [ ] 红灯：2步兵+1炮，实际展开/护卫到位/射界清楚才火力事实；挡线停火/调整，不穿友军；敌不进射程留守，不拆炮追敌，不生成栅栏/城墙；失炮资格invalid。
- [ ] 跑新测试红灯，实现并绿灯；CF06 ranged回归及JSON中途恢复。
- [ ] 提交／PR：`feat: hold artillery behind real protection and clear fire lanes`。

## Task CF21b：统一条件支持与暴露来源

**依赖：**CF21a。**拥有：**新 `cluster_support.gd`、`tests/engine/test_cluster_support.gd`；`battle_system.gd`、`battle_strength.gd`、`battle_presentation.gd`、新cluster_effects CSV及 `data_repository.gd`/`data/tables.csv`、cluster guide。**Interfaces:** `ClusterSupport.facts(repo,state,cluster_id: String,unit: String) -> Array`；`factors(repo,state,unit: String) -> Array[Dictionary]`。

- [ ] 红灯手算来源：fixture base100，两个同category偏差+100/+50→115，仅一次截断；重复source拒绝。侧击/冲锋复用既有source一次；邻接/拦截/双侧/接替/准备各有成立失效原因，无全军永久乘数。
- [ ] 红灯：重组暴露同源只计一次，旧线/新援分开；移走保护步兵、堵射界、失接触即撤对应事实；无阵型保留装备/训练/地形/自卫但无协同事实。
- [ ] 跑红灯、实现、绿灯；既有strength/presentation/charge/ranged和JSON恢复测试。生产量值只为可运行初值并标未平衡，CF24完成战果验收。
- [ ] 提交／PR：`feat: apply traceable conditional support without duplicate sources`。CF21统一完成指a/b均合并。

## Task CF22：左键框选与集群命令面板

**依赖：**CF13、CF08（可与 CF14–21 并行，文件不重叠）。**拥有：**`scripts/map3d/map3d_input.gd`、`map3d_selection.gd`、`map3d_view.gd`、`scripts/ui/army_order_menu.gd`、`game.gd`、`game_root.gd`；新 `scripts/ui/cluster_order_panel.gd`、`scenes/panels/cluster_order_panel.tscn`、`tests/ui/test_cluster_selection.gd`、`tests/ui/test_cluster_order_panel.gd`，ui/map guides。

**Interfaces:** panel `present(view: Dictionary) -> void`，signals `confirmed(params: Dictionary), preview_changed(params: Dictionary)`；Game 新 `cluster_quote(params: Dictionary) -> Dictionary` 返回获准 options/cost/reason；confirm 仅 `try_execute`。沿用已选unit IDs，不向 map3d 引入 `Game.`。

- [ ] 红灯：军事模式普通左拖框选；2unit不显示新集群，3unit显示；国王/信使/非作战不凑数，单击国王不留军队选择。地图平移提供右拖（不吞右键菜单的单击），Shift 追加选择保留；路线弯折/已开启目标预览优先，不冲突开群。
- [ ] 红灯：可用项靠前，八项及具体缺项、无阵型、强翼左右、费用、慢成员可见；取消/点选只改预览不拆队；跨群确认明确保留/合编；键盘focus/长文/缩窗仍可用，不撑宽LEFT。
- [ ] 跑红灯；通过 gdai 编辑器搭面板及引用，保存前对齐所有打开脚本与磁盘；最小绑定并绿灯，UI/map editor-owned/no-Game 守卫和既有多选/royal菜单回归。
- [ ] 真实窗口 visual-review 全图+3倍裁图、2–3变体，唯一 Review 独立按八轴批评。提交／PR：`feat: choose cluster plans from military box selection`。

## Task CF23：已知预览、阶段回执与身体显示一致

**依赖：**CF22、CF12；接敌反馈在 CF21 合并后复验。**拥有：**`battle_presentation.gd`、`scripts/ui/game.gd`、`cluster_order_panel.gd`、`war_formation_dots.gd`、`scripts/map3d/map3d_view.gd`、新 `scripts/map3d/map3d_cluster_preview.gd`、`scenes/map3d/cluster_preview.tscn`；`tests/engine/test_cluster_projection.gd`、`tests/map3d/test_cluster_preview.gd`、`tests/ui/test_cluster_receipts.gd`，相关 guides。

**Interfaces:** 新 `BattlePresentation.cluster_view(repo,state,realm: String,request: Dictionary) -> Dictionary` 输出获准成员、路径/阵位/朝向、慢成员、预计时间/阻塞、阶段、已送达版本/原因；map `apply_cluster_snapshot(snapshot: Dictionary) -> void` 只读投影，schema不含隐藏enemy/raw state。集结估计由实际已知路线和准备导出，变化时刷新。

- [ ] 红灯：只改隐藏敌位置/人员/预案，投影序列化完全相同；合法己方/已见变化正常刷新。远端预览不读真实敌占位，确认时合法重新验证；场地不足显示阻塞阵位，不缩模型/换阵。
- [ ] 红灯：pending/assembling/partial-delivery/formed/invalid/failed 和命令版本分批可见；渲染10→9→0、空位范围不缩、单unit pick和任务信号仍正确；幽灵不查询隐藏当前 fit，fleet不生成兵人。
- [ ] 跑红灯；编辑器制作静态预览资源、绑定投影，绿灯及 `test_map3d_battle_groups.gd`、`test_map3d_formation.gd`、WAR ROOM folio/UI守卫；真实窗口检查路线、箭头、朝向、重组受袭和错列射界，与CF04路径合同一致。
- [ ] 提交／PR：`feat: project known cluster deployment and delivery progress`。

## Task CF24：数值实验与条件优势平衡

**依赖：**CF21、CF23。**拥有：**新 `tests/balance/test_cluster_outcomes.gd`、`tools/cluster_bench.gd`、`docs/reviews/cluster-formations/balance.md`；`data/battle/cluster_effects.csv`、`data/battle/balance.csv`（cluster键）、`tests/categories.json`、`tools/CLAUDE.md`。不修改运动/伤害算法以凑胜率。

**Interfaces:** bench CLI `--formation CODE|none --scenario CODE --seed N --out PATH`，输出原始种子/输入hash、每子步接触/射击/阻塞/收益来源、伤亡/胜负/计算成本。复用当前BattleScenario式fixture但开启真实身体规则；每组装备、人数、地形、补给相同。

- [ ] 先冻结开阔适配、窄地克制、未完成受袭、缺兵种及无阵型对照，八阵型各覆盖；运行固定训练种子集合调参，保留失败样本。为新量值先写手算小测试，不用胜负观测当公式期望。
- [ ] 在独立验证种子运行前，将具体优势目标（胜率/伤亡差及容差）、受克制失败要求、CPU子步预算/规模/硬件写入 balance.md；目标尚未有证据，不能提前承诺百分比。验证集合不得用于反复调参，失败就保留结果重新审视。
- [ ] 显式 `./run_tests.sh --test tests/balance/test_cluster_outcomes.gd`；PR正文 `GUT_INCLUDE: balance`。只有适配且成阵有稳定可辨认战果优势、错误/未成阵仍能失败、无穿体/隔空伤害/隐藏反制才通过。
- [ ] 同时测引擎规模与 map近/中/远、still/pan性能；沿用 tier budgets，不降低现有门槛。提交／PR：`balance: validate conditional cluster advantages`。达不到目标则此步未验收，不能改文案宣布通过。

## Task CF25：端到端保存、对称性与真实窗口验收

**依赖：**全部前置（CF24已合并验收）。**拥有：**新 `tests/gameplay/test_cluster_campaign.gd`、`tests/simulation/test_cluster_replay.gd`、`docs/reviews/cluster-formations/acceptance.md`、`docs/reviews/cluster-formations/evidence/`、必要 `tests/categories.json` 分类。此步只验证；产品缺陷交独立有界修复PR及其固定两人，不把本步变全系统修复包。

- [ ] 先写端到端断言：相同save+input，暂停/1x/4x、镜头外、每个子步cursor及pending round保存恢复的最终 state_hash/人员/费用/命令版本一致；旧6/7档非重叠迁移幂等，异常重叠和非法结构明确拒绝不覆盖；换阵取消/在途信/合并不中途重扣。
- [ ] 跑显式 `--test tests/gameplay/test_cluster_campaign.gd` 和 `--test tests/simulation/test_cluster_replay.gd`；PR正文 `GUT_INCLUDE: simulation,gameplay`。敌我调换种子/兵力后遵守相同资格/通信/空间/准备，隐藏状态不驱动完美反制。
- [ ] 冻结真实新系统产出的save（不手改点），记录raw/loaded/final hash、HEAD、pack/world/资源hash；按下一节拍摄满员/减员、穿插、敌触、八行为、信使/国王、受袭/失败/增援/部分选取。独立 Review 先看图片和taste再看作者结论。
- [ ] 更新逐项验收及缺陷，不把 skipped/缺图/timeout算通过；跑文档和最终相关检查，提交／PR：`test: accept cluster formations through replay and real windows`。若视觉失败，保留失败并停止该验收，不派发下一产品特性。

## 真实窗口验收方法与证据合同

所有视觉相关PR（CF01/04/07/22/23及最终CF25）都使用 `visual-review`：先读 `.claude/skills/visual-review/taste.md`、相关参考；真实窗口before、至少2个变体、全窗+3倍裁图、唯一Review独立八轴批评；发生资源改动重拍受影响证据。唯一Review作为fresh critic不另spawn第三人。没有本地窗口/gdai时，只能交代码证据并明确剩余编辑器/视觉门禁，不能声称验收完成。

现有冻结拍摄入口（参数必须用真实路径替换；共享锁在超时外）：

```sh
/Users/samuelzhang/game_design-wt/godot_lock.sh python3 tools/run_with_timeout.py 300 /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/snapshot_screen.tscn -- --screen root --resolution 2560x1600 --battle-save /ABS/INPUT.json --group-evidence /ABS/EVIDENCE.json --out /ABS/OUT.png --zoom3d 400 --yaw3d 90 --still
```

仅用于实际含合法battle groups的新系统save；非战斗或面板截图使用现有普通 `--screen root` 实际交互路径，不能给 `--battle-save` 不满足其前置的数据。动态穿插录制逐帧/多时点实际窗口与引擎完整轨迹同时留证，单张静态图不能证明全过程。不得 headless 3D；截图源和输出分离；raw/loaded/final hash区分迁移，loaded=final证明拍摄不改状态。

窗口至少2560×1600及当前项目支持的较小窗口，近/中/远与不同yaw；模型尺度/占位一致、骑马/当前炮兵 placeholder 不穿体；真实火炮替换后重测身体、旋转、运动、视觉及性能，当前证据不覆盖真实火炮；敌人保留真实遮挡。必须涵盖：901→900范围保持、相向/三队/窄路/转身、敌接触与合法缺口、骑兵真实侧绕、弓炮挡线、重组中伤亡/停滞失败、分批收令、实际随阵国王、增援仅新成员走位。任何“看不清/被遮挡”按真实结果记录，不能隐掉场景强行过关。

性能沿用 `tools/map3d/bench.gd` 及 map guide tiers，在相同场景/分辨率/硬件记录 median/mean/p95 和pan；新引擎运动预算由CF24冻结。数据CSV或模型尺寸有变，重跑相关手算/轨迹/保存和视觉；无关文档变化不重跑游戏全套。

## 依赖、并行和实际派工规则

关键顺序：CF01 →（替代接入门禁及文件归属冲突解除后）CF02→03→04a→04b→04c→05→06→07；独立CF08可与测量并行，但修改loader/index时不得与CF02同启。CF07+08→09→10→11→12→13→14→15→16→17→18→19→20→21。CF22在CF13后可与自动行为链并行，CF23与CF21共享 `battle_presentation.gd`，两者必须串行或先只完成不重叠的独立步骤；CF24等待CF21+23；CF25最后。

串行不仅由箭头决定：任意 shared guide、loader、index、Game、测试fixture、CSV都算文件归属冲突；默认串行，不能两PR同时拥有一文件不同区域。CF08若先合并，CF02基于其新loader再接入；反之亦然。每步引入自己的小fixture，不擅改N1或全局BattleScenario；真需共享fixture，先追加精确归属并重新审计冲突。

**派工状态：**CF01/CF08 已有实施 owner，保留其实际登记及唯一 Review，不重复创建；其余任务的模板不代表已派工，实际状态以共享 registry、现有 PR 和各自检查点核对。获准执行后，唯一派工方逐步登记 `step_id/dependencies/owned_files/acceptance/worktree/branch/implementation_session/review_session`，核对 active registry/PR/检查点后才创建一次；Review最迟交接前确定。依赖已合并且适用验收通过才能启动。CF04a/b/c、CF07a/b、CF21a/b各是独立step_id与PR，禁止合成大实现；其余步骤如遇额外未预见范围，先修订边界再启动。当前计划编写者交付后结束，不兼任后续调度。

## 本计划自审与停止条件

- spec §2–3／验收1–2：CF01–07及CF25；§4选择/行军/信使/增援：CF08–13/22–23；§5失败：CF11/13；§6八阵型：CF14–21；§7条件优势：CF06/21/24；§8保存/迁移：CF02/07/09/25；§9真实窗口：各视觉PR及CF25。没有疲劳度步骤。
- 签名以本计划定义的新接口和调查到的旧入口为界；每个实现者先核对上游最终签名，若不一致更新该步计划再动调用方，不增加兼容wrapper掩盖错误。
- 本计划PR只做文档检查、路径/覆盖自审和必需CI；不启动Godot、测模型或声称数值/视觉已通过。
- 本次依赖维护停止于文档 PR 由唯一 Review 审查、当前 HEAD 必需 CI 成功并合并；不创建产品实施会话、不派 CF02、不操作 #178 终态。

## 提议的有限分阶段接入（DRAFT，未批准，未登记）

本节转录原 CF02 owner 的边界建议；不修改以上 Task CF02–06 的当前批准合同。批准前不能按此执行、重新派工或释放 claims。CF01 (#186 / `068f33ba`) 和 CF08 (#185 / `579146b6`) 已 accepted；N1 为 superseded / unmerged、#178 closed，不是可满足依赖的 accepted 步骤。迁移索引 #184 / `4deeda27` 与 harness #183 / `08beb1f6` 已合并。本次核对仅消费作者报告，不审查 CF02 产品 diff。

提议顺序：CF02 被动基础 → CF03 纯 planner → CF04a 候选 march → CF04b 候选 placement → CF04c 候选 render → CF05 候选 battle → CF06 候选 damage → **PROPOSED-CF-ACTIVATION** → CF07a → CF07b。激活依赖全部前置合并及适用验收，基础不反向依赖激活；不存在 CF03→CF02 回边。`PROPOSED-CF-ACTIVATION` 只是本文占位 ID，未登记、owner 未分配；其他标签也是建议边界，不是新的启动记录。共享文件/guide 必须串行。

中间提交保持旧生产完整调用链；新 route 只能由显式候选入口在隔离副本上调用，读取不 materialize。不能自动 read 初始化、局部 live 混用、影子运行状态、全局 feature flag 或永久 fallback。被动序列化可保留明确存在且有效的元数据，不凭空制造 missing pose，也不对未改变的旧运行链全局强加新物理验证。新保存版本发布及生产 lifecycle 接线留至激活。每步须证明普通 march/spawn/battle/damage/render/load 调用链未改，并跑受影响旧回归。

### 原生产验收暂存映射（仅提议）

- **CF02：**保留十空位/固定范围/精确人数/稳定身份、候选单一存储及迁移的手算和原子测试；把真实 start/merge/exit/cancel/delete 接线、生产保存版本和 `Game.load_campaign` 发布前物理验证暂存至激活。候选迁移不等于旧档生产兼容完成。
- **CF03：**全过程相对扫掠、旋转包络、确定性让行、预算、cursor 和拒绝原子性全部保留；只限制候选副本入口。普通世界全过程无穿体在激活补验。
- **CF04a：**候选 anchor/rows/预算/补给同事务、普通/王军/敌军/撤退/预测共用合同；真实新游戏及生产 dispatch 暂存激活。CF04b：候选营地/离营/招募/敌方/split/reconcile 用真实生产半径和战役输入验证；普通 spawn 接线暂存激活。
- **CF04c：**候选消费者仍须真实窗口近远、暂停/1x/4x、对穿/交叉/转向及性能验收；普通地图 dispatch 暂存激活，并在实际 live world 重做视觉/性能。CF04 不可凭候选渲染宣布原生产 a/b/c 验收完成。
- **CF05：**候选冲锋/包抄/部署/撤退/接敌/merge/end/cancel 的全过程扫掠、同日预算/runup、bilateral parties 和军法协议全部保留；生产接线和真实道路接敌、defeat 日内续行留至激活再验。
- **CF06：**候选真实近战投入与直接射击手算、射程±1米、遮挡、合法目标及零接触零伤害全部保留；生产伤害仍与旧运动成对，最终与其他 writer 同时切换。真实空间必须能形成合法接触/火力，不得缩 R 或暗调射程补失败。

### 激活的不可删门禁

激活仅可为已验证函数的有界接线 PR；若仍需新产品算法或大规模修复，先停止并拆分设计/实施，不能用大 label 吞大 feature。全部真正生成、运动、接触、伤害、render 和 load 安全必须先已可用，再原子切换所有 writer：新游戏 placement 在世界发布前；入战/merge/撤出/结束/取消在删除前转移唯一身体；候选 load 验证版本与冻结事务后才发布。同步移除过时绑定，不留物理 fallback；CF07 随后只退役旧战术语义。

合法旧档原位、原路径、slot、人员和已付成本必须保留；重叠/损坏/未来版本 fail closed，失败不改原文件或当前运行 state，不提高 MIN_SAVE_VERSION 丢弃兼容。missing legacy nonbattle pose 的分类及初始化政策尚待明确批准：仅可经已证明 placement 在 load candidate 显式初始化，或明确拒绝；不能把缺失必需身体行一概当 legacy。新当前战役 boot/save/load 必须成功。未完成事务保留冻结数据，恢复不重复人员/移动/费用，非法恢复明确拒绝。

激活须以 CF01 生产半径通过未改弱的道路接敌、defeat 续行、新战役 roundtrip、military reorganization、slot/人员/成本守恒、保存确定性及最终受影响 selector/runtime gate/current-HEAD CI/独立 Review。继承的 55 fail 和 6 risky/pending 须逐项分类并解决，无排除、门槛变化或继承 PASS。真实窗口 visual-review 验收满员十人、各强度固定占地、全程无穿体、实际生成/接战/射击及性能；CF01 有限17采样及炮兵步兵替代限制仍保留，输入改变须重测。

### 批准与执行前清单

- [ ] 人类明确批准上述有限 staging 例外、原 CF02–06 acceptance 拆分和补验落点；最终 spec §2–9、十兵人/固定占地/全过程扫掠/军法通信/八集群/保存确定性/真实视觉性能要求全部不变；后续 CF09–26 不删除或提前算完成。
- [ ] 明确保留 WIP 的提取方式及现有 fixture 改动处理，保留全部失败；未获准的额外12测试路径仍不得编辑。
- [ ] 批准 missing-pose/schema/版本兼容政策，区分合法 legacy 缺字段与损坏的必需字段；锁定新战役 roundtrip、合法原位旧档与非法档拒绝测试。
- [ ] 确定激活 step 的正式 ID/唯一派工方/唯一实施与 Review，以及原 CF02 owner 是否保留延后生产验收；不得替换 owner 或在原 scope 累积后续功能。
- [ ] 在单独授权的规则处理及合法 registry 流程明确验收修订/claims 后，再逐步登记精确文件、依赖、owner、worktree、branch；原 CF02 在此之前仍 blocked，不能当作已完成依赖。不得直接改 registry accepted/ownership 或由本文终态原 CF02。
- [ ] 每步登记前确认候选入口的确切签名与测试、guide 路径及授权。源建议没有给出全部候选 API 名称，故这些任务尚非可执行计划；由原负责方确认后补齐，本文不发明签名/算法。

详见边界记录中的源合同、文件清单与具体未决问题。本草案只允许文档 Review，不能创建任何产品后继。
