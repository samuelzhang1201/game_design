# P2 贵族指挥官与征兵 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每支实际部队有唯一贵族指挥官，玩家付费选择贵族比例，人物、人口和军队人数可核对。

**Architecture:** 复用 Character 的家族、sk_martial、prestige 和性格；新增 MilitaryRoster 统一身份人数，RecruitmentSystem 执行原子征募。新界面通过 ActionSystem 调用，不把旧 LEVY_RAISE 的抽象军力增益误当真实征兵。

**Tech Stack:** Godot 4.7、GUT、CSV、Qwen/ComfyUI、编辑器 Resource。

**Spec:** [设计 §5–6、§16、§20](../../specs/2026-10-16-battle-system-design.md)；[总计划](../2026-10-16-battle-system-implementation.md)。前置：P1。

## Global Constraints

- 普通单位贵族比例最高 10%，包含指挥官；最低无骨干编制仍有 1 名贵族指挥官。
- 征兵直接付钱，无家族审批；不增加亲卫系统；贵族不等于骑兵。
- 无疲劳；人员状态无失联池；伤亡后比例超限不删除贵族。
- 头像只覆盖玩家、开局入侵国家和实际需要的接替人选；2D 手绘 Qwen。
- 引擎确定性、整数存档、CSV 数值、SuiteData 夹具；遵守总计划测试/视觉/PR流程。

## Review Focus

1. 600 人加上指挥官变 601：P2.1 `test_commander_is_in_noble_total`。
2. 一人同时指挥两队：P2.1 `test_commander_assignment_is_unique`。
3. 余款/人口不足却扣部分费用：P2.2 `test_recruitment_is_atomic`。
4. 残部贵族比例超限被系统删除：P2.2 `test_casualties_do_not_enforce_recruit_cap`。
5. 拆分军队后画像数量不足：P2.3 `test_commander_art_manifest_covers_roster`。

---

## P2.1 人员账与主将选择

**Modify:** `scripts/engine/world_ledger.gd`、`data/realm/order_costs.csv`、`data/realm/world_schema.csv`、`scripts/engine/character_factory.gd`、`scripts/engine/game_state.gd`、`scripts/engine/army_split.gd`、`scripts/engine/map_objects.gd`、`scripts/engine/army_system.gd`、`scripts/engine/battle_system.gd`、`scripts/engine/hazards.gd`、`scripts/engine/army_conduct.gd`、`scripts/engine/desertion.gd`、`scripts/engine/data_repository.gd`、`data/council/roles.csv`、`data/tables.csv`。

**Create:** `scripts/engine/military_roster.gd`、`scripts/engine/military_population.gd`、`tests/engine/test_military_population.gd`、`scripts/engine/battle_command.gd`、`data/army/commanders.csv`、`tests/engine/test_military_roster.gd`、`tests/engine/test_battle_command.gd`。

**Interfaces:**

```gdscript
# MilitaryRoster
static func composition(total: int, noble_permille: int, cap_permille: int) -> Dictionary
static func living(state: GameState, code: String) -> int
static func fit(state: GameState, code: String) -> int
static func personnel_capacity(repo: DataRepository, equipment: Dictionary) -> int
static func assign_commander(repo: DataRepository, state: GameState, code: String, character_id: String, reason: String) -> Dictionary
static func transition(repo: DataRepository, state: GameState, event_id: String, changes: Array, reason: String) -> Dictionary
static func mobilize(repo: DataRepository, state: GameState, event_id: String, recruits: Array, reason: String) -> Dictionary
# MilitaryPopulation：总居民数不等于可征平民；源省只能认领一次。
static func available(repo: DataRepository, state: GameState, province: String, field: String = "") -> int
static func occupied(state: GameState, province: String, field: String = "") -> int
# changes为cohort_id/from/to/count的批次，先整体校验，再同步提交。
# mobilize与transition是唯一人员写入；人口读数从同一份cohort派生。
# BattleCommand：ids 是已合法筛选的本战场人物；nominee 必须在 ids 内且可任职。
static func select(state: GameState, ids: Array[String], nominee: String) -> String
```

