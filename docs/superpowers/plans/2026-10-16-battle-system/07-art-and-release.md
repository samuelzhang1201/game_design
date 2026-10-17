# P7 战斗演出、性能与整体验收 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把已可玩的各阶段整合成完整的3D战争体验，达到资产、性能、存档与发布门槛。

**Architecture:** BattlePresentation输出已知事实与表现阶段；Map3DBattle编排代表兵人的阵型、局部配对与动作。动画绝不反写伤亡，视图散列相位不消耗引擎随机流。

**Tech Stack:** Godot 4.7 Forward+、AnimationPlayer、Blender、GUT、真实窗口截图与现有bench。

**Spec:** [设计 §16–20](../../specs/2026-10-16-battle-system-design.md)；[总计划](../2026-10-16-battle-system-implementation.md)。前置：P1–P6功能与对应资产已验收。

## Global Constraints

- 唯一战场为现有3D战略地图；Blender生产模型和可复用动作，不制作固定整场战斗影片。
- 没有疲劳、紧急弃营、失联、后方押送或国王被俘；无独立战斗时钟和五轮平局。
- 一兵人代表一组人员，敌军可见数量不能泄露精确兵力；兵人头顶无数字/条/图标。
- 国家色只作用于合适布料/旗盾；贵族靠装备与少量纹章辨认，不全军穿骑士装。
- 所有运行资产提交，WIP源按目录规范；禁止Hunyuan3D，付费Tripo仅按已有授权使用。
- 视觉必须真实窗口审查；headless只跑逻辑；遵守总计划测试、PR与CI规则。

## Review Focus

1. 动画先播死再结算，导致玩家看到假阵亡：P7.1 `test_death_requires_confirmed_loss`。
2. 改镜头/刷新UI改变下一次战果：P7.1 `test_presentation_does_not_advance_rng`。
3. 暂停/4倍速漏掉撤退投降或进入下一场：P7.1 `test_terminal_state_is_not_skipped`。
4. 坡地、窄路、多战场帧耗超预算：P7.2真实窗口录制和bench性能门槛。
5. 仅开发机有未提交GLB或旧存档恢复改变结果：P7.3全新克隆及JSON往返全流程。

---

## P7.1 兵人编排、动画与完整国家色

**Create:** `scripts/map3d/map3d_battle.gd`、`scripts/map3d/map3d_battle_pairs.gd`、`tests/map3d/test_map3d_battle.gd`、`tests/map3d/test_map3d_battle_pairs.gd`。

**Modify:** `scripts/map3d/map3d_units.gd`、`scripts/map3d/map3d_unit_rig.gd`、`scripts/map3d/map3d_unit_settle.gd`、`scripts/map3d/map3d_formation.gd`、`scripts/map3d/map3d_layer_units.gd`、`scripts/engine/battle_presentation.gd`、`scripts/engine/game_art.gd`；对应已有单位GLB和编辑器场景、`assets/3D/units/army_models.tres`。

**Interfaces:**

```gdscript
# snapshot来自BattlePresentation，含phase/known sides/formation/action/loss revision。
func apply_snapshot(snapshot: Dictionary) -> void
func set_playback(paused: bool, world_speed: int, day_progress: float) -> void
# Map3DBattlePairs：输入纯展示槽位，最大距离用世界米；无Game/模拟写入。
static func pair(front_a: Array[Dictionary], front_b: Array[Dictionary], max_distance: float) -> Array[Dictionary]
```

- [ ] 写pair测试：每个front槽位最多配对一次、超距离无配对、稳定id同输入同结果、移走对手后重配；support/reserve不全挤到front。运行两个新map3d文件见红。
- [ ] apply_snapshot保存最后loss_revision；只有确认损失递增才退出/倒下相应代表人物，重复投影不重播。没有精确敌损时只表现可观察退却，不从隐藏dead数推导数量。`test_death_requires_confirmed_loss`：同一attack循环播放100次无新revision，零新增死亡。
- [ ] pair仅负责近战前排的就位/攻击/格挡/退步；支援补位、后备保留轮廓，突破口允许局部交错。导航沿合法地表、局部避让，禁止整块队伍穿模。视觉相位用稳定展示id散列，不调用state RNG；修改镜头/帧数/可见兵人数后SaveLoad.state_hash不变。
- [ ] 阵型几何根据宽度、方向、地形与中心目标生成：横线/锥形/菱形/双排各有辨识轮廓。9/6/3等既有可见档位继续用于代表性显示，战术槽位由阵型决定；不将真实每人坐标放入存档。
- [ ] 复用已合格动作，按下表补齐；每个GLB检查骨骼、脚底/握点、root motion约定、循环接缝和导入设置。动作名在ArtTable/Resource映射，不在多处硬编码猜名。

