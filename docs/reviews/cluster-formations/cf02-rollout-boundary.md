# CF02 rollout boundary — DRAFT / 未批准

日期：2026-10-26。文档 step `CF02-rollout-plan`；唯一 dispatcher `01a17398-42c1-7583-8d3f-7b15e877586c`。此记录只整理原 CF02 owner 建议，不是第三产品 owner、架构或产品 Review。原 CF02 implementation `01a17401-321b-71a2-9908-32857c8ef4f8`、38 claims、37 dirty、无 commit/PR/Review、boundary-blocked 状态保持；本步不动其树、claims、验收或失败证据。草案须经唯一文档 Review 和当前 HEAD 必需 CI，再等待人类明确批准 staging/ownership 处理才可合并。

## 来源与失败证据（作者报告，不是本 session 重跑）

唯一顺序来源：原树 `.superpowers/cluster-cf02/boundary-order-proposal.json`，SHA256 `e3930f29d3ce1f69c4df1d5067734bb334b5cb67b7fc3ac9cea8457070ac2104`。原树绝对位置 `/Users/samuelzhang/.codex/worktrees/cluster-cf02/game_design`。同时消费同目录 `boundary-report.json`、`boundary-inputs.json`、`failure-inventory.json`、`checkpoint.json`；不读取产品 diff 重新设计或审查。

冻结 selector：输入 `19bd7a5b9deb50a1bb1820aac2348e9e20adb8400484d1e3ab6e0729da2fbfb5`，437 scripts / 4504 tests：4443 pass、55 fail、6 risky/pending，exit 1，runtime gate FAILED。当前 boundary manifest `9d4dfef057c6ad131ec0f7aa5b7f3ae68e028ea74da24bec0e7f675426a26ee3`，报告称 runtime 未变；不是新 PASS。

- 真实 defeat 日内撤退：8合法 rows/0 overlap → 同身份8 rows/3 overlap；需要 swept planner 与 march/battle 接线，扩大 fixture 不证明通过。
- 未改原道路 `test_enemy_invasion`：12 tests / 11 pass / 1 fail，496次准入拒绝；旧 anchor/circle 路径使新身体重叠，不能降低 admission 或模型半径。
- fresh 当前 campaign 无 body_store：迁移首次造 nonbattle bodies 后 horse overlap，实际 save/load 失败；需明确 storage 与 initialization 边界。
- 其他失败仍含 UNKNOWN 和级联；不得统称 fixture-only。候选 reserve cancellation 的 zero ranged power 遮挡/eligibility 尚未闭合。55 failures 与6 risky/pending全部继承，早期局部 PASS 不覆盖最终红灯。

## 原作者逐步建议合同

以下文件仅为 PROPOSED scope，不是所有权申请或登记。新脚本/测试的 `.gd.uid` 归对应步骤；现有批准 Task 的红绿测试、手算、回归与收尾检查仍保留，改动只按 plan 的暂存映射提议。每一步先锁定确切入口合同/测试，再红灯、最小实现、绿灯及旧生产回归，最后独立 PR。依赖必须先 merged+accepted；共享文件串行。新激活占位 `PROPOSED-CF-ACTIVATION` 未登记、owner 未分配。

### CF02 passive foundation (proposed revised acceptance)

提议文件：

- `scripts/engine/unit_bodies.gd`
- `scripts/engine/unit_bodies.gd.uid`
- `scripts/engine/game_state.gd`
- `scripts/engine/data_repository.gd`
- `scripts/engine/guide/cluster_formations.md`
- `scripts/engine/guide/battle_groups.md`
- `scripts/engine/CLAUDE.md`
- `data/army/unit_footprints.csv`
- `data/tables.csv`
- `tests/engine/test_unit_bodies.gd`
- `tests/engine/test_unit_bodies.gd.uid`
- `tests/categories.json`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

rows/footprint/home_slots are pure queries; ten homes and exact ceil(fit/100), fixed measured footprint, stable nonreused slots, integer path/facing. Explicit candidate migration and transfer operations never publish running state; migration validates existing saved poses without manufacturing missing world placement. Missing-pose initialization is a separate explicit placement request. Keep current production Game load/save version and lifecycle wiring until activation.

源验收：