每队 `military_rosters[code]` 保存 commander_id、cohort_ids及任职记录；cohort本体只存在 `military_cohorts[id]`。cohort含 `id/unit_code/source_province/source_population_field/identity/family_name/stage/initial/fit/wounded/captured_current/dead/released`。来源字段必须明确城市或农村人口；stage区分集结与现役。五种人数互斥，`initial=fit+wounded+captured_current+dead+released`。具名指挥官使用带person_id的单人贵族cohort，任命只引用该记录，不额外加人数；死亡、负伤、被俘或退伍后解除任命，获释需重新征募。P5持有批次只引用源cohort；历史累计被俘人数保存在不可变战报/事件中。人口占用只从fit+wounded+captured_current派生，集结项目不重复占人。released表示已成为平民的明确去向，不能直接转回fit；重征创建新cohort与新费用。

装备／编制元素与人员分开保存。人数容量按当前包 `unit_types` 的 `crew` 计算；现有一艘舰船不能当作一名军人。人员伤亡不直接删除同数量舰船或炮；装备毁损另记且影响可投入战力。身份比例始终按人计算，不能按武器、马匹或舰船计算。

人口口径：现有省人口作为总人口基数，新增按原籍保存的军事动员占用；可征人数=人口规则允许的平民−已动员者。征募不同时扣省与王国两份总人口；阵亡才经 WorldLedger 减对应来源人口一次，汇总从来源推导。释放解除动员占用并登记平民，不能增加总人口一次、可征池再增加一次。初始军队迁移占用既有人口，不减总人口；若历史数据与人口不一致，迁移报告冲突并禁增募，不能制造负数或削减现有军队。俘虏只算原籍动员人口，不因被押到敌国改变原籍人口。

- [ ] 写下列手算测试并运行新文件见红：

```gdscript
func test_commander_is_in_noble_total() -> void:
    assert_eq(MilitaryRoster.composition(600, 50, 100),
        {"commoners": 570, "noble_troops": 29, "commander": 1})
    assert_eq(MilitaryRoster.composition(600, 0, 100),
        {"commoners": 599, "noble_troops": 0, "commander": 1})
    assert_true(MilitaryRoster.composition(9, 0, 100).has("error"))
    assert_true(MilitaryRoster.composition(600, 101, 100).has("error"))
```