| 角色 | 必需动作/序列 | 实际画面判定 |
|---|---|---|
| 步兵 | march、standby、garrison、attack、block、recoil、retreat、surrender | 不锁步挥刀，盾武器不脱手，脚贴地 |
| 弓兵 | ready、draw、release、reload、defend/withdraw | 箭与手部配合，群体节奏错开 |
| 骑兵 | approach、impact、disengage、regroup | 有冲击距离，不原地无限冲锋，不马腿滑行 |
| 指挥官/传令官 | command、observe、rally、parley、travel | 交涉与指挥阶段可读，家徽节制 |
| 国王 | P3行进/观察/指挥/鼓舞 | 无死亡/被俘槽，真实位置始终一致 |
| 投石机等 | load、aim、fire、reset | 只在真实工程/攻击阶段开火 |
| 俘虏/看守 | lower_arms、guarded_idle、guarded_walk | 接受投降后出现，随实际holder移动 |

- [ ] 国家主/辅色覆盖步兵、弓兵、骑兵、指挥官、旗盾；金属/皮肤/木材/皮革保持自然材质。对相近主色国家用辅助色与旗形区分；两支同国不同家族单位不染成两个国家。Forward+色彩转换按现有shader规范，不让VERTEX颜色过亮。
- [ ] 暂停冻结走位/动画/投射物；加速压缩重复循环，保留对峙、交涉、撤退、投降、结束关键阶段。状态若一帧跨多revision，最后模拟状态优先，用短过渡结束旧演出，不反向播放已失效攻击。
- [ ] 测 `test_terminal_state_is_not_skipped`：attack→accepted_surrender在同帧更新仍收武器；state结束后不再出箭。测 `test_presentation_does_not_advance_rng` 与隐藏状态不同但投影一致。跑map3d/UI、fast并提交 `feat: choreograph battles from authoritative visible state`。

## P7.2 视觉验收与性能门槛

**Modify:** `tools/snapshot_screen.gd`、`tools/map3d/bench.gd`；编辑器如需调整其工具场景，仅在工具侧添加fixture入口。

**Create:** `tools/battle/showcase.gd`、`tools/battle/bench_cases.csv`、`docs/reviews/battle-system/P7.md`。

**Interfaces:** `BattleShowcase.build(repo: DataRepository, case_id: String) -> GameState`，使用固定种子和绑定国家；`snapshot_screen`/bench新增明确的 `--battle-case` 参数。工具调用真实引擎到达场景，不伪造最终模拟结果。