Hand counts 1000/901/900/1/0; survivor identity and fixed footprint; candidate enter/merge/exit/cancel including null repo; exact JSON/path preservation; corrupt/future/overlap rejection leaves candidate source and file unchanged; frozen transaction no replay. Actual baseline fresh campaign save/load and selected regressions remain runnable. This revises original CF02 production integration acceptance and cannot be declared equivalent without approval.

### CF03 pure planner

提议文件：

- `scripts/engine/body_motion.gd`
- `scripts/engine/guide/cluster_formations.md`
- `tests/engine/test_body_motion.gd`
- `data/battle/balance.csv`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

Existing planned BodyMotion.plan/commit signatures; explicit candidate state only; full relative swept capsules, conservative rotation, deterministic yield, integer paths and idempotent saved cursor; commit validates atomically.

源验收：

Opposing/crossing paths, rotation, narrow passage, stall, order permutation, JSON replay, actual path <= budget and invalid plan leaves state/RNG unchanged. Production call graph unchanged.

### CF04a staged march binding

提议文件：

- `scripts/engine/army_system.gd`
- `scripts/engine/tick_engine.gd`
- `scripts/engine/day_resolution.gd`
- `scripts/engine/guide/regiments.md`
- `tests/engine/test_body_marches.gd`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

Explicit candidate march transaction accepts initialized valid bodies, publishes anchor/rows/budget/supply together; ordinary/crown/foe/withdrawal and prediction reuse this transaction. Keep ordinary production dispatch on existing route until activation; candidate route has no second budget writer.

源验收：

Crossing/interception sweep, repeated substep/cursor/JSON no replay, legal retreat; army-clearance and saved-march regression. New-game coverage here requires initialized candidate setup, not a claim of real boot integration.

### CF04b staged placement binding

提议文件：

- `scripts/engine/army_ground.gd`
- `scripts/engine/army_split.gd`
- `scripts/engine/enemy_ai.gd`
- `scripts/engine/guide/regiments.md`
- `tests/engine/test_body_placement.gd`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

Explicit placement candidate for camp/leave/recruit/enemy/split/reconcile; equipment resolved before occupancy, home slots plus planner produce legal poses; lack of space waits or returns reason without publication. No implicit placement in migration.

源验收：

Production radii and real campaign inputs, ten full homes at full strength, conservation and stable slots, no whole-unit friendly wall, no teleport; ground/seat/enemy-spawn regressions. Existing production spawn calls unchanged until activation.

### CF04c staged render consumer

提议文件：

- `scripts/map3d/map3d_battle_groups.gd`
- `scripts/map3d/map3d_layer_units.gd`
- `scripts/map3d/map3d_formation.gd`
- `scripts/map3d/CLAUDE.md`
- `tests/map3d/test_body_paths.gd`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

Explicit physical-row consumer reads committed path/cursor through approved projection, never hidden enemy paths or Game autoload; existing ordinary map dispatch remains until activation. Exact existing map topic guide path must be resolved at registration; proposed new guide path is not authorized.

源验收：

L-path interpolation, 0/1/9/10 identities, transfer continuity, no simulation dependence on camera/fps; real-window candidate scene near/far pause/1x/4x, continuous crossing/turning and performance. Final live-world visual acceptance repeats at activation.

### CF05 staged battle binding

提议文件：

- `scripts/engine/battle_groups.gd`
- `scripts/engine/battle_charge.gd`
- `scripts/engine/battle_task_system.gd`
- `scripts/engine/battle_merge.gd`
- `scripts/engine/battle_system.gd`
- `scripts/engine/guide/battle_groups.md`
- `scripts/engine/guide/battle_charge.md`
- `scripts/engine/guide/battle_merge.md`
- `tests/engine/test_body_battle_motion.gd`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

Candidate start/discover/merge/manoeuvre/retreat/end/cancel transfer through a single transaction and swept planner. translate/follow_anchor candidate route only accepts valid plans. Keep original production battle dispatch intact until activation; no automatic refresh materialization.

源验收：

Real road candidate creates contact through legal approach; defeat candidate cannot create overlap; charge/flank/withdrawal full sweep, one shared day budget/runup, terms and bilateral merge conservation, saved receipts/cursor no replay. Guide filenames must be checked against actual indexed guides before registration.