- [ ] composition 在合法输入上以 `nobles=max(1,total*noble_permille/1000)` 取整，commoners=total−nobles，noble_troops=nobles−1；再检查 `nobles * 1000 <= total * cap_permille`。生产调用从 CSV 传入普通单位上限100‰，不把上限藏进函数常数；上面的100仅为测试输入。百分比目标与最终整数比例同时显示，不能承诺600人能表达任意小数比例。
- [ ] 先写人员换算测试：夹具 1 艘船×100 crew=100 人，贵族5%为95平民+4骨干+1指挥官；2门炮×8 crew=16人，无骨干时15平民+1指挥官。重复初始化及旧档迁移不得再次乘 crew；装备仍是1艘、2门。旧dead/wounded/deserted保存值按已记录人员事实保留，不随crew再乘一次；例如200骑兵元素、crew2、10死/20伤/5逃兵迁移为365可战/20伤/10死/5平民，记录换算口径，不复活已损失者；旧装备毁损无法精确还原时保留旧装备记录与迁移说明，不伪造历史。
- [ ] 人员换算与既有拆分上限一起迁移：`army_split_cap_men` 约束人员，普通陆军的装备元素上限为 `floor(cap_men / crew)`，再按既有均分算法拆分。crew必须为正整数；单元素所需人数超过cap时给出数据错误，不静默造超限单位。舰队和一国一支royal train保留现有组织例外。该口径不把crew=2臆解为某种已确认的历史兵种配置。
- [ ] 增加拆分手算：1268个骑兵编制元素、crew=2、cap=600，元素为[254,254,254,253,253]，人数[508,508,508,506,506]，总人数2536；301个元素分[151,150]，人数302/300；7个元素、crew=8、cap=25，分[3,2,2]，人数24/16/16。枪炮和舰船总数量始终守恒。
- [ ] 旧存档从已保存的现存部队迁移，不从开局包重建。拆分时首个子队保留旧ID，其他子队用稳定派生ID；装备、各身份人员状态、库存和战利品按整数守恒分配，保存旧ID到子队列表。军令、信使收件人、战斗参与者逐项映射，同一命令费用不因拆分重复支付；驻防席位只有一个子队继承，其余使用合法相邻驻地。
- [ ] 若旧档处在未完成日事务，先保存待重组标记，保持原事务参与者和游标，待该事务完成后的安全边界再重组。写两条迁移分支：普通存档立即升级；第二战场阻塞存档先续跑再升级。两次加载后的组织版本、ID映射、人数、库存、命令费用及结果hash一致，不重组第二次。P7重新执行端到端迁移矩阵。
- [ ] 所有初始真实单位逐一绑定 Character，覆盖陆军、舰队及 royal train；玩家国家和开局入侵国家均取完整名册，不只取已越境的敌军。`commanders.csv` 保存 `character_id/realm_slot/eligible/unit_kinds/portrait_key/reserve_priority`，人物完整字段继续由 `roles.csv` 和 CharacterFactory 读取。明确排除国王、外国君主、无资格及存在任职冲突的人物；排序稳定，不能占用已绑定者。
- [ ] ArmySplit 在拆分与合并 royal train 前保存 `source_parts`，每项含原 regiment_code、province_code、arm、equipment_count 和 crew_per_element；所有数量为整数。原始省只是开局驻地，不冒充已经记录的历史征募地。首次初始化使用该省作为明确的原籍分配策略，再按省人口×兵种 rural_rate/urban_rate 的权重做整数分配并保存来源；不能把全部炮组人员记成首都居民。零权重、未知来源或人口不足给出明确冲突，不默认全属农村。夹具农村1000/城市500、征募率120‰/30‰，180人分160农村/20城市；拆分子队只认领自己的份额，JSON往返保留整数与总数。
- [ ] 新增人物使用既有家族绑定与角色字段，不从 cavalry 或 Character.category 单独推断贵族身份。具名指挥官使用带 person_id 的一人贵族 cohort，计入原有总人数；任职记录必须包含 reason。被俘、阵亡或失去任职资格时解除任职，恢复或获释后不自动复任；同一人重新征募时产生新 cohort，旧服役记录仍可追溯。
- [ ] 实现主将：合法玩家提名优先，否则按 sk_martial 降序、prestige 降序、id 升序；已有主将仍有效则援军不重选。主将阵亡/被俘/退出战场才按规则接替。
- [ ] 在 test_battle_command 用三名人物：A技能16威望40、B技能15威望90、C技能16威望40，A/C按id取A；指定合法B取B；新人技能20加入既有战场不夺主将。失效提名返回空ID，由调用方显示明确错误，不偷偷改为另一人。
- [ ] 再测试唯一指挥、同家族多成员可分任、无合格人选不能出征、舰队和两个国家的 royal train 全覆盖。迁移保留原有伤亡事实，人物按稳定ID生成一次；不重新支付初始编制费用。
- [ ] 加入人口守恒测试：1000总人口动员600，可征400；阵亡40后总数960、占用560、可征400；其中60被俘，占用仍560；释放60后占用500、可征460、总数仍960。重复死亡或释放 token 不变。另设农村80/城市20的来源队列，按比例阵亡10，仅对应来源人口1000/500变992/498；王国汇总只减少10。
- [ ] 现有 LEVY_RAISE 只增加抽象军队质量，其独立扣王国农村人口的成本不得继续制造第二份人口账：保留其训练含义及真实财政费用，移除虚假人口扣除，更新显示文案与测试。WorldLedger 的王国城市／农村人口读数改为所属省汇总；人口变更走明确来源省，旧王国缓存只重建一次。既有 schema 的人口写入口也须重定向到有来源的转移或拒绝不明确写入，不能保留旁路。
- [ ] 把 BattleSystem._apply_side 的伤亡、ArmySystem.settle_month 的恢复、Hazards.settle_regiments 与 ArmyConduct.settle_units 的受伤、Desertion.daily_loss 的退伍统一经过 transition。先校验状态、人数、具名人物及 event_id，再同步更新全部账；逃兵退出动员成为平民，无失联池。旧 dead/wounded/deserted 字段如为兼容保留，只能是只读投影。
- [ ] `ArmySystem` 战力/供给读取人员账；MapObjects 的装备数查询与人员数查询分名，逐个迁移调用者，不能全局替换后把船数显示成人数。人员 transition 与本任务的人口写入形成同一守恒单元；跑 roster、army_split、army_power、hazards、conduct、desertion、save_load及fast后提交 `feat: track military cohorts and noble commanders`。