- [ ] showcase固定案例：`field_even`、`field_reinforced`、`camp_packing_attack`、`royal_surrender`、`siege_tunnel`、`siege_assault`、`prisoner_march`；相同case可在截图、bench和人工试玩重复使用。工具读数据入口遵守仓库工具规范，不复制测试SuiteData进正式游戏。
- [ ] 用visual-review实际窗口拍摄：至少2560×1600及当前项目最小支持窗口，各取远/中/近景，晴天/阴雨、平地/斜坡/河边、两国近似色，1x/4x/暂停。关键裁切检查脚滑、持握、穿模、字幕可读、营地尺度和旗含义。制作2–3方案对照、独立审查并记录采纳原因。
- [ ] 执行示例（新增battle-case参数完成后）：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/snapshot_screen.tscn -- --out /tmp/battle-field.png --resolution 2560x1600 --layer "3d map" --battle-case field_even --still
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/map3d/bench.tscn -- --quality high --pan --battle-case field_reinforced --out /tmp/battle-bench.json
```

- [ ] benchmark使用 `data/screens/ui/graphics_quality.csv` 的low/medium/high/ultra档位、各自bench_size和bench_budget_ms；不得改大预算来迁就战斗。比较基线/单战场/多个同屏战场/围城+营地+雨天；负载使用P2人员换算后的实际单位数，另测旧档迁移后更密集的驻军，不能沿用旧单位总数低估负载；记录median/mean/p95、模型/动画人数、显存/内存与图像证据。超预算退出不能当通过。
- [ ] 优先优化远景更新频率、骨骼/材质复用、可见裁剪与投射物数量；不降低全世界时速、不减少真实战斗结算频率。动画角色保持独立AnimationPlayer；静态帐篷/道具按现有允许方式批处理。减面必须使用decimate-quality并重新视觉检查。
- [ ] 人工逐项签收：前线/支援/后备可读、四阵型区别、两国/阶层辨识、贵族肖像统一、营地建驻拔连续、投降后俘虏归属可读、无数字头标、无国王死亡被俘、无缺资产。跑工具受影响测试与fast，提交 `perf: validate battle presentation at map budgets`。

## P7.3 全流程、旧存档与发布

**Create:** `tests/engine/test_battle_campaign.gd`、`tests/engine/test_battle_migration.gd`；归档每阶段证据。

**Modify:** `scripts/engine/save_load.gd`、`scripts/engine/game_state.gd`、`tools/sim_invasion.gd`、`docs/design/DATA_ARCHITECTURE.md`、相应子系统指南。

- [ ] 写全流程测试：征兵600/5%→指定主将→王随军→自动营地→派发搜索→拔营→接敌暂停→四阵型之一→逐条协议→事件/命令→援军→战斗结束→俘虏赎回→重新征兵。每阶段断言总人数、资金、天数、命令记录与合法性，固定seed重跑hash一致。
- [ ] 再运行国王远方版：军令存在信使延迟，指挥官自动选事件，战报送达才知精确结果；搜索预览不显示隐藏敌人。围城版连续40日跨月，穿插解围/强攻/停火契约，工程与粮账不重复。
- [ ] 存档矩阵覆盖遭遇暂停、第二战场事件、赏金保留、国王在途、收营半途、搜索已覆盖、围城工程、条件投降deadline、在押/交换待履行。每点JSON往返+新TickEngine后，同输入与不停档分支hash一致；重复读取和UI刷新不改变RNG。
- [ ] 旧存档迁移保留现有伤兵/死者/军令/已知情报；新字段缺省后只初始化一次；旧战斗round≥5不被新系统强制平局或复制新battle。未知未来版本明确拒绝，不静默丢字段。现有保存版本6与最终新版本间写单次升级测试，版本号以执行时基线为准。
- [ ] 删掉所有已被替换的实际入口：五轮平局、按开局死者算粮、从首都默认发所有军令、敌军回撤免接触、装饰线直接驱动任务的捷径。删除前先用rg查调用并迁移，不能只隐藏UI保留可达后门。
- [ ] 审查无新增疲劳属性/费用/事件、紧急弃营、暂失联、后方押送、国王俘虏流程；负向测试覆盖公共ActionSystem命令入口，不以文本搜索到“没有疲劳”的说明算失败。
- [ ] 校准CSV并保存模拟报告：普通均势组3–5天，悬殊更短、真实增援/补给可延长、至少一场跨月围城。报告每组seed、起止、实际日数、伤亡和消耗，不用平均值掩盖异常，也不承诺所有野战必在3–5天。
- [ ] 跑fast及改动的UI/map3d/war_room目录；创建PR后等完整CI通过。全新克隆只做Godot导入即可离线运行完整案例，不依赖本机未提交GLB、ComfyUI、Blender、模型缓存或密钥。
- [ ] 更新状态为实际已完成的阶段，不提前勾选；附PR、CI、测试、视觉、性能和新克隆证据后提交 `test: verify the complete battle campaign and migration`，按PR合并流程发布。

**最终放行：** P1–P7所有门槛通过；没有以缺美术/缺动作/缺旧存档迁移结案；真实游戏中能从画圈下令一直玩到战报与俘虏再征募。