### CF06 staged damage binding

提议文件：

- `scripts/engine/battle_groups.gd`
- `scripts/engine/battle_ranged.gd`
- `scripts/engine/battle_system.gd`
- `scripts/engine/battle_strength.gd`
- `scripts/engine/guide/battle_groups.md`
- `scripts/engine/guide/battle_ranged.md`
- `data/battle/balance.csv`
- `tests/engine/test_physical_damage.gd`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

Physical candidate melee_counts and clear_shot use actual exposed contact and complete friend envelopes; no reserve damage fallback on physical route. Existing production damage route stays paired with old production movement until final switch.

源验收：

Hand-computed 100 engaged/900 unengaged and last single person; no contact => zero damage, range +/-1m, occlusion and protected targets, translation invariance. Resolve current zero-ranged-power failure by real eligibility/geometry evidence; do not alter measured R or silently retune range. CF06 is a final-switch dependency because actual physical spacing must produce playable legal contact/fire.

### Final production activation (new separately registered bounded step; proposed only)

提议文件：

- `scripts/engine/game_state.gd`
- `scripts/engine/unit_bodies.gd`
- `scripts/engine/military_reorganization.gd`
- `scripts/engine/army_system.gd`
- `scripts/engine/tick_engine.gd`
- `scripts/engine/day_resolution.gd`
- `scripts/engine/army_ground.gd`
- `scripts/engine/army_split.gd`
- `scripts/engine/enemy_ai.gd`
- `scripts/engine/battle_groups.gd`
- `scripts/engine/battle_charge.gd`
- `scripts/engine/battle_task_system.gd`
- `scripts/engine/battle_merge.gd`
- `scripts/engine/battle_system.gd`
- `scripts/engine/battle_ranged.gd`
- `scripts/engine/battle_strength.gd`
- `scripts/engine/guide/cluster_formations.md`
- `scripts/ui/game.gd`
- `scripts/map3d/map3d_battle_groups.gd`
- `scripts/map3d/map3d_layer_units.gd`
- `scripts/map3d/map3d_formation.gd`
- `tests/engine/test_unit_bodies.gd`
- `tests/engine/test_body_marches.gd`
- `tests/engine/test_body_placement.gd`
- `tests/engine/test_body_battle_motion.gd`
- `tests/engine/test_physical_damage.gd`
- `tests/map3d/test_body_paths.gd`
- `tests/engine/test_defeat.gd`
- `tests/engine/test_enemy_invasion.gd`
- `tests/engine/test_battle_save.gd`
- `tests/engine/test_battle_task_combat.gd`

源入口合同（保留作者原文；未给确切候选签名处待原负责方确认）：

Wiring-only switch once staged functions pass: new game placement before world publication; runtime all movement/placement/contact/damage/render writers switch together; lifecycle transfers before deletion; load on candidate with validated version/frozen transaction. Existing saved poses retain exact legal points; overlapping existing poses rejected without repair. Missing legacy nonbattle poses must be explicitly classified and initialized via proven placement on load candidate, or fail with a clear reason; fresh current-campaign roundtrip must succeed. Original save file and current running state unchanged on any failure. No omitted migration path or permanent fallback.

源验收：

Real current campaign boot/save/load, military reorganization, actual defeat continuation and unedited road interception pass with CF01 production radii; full-strength ten visible figures, fixed footprint at all strengths, full-motion nonpenetration in real window, actual spawn/contact/fire; frozen/resume/cost/personnel/slot conservation and fail-closed publication. Run final affected selector with runtime gates and required current-HEAD CI/review. Inherited 55 failures all classified and resolved, no exclusions/threshold changes. If this ceases to be wiring-only, stop and split design/implementation before registering; do not make a large catch-all PR.

## Guide 路径核对与未决接口

只读核对现有索引：`scripts/engine/CLAUDE.md` 索引 `guide/regiments.md`、`guide/battle_groups.md`、`guide/battle_charge.md`、`guide/battle_merge.md` 和 `guide/battle_ranged.md`；以上清单已把源建议的 charge/merge/ranged 简称解析为这些实际路径。`scripts/engine/guide/cluster_formations.md` 是 CF02 提议新增文件，仍须由 engine CLAUDE 索引。map3d 当前身体绘制规则在 `scripts/map3d/CLAUDE.md`，没有 indexed cluster_formations topic，故使用现有 CLAUDE 路径，不提交假 topic。若之后需要拆 guide，先取得路径授权/登记，不能自动增加本次 scope。