## P2.2 付费征募、贵族效果与真实补给

**Create:** `scripts/engine/recruitment_system.gd`、`data/army/recruitment.csv`、`data/army/noble_quality.csv`、`tests/engine/test_recruitment.gd`、`scripts/ui/army_recruitment_panel.gd`、编辑器场景 `scenes/panels/army_recruitment_panel.tscn`。

**Modify:** `scripts/engine/action_system.gd`、`scripts/engine/army_system.gd`、`scripts/engine/world_ledger.gd`、`scripts/engine/data_repository.gd`、`data/realm/order_costs.csv`、`data/realm/world_schema.csv`、`data/realm/policy_actions_domain.csv`、`data/tables.csv`。

**Interfaces:**

```gdscript
# 请求字典含 source_province, source_population_field, code, total,
# noble_permille, commander_id, request_id；recruit 创建集结项目，不即时生成可战兵。
static func quote(repo: DataRepository, state: GameState, request: Dictionary) -> Dictionary
static func recruit(repo: DataRepository, state: GameState, request: Dictionary) -> Dictionary
static func step_day(repo: DataRepository, state: GameState) -> Array
```

- [ ] 用 SuiteData 复制数据，给夹具平民单价2、贵族单价10、指挥官任职费0、可征人口1000、国库2000。600人5%报价为570×2+30×10=1440；成功后钱560、可征400、总人口仍1000，600人处于集结状态，尚无新增可执行部队。资金1439或可征599均完全不变；同 request_id 重送不二次执行。
- [ ] 运行 test_recruitment/test_military_population 见红。
- [ ] quote 同时返回人数构成、招募钱粮、集结完成日、日消耗、战力/军纪变化及拒绝原因；recruit 同步检查资金、人口、装备与任职资格，足够才付款并预留人员、装备和人物。保存 recruitment_projects 的 request_id、cohorts、commander_id、equipment、start_day、completion_day、status；step_day 在 P1 日事务内完成集结，一次性加入部队。集结中不能出征或重复任命；存档恢复不缩短等待。费用经 OrderCosts核算、可征人口经MilitaryPopulation查询、人员占用经MilitaryRoster.mobilize提交、财政经 WorldLedger，均附原因。
- [ ] 在 ActionSystem 注册 `ARMY_RECRUIT`，与已有抽象训练动作分开；拒绝直接修改人数或跳过集结的旧入口。MilitaryPopulation只派生可征与占用读数；实际动员、阵亡、退伍与释放统一通过MilitaryRoster的批次接口提交，不能另设一份可写人口占用账。

