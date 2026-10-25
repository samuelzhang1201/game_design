# N1 → CF 迁移接入索引

本文件只维护 #181/#182 的依赖。原 N1 固定 pair 的 Audit 2 结论为 `PRESERVATION_AUDIT_PASS_ONLY`；不是产品、运行、视觉、性能验收，也不是 close-ready。PR #178 不要求合并：仍需的基础要求在已有 CF02–06 按新设计实现并逐步验收，没有由本清单证明需要新增的独立基础 PR。

## 冻结来源与可恢复索引

- 原 step `p4-narrow-deployment-capacity`，[PR178](https://github.com/samuelzhang1201/game_design/pull/178)，HEAD `62436a2e64c0038083d6fbe9df827f3415265823`，base `c8b10a923f6681f98552ace192144f434519e486`。
- 原实施 `01a16dcd-07a8-7830-819a-659476230b4c`，唯一 Review `01a16e52-0843-77e1-bc6f-5b3ef4b8eb91`。本文件 pair 仅负责依赖文档，不成为 N1 产品第三 owner。
- 原 checkout `/Users/samuelzhang/.codex/worktrees/p4-narrow-deployment-capacity/game_design`；保全包位于其 `.superpowers/p4-narrow-deployment-capacity/migration-preservation/`，正式核验为 `.superpowers/p4-narrow-deployment-capacity/review/MIGRATION_AUDIT_2.md`。
- Audit 2 SHA256 `932e84aaf8bb3a2866f28174545915f722126a6b9eb1f27c16366c880af2d27b`；`MIGRATION_HANDOVER.md` SHA256 `00b2cf4af86b5c32b21609691831dcdd75610cc4519a5ed2e9cec893553323ae`；`MIGRATION_MAP.json` SHA256 `d7f71f7b0f74ec501aa619ab61ea2e4318a15efb50dadb21dc7957f272b35016`。
- 最新耐久前缀 `/Users/samuelzhang/.codex/visualizations/2026/10/24/01a16dcd-07a8-7830-819a-659476230b4c/N1/migration-62436a2e-20261025-r2`；其 `migration-preservation/` 含上述清单。`PRESERVATION_MANIFEST.json` SHA256 `119efb0feedce155f63a632b2ea0ee2834e6637119e23496c09a3985195c851e`。原 Review 已核验双端 1550 文件／1799057448 bytes，保留 audit1 和旧快照。
- `MIGRATION_MAP.json` 与 `MIGRATION_HUNKS.md` 是 47 文件／173 hunks／2282 changed lines 的逐行策略、函数、旧新行号、原 commit、base/head source SHA256 和 file/hunk patch SHA256 索引。F29-H03 的 22 行旧校准归为 measurement → superseded reference → CF01/CF02；其余 172 hunks 未变。
- `full-pr178.patch` SHA256 `e11fb17a7df4c63a83183e7107d4bcf8a80aaa230ab714a404dcbbbdacc4d57d`；`pr178-incremental.bundle` SHA256 `310e8cac68dbc173dd0608d9e3ba48a5948ec03cc370a4814dfe1c202e0655a2`。bundle 需要保留的 main 历史 `95e92ed4ccd48de4681b48457ab70da14f46825a`、`c8b10a923f6681f98552ace192144f434519e486`、`fede450e184c6cb63caf57613a66122e16200eb9`，不是 standalone。`sources/base/`、`sources/head/`、`patches/files/`、`patches/hunks/` 和 `git-log.txt` 保留原始字节与历史。

此处只消费原 pair 的正式保全核验并核对三份输入哈希，不独立重审 N1 产品 diff。恢复材料只供获准 CF owner 在隔离 checkout 查询；禁止整包应用或 wholesale cherry-pick。CF02–07 从各自启动时的 `origin/main` 实现新设计，不把旧工作树当接入基线。

## 必要要求的已有接收步骤及门禁

下列文件名未带前缀时属于 `scripts/engine/`；新测试按计划位于 `tests/engine/`。完整拥有文件仍以计划及派工 registry 为准，本索引不新增派工或扩大文件归属。

- **CF01 → CF02，尺度与事务。** CF01 只读测量；旧 `figure_radius/compact_radius/pitch/occupied_radius` 及 F29-H03 仅作对照，人数半径不继承。炮兵当前用用户批准的步兵 placeholder，报告标记以后真实火炮必须重测，不能因缺资产另加基础 PR。CF02 接收 `battle_groups.gd` 的 refresh 候选／回滚、稳定 slot/count、migrate_size 拒绝，以及 `battle_system.gd` 的 join/_start 准入回滚和 `military_reorganization.gd` 的 split 装备先于占位查询；新 `unit_bodies.gd`、`game_state.gd`、`battle_merge.gd`、`scripts/ui/game.gd` 等按计划建立单存储与发布边界。门禁：CF01 合并且实测通过；CF02 十空位固定范围、人数守恒、入战/出战/merge 原子转移、JSON 幂等、非法旧档拒绝且原文件和当前 state 不变，计划列明 migration/save 回归通过后合并。
- **CF03，全身体扫掠与进展。** 新 `body_motion.gd` 接收旧 `_ground_clear/_rect_distance_sq/_distance_sq` 的胶囊内部、端帽、边界、预算裁剪反例。旧 battle-local `_route` 不是已验收解法。门禁：CF02 已合并验收；相向／交叉全路径无穿体、确定性让行、窄道可进展、无出口有限 blocked、绕行实际长度不超预算，重复 cursor/JSON 不重复提交，无效 plan 不发布，`test_body_motion.gd` 通过后合并。旧完整 clump 退出失败不能被窄两行测试遮盖。
- **CF04a，普通行军。** `army_system.gd`、`tick_engine.gd`、`day_resolution.gd` 接收准确 anchor、冻结日预算和失败不发布要求。门禁：CF03 合并验收；实际身体对穿／三队／敌拦截扫掠，anchor 与 rows 同事务，重复子步和保存恢复不重复移动；`test_body_marches.gd`、`test_army_clearance.gd` 及 march 事务回归通过后合并。
- **CF04b，生成与停驻。** `army_ground.gd` 的 unit_radius/held_taken/settle/refill/reconcile、`army_split.gd` 的 place/seat、`enemy_ai.gd` 的 spawn/arrival_mode/stands_halted 是参考调用点。接收装备相关放置、合法身体空位及失败原因，拒绝整 unit 硬圆作为友军墙。门禁：CF04a 合并验收；camp/spawn/split 人员/slot 守恒，空间不足不硬塞、不瞬移；`test_body_placement.gd` 与 ground/seat/enemy_spawn 回归通过，后者用真实身体分离替换旧整圆要求。
- **CF04c，显示与性能。** `scripts/map3d/map3d_battle_groups.gd`、`map3d_layer_units.gd`、`map3d_formation.gd` 接收原尺度、坡面权威 XZ、竖直种植、按镜头 pick bounds；旧 place cache 与失效测试仅为可查询参考，旧 metre_slots/spread 战术偏移由权威身体路径替代。门禁：CF04b 合并验收；L 路径不切角、身份/转移稳定、无 hidden 查询，map 回归及真实窗口全过程穿插/交叉/转弯 visual-review 通过；相关性能按相同资源/场景重测。不能凭旧端点截图宣称全过程通过。
- **CF05，战斗机动与实际接触。** `battle_groups.gd`、`battle_charge.gd`、`battle_task_system.gd`、`battle_merge.gd`、`battle_system.gd` 接收已保存 flank 点、deploy_flank/charge 全扫掠、单日预算/JSON retry 和正身体接触 merge；旧 deploy_day/_mean_anchor 不能成为第二位置 writer。门禁：CF04a/b/c 全部合并且适用验收通过；计划 `test_body_battle_motion.gd` 及 charge/task/merge/save 回归证明合法 bodies 上真实接触与单次预算，完整堵塞/恢复失败保持可见，合并后才启动 CF06。
- **CF06，真实接触和直射。** `battle_ranged.gd`、`battle_groups.gd`、`battle_system.gd`、`battle_strength.gd`、`data/battle/balance.csv`，新 `tests/engine/test_physical_damage.gd`接收 contact_reach、state-aware touching、射程边界±1m、暴露线段、友军完整包络、平移后整数相切反例。三条 CSV 射程/遮挡注释仅参考语义，两条 spacing 注释已被固定配置替代；原五处均 notes-only，未改数值/schema/order。门禁：CF05 合并验收；按计划用新校准 bodies 手算接触伤害、无接触输出0、射界遮挡和边界/平移用例、保存及既有 ranged 回归通过后合并，旧 front/reserve fallback 不算新合同通过。

CF07a/b 在上述链完成后退役内部战术收益与控件；不移植旧四形 allocator、front/reserve 布局、人数缩放或 legacy-overlap 退出例外。CF02 已批准用明确拒绝重叠旧档替代该旧政策，但合法状态的运动进展仍由 CF03/05 证明。NC/no_clearance、旧 fixture 坐标及 broad campaign 开关不整包带入；每个 CF owner 只在自己的有界范围保留合法 contact、军法、人员断言，不能弱化 clearance 换绿灯。

## 必须继承的失败与重新验收

- **旧完整退出仍 FAILED：**10 个 positive distinct slots、实际 R538；12 个真实 deploy_day 后最小间距仍 40m，assert58 失败，随后原 180s timeout。`edge_legacy_exit_inputs.gd`、`native-edge-legacy-exit/legacy-before.json`、`edge-legacy-exit-inputs.log` 位于保全前缀；无成功 after-save/retry/screenshot。CF02 的新拒绝政策不把旧失败改成已修复；CF03/05/CF25 保留合法状态完整进展与恢复门禁。
- **旧当前 HEAD CI 仍 FAILED：**[run40191336312](https://github.com/samuelzhang1201/game_design/actions/runs/40191336312)，HEAD62436a2e 的 engine-core、UI 和 gut-tests 失败，未根因诊断。`ci-62436a2e-final-failed.log` 及 map evidence 索引保留 charge/deployment/flank、law/herald/ransom、self-defence/pursuit/king/migration 和 king-map bridge 风险。对应 CF02/04/05/06 的回归与最终 CF25 必须在新输入上解决或明确记录阻塞；不能推断全部来自旧 fixture，不能降门槛或 blanket 关闭 clearance。
- **旧 broad local 仍 FAILED：**200 scripts／2132 cases，2126 pass／6 fail；两个 fixture 的单独修正重跑通过不等于原 broad batch 全绿。`contact-final-local-coverage.json` 保存原失败及重跑输入。31/31 actual-clearance 及 targeted range/legacy/translation 仅证明各自冻结输入。
- **44 窗口／12ms 仅旧 author 证据：**`edge-final-author-validation.json` 保留 38+6 captures，未完成独立视觉验收。暂停 medians 9.213/10.888/9.134ms，原 live4x 9.244/10.127/9.360ms 只满足原 median 门槛，不能写成每帧<12ms；p95/CPU spikes 保留。新身体/config/storage/motion 改变使相关旧 runtime/native/performance 验收失效，CF04c/CF24/CF25 必须用新输入验收。

保全 PASS 只证明资料可恢复与分类核对通过。当前没有因此得到 runtime PASS，也没有授权将缺失、跳过、失败或超时当成功。若原清单不足以支持具体接入门禁，记录 blocked 并交回原 pair，不自行设计额外基础任务。

## 状态与停止条件

CF01/CF08 原 owner 继续；本文件不创建、替换或唤醒产品 owner，不派 CF02。所有后续步骤先核对实际前置合并／验收及活跃文件归属；PR178 未 terminal/close/release 时不能抢占其 claim。只有原 controller 与原 pair 处理后续 close-ready 和保留 branch/tree 的 superseded 关闭路线。本文件及计划合并不等于 #178 已关闭，不终结真实 registry，不清理原／recovery-hold 工作树或 refs。