源建议保留 `UnitBodies.rows/footprint/home_slots/migrate`、`BodyMotion.plan/commit` 及既有外部入口签名；但 march/placement/render/battle/damage 的显式候选入口确切名称、参数、返回值与“普通入口不可达”测试尚未给出。请原负责方在获准验收拆分后确认：候选迁移与 missing-pose 请求如何区分？候选调用如何不触及生产发布/版本？现有外部入口最终如何一次切换？这些缺口使本文不能直接启动实施，不由文档作者设计答案。

## 待人类明确决策

1. 是否批准有限 passive/candidate staging 例外及 plan 的 CF02–06 暂存映射，同时保留全部最终验收？原 CF02 原 acceptance 和 ownership 在明确合法处理前仍有效、blocked。
2. 怎样从保留 WIP 提取 passive foundation，现有 fixture 改动怎样保留/归属？拒绝过的额外12测试文件仍未授权，`test_enemy_invasion.gd` 在这里只是未来激活提议。
3. missing legacy nonbattle pose 与 malformed/missing required rows 的 schema 分类、显式初始化或拒绝政策是什么？必须保留合法原位旧档、非法档 fail closed、冻结事务、版本兼容和新当前战役 roundtrip。
4. 是否批准新依赖图；激活正式 ID、owner/pair、原 CF02 延后生产 acceptance 的归属如何处理？不得第二次启动或替换 CF02 owner。
5. 是否需先进一步拆分激活？它只可接线，若算法/实现尚未就绪就停止，不能成为大 feature PR。精确候选 API、tests、scope 与 shared guides 要在每步登记前确认。
6. 人类批准后由授权规则步骤与合法 registry 流程处理 acceptance/claims，再登记唯一派工方、依赖、文件、worktree、branch、owner、Review；本文不提供该授权，不直接写 registry，不 terminal CF02，也不派产品后继。

## 端态保全与文档验收

十兵人、固定占地、全过程身体扫掠及让行、实际生成/接敌/直接射击、军法/通信/成本、八种集群及自动行为、单一身体权威、保存/确定性、真实窗口视觉与性能验收全部保留。具体激活补验与 fail-closed 发布清单在 plan；后续 CF07–26 的任务不因 staging 删除。CF01 17采样及炮兵步兵替代限制继续披露，不能称完整动画/真实炮模型已验收。

本 doc PR 验收只含：源建议 SHA 匹配、上述证据如实保持 FAILED/UNKNOWN、原批准 task 正文不被替换、guide 路径核对、纯文档 selector/harness/config/guide/whitespace 检查及当前 HEAD CI/唯一 Review。没有运行 Godot、产品视觉或性能，不为未实现入口造 PASS。文档 Review 只审本 PR 的来源、依赖、端态保全与 CI；不审原 CF02 产品、不编辑、不派工。CI 绿也不自动 merge，等待人类明确批准 staging/ownership 处理。

## 派工方补充的登记约束（非产品建议）

现有 `record_terminal` helper（`.codex/hooks/task-handover.md`）允许原 step owner 在明确人类授权下封存 superseded / unmerged，不要求已有 PR；但不能直接改写 CF02 不可变 acceptance。拟议合法路线：原 owner 先保全37 WIP/失败/输入证据，再本人用 helper 封存旧 CF02，保留原身份、owner、完整 previous_step 与未完成事实，仅释放活跃 claims。修订子步骤使用新 step IDs 和新固定 pair，依赖新被动基础的实际 accepted merge，不能以旧 CF02 为 accepted 依赖，也不复用结束的原 session 拥有另一 step。这样保留历史，并非更换旧 step owner。源建议中的 owner 归属问题仍须在这些规则内由人类决定。其他路线若需修改不可变 acceptance，现有 helper 不支持，必须先有独立合法规则处理。此草案不执行封存、释放、acceptance 改写或派工。