- [ ] 集结夹具用两整日：完成日前仍零新增可战者；第二日日末得到600人含30贵族，之后重复 step_day 无变化。完成前存档往返结果一致；来源易主、集结点失效或指挥官失去资格时暂停项目并给出原因，不继续从失效来源自动补人，也不丢失已付款与占用记录。
- [ ] 贵族战力和供给用身份分组加权，训练/士气/军纪分别只应用一次。把修正分解保存为可读解释。fixture 中平民质量1000、贵族2000，570×1000+30×2000=630000，除1000得到630基础等效兵力；相同部队贵族每人粮3、平民1，则每日660粮。此数值只验证算法，生产值由表与P4调校决定。
- [ ] 测试600人、30贵族中阵亡38平民和2贵族，余532平民+28贵族；70伤兵仍在存活人数内，按1/3日耗得到616粮，不能按开局人数扣660。P5再加60普通俘虏时日耗应为676，己方人数不增加。残部只剩40人含8贵族时不删除贵族，补员目标需重新满足10%上限。零训练、低士气不能被贵族加成重复乘成无敌。
- [ ] 贵族骨干的纪律/稳定收益只由仍能作战的人贡献；负伤/阵亡/被俘后重新派生，不把初始贵族比例永久锁成buff。具名指挥官与骨干损失产生按家族归属记录的关系后果，原因含战场、损失及命令；同一轮重复结算不得重复扣关系。fixture设家族损失1人关系−2，重复消费同一损失id仍只−2；此系数仅用于手算测试。
- [ ] 编辑器制作征兵卡：总人数、贵族比例滑杆、指挥官/家族、一次费用、日供给与最终整数人数；不足原因禁确认；保留窗口选择不提前扣钱。角色肖像复用P2.3。
- [ ] 更新 `scripts/engine/guide/regiments.md` 和数据架构人口说明；跑本任务测试、world_ledger、army_supply_data、UI与fast，提交 `feat: recruit paid noble and commoner cohorts`。

## P2.3 肖像清单、国家色与阶层样张

**Create:** `tools/units3d/commander_manifest.gd`、`tests/engine/test_commander_art_manifest.gd`；`docs/art_team/battle_asset_manifest.md`。

**Modify:** `docs/references/art_prompt_library.md`、`assets/imagegen/cast_art.csv`、`scripts/engine/game_art.gd`；安装到 `assets/2D/portraits/cast/` 与 `assets/2D/portraits/full/`；复用 `scripts/ui/character_portrait.gd`、`scenes/characters/character_portrait.tscn`。

- [ ] manifest 工具输出两国所有实际单位（含舰队与 royal train）的 code→commander_id→realm→family→portrait_key；另列备用角色，不重复统计已有肖像。数量=现役唯一人物并集+实际配置的备用人物并集−已合格资产。旧拆分口径曾盘点玩家44、入侵国64，共108名现役；这不是新系统画像订单。P2.1按crew和人员上限调整拆分后，必须重新输出新开局、旧档迁移两套实际名册，资产取需要支持的人物ID并集及接替名单；生产代码与测试不写死数量。只覆盖实际越境敌军会漏人，不可据此缩减清单。
- [ ] 写 manifest 测试：每个真实单位恰一指挥官、每个需要画像的id恰一资产key、其他国家不进入生成队列；运行见红，然后实现清单器并见绿。
- [ ] 按 tools 指南给每个人物写 `K-` 提示词、cast映射，Qwen先生成不同年龄/阶层的3张样张；复用已有合格人物不重画。2D手绘、统一光照与裁切，家族特征可辨，不用文字水印表达身份。
- [ ] 样张审查通过后用 `assets/imagegen/generate.py` 的明确 ids、seed、variants、model 参数生成清单剩余项，再经既有 `install_map_art.py cast` 安装；记录模型版本、seed、提示词、选图与安装路径。禁止改用未要求的图像模型悄悄替代Qwen。
- [ ] 在游戏人物卡、单位卡、主将任命卡检查小图清晰与full图；缺图测试必须失败，不使用匿名头像作为最终交付。
- [ ] 制作一组普通步兵国家色与平民/贵族对照样张：只染布料、盾面和旗；贵族更完整甲胄，指挥官少量家徽。同时看两国相近主色，使用辅助色和旗形辨认。P7扩展全兵种，不推迟本阶段辨识验证。
- [ ] 真实窗口 visual-review、保存 P2 证据、跑肖像覆盖与相关UI/地图检查及fast，提交 `art: add commander portraits and military identity samples`。

**阶段放行：** 征兵可玩、指挥链唯一、人数/资金/人口一致；现役与备用肖像清单全覆盖；家族与阶层样张通过实际地图审查。
