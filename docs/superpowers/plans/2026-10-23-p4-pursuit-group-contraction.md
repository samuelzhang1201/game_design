# P4 Pursuit Group Contraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow one implementation/unique Review per PR; no subagents or extra reviewers.

**Goal:** Bound the complete physical pursuit deployment by its received region and remaining route distance, contracting or holding before further offensive movement would cross either limit.

**Architecture:** Extend the authoritative physical groups and validated movement from [narrow deployment and reserves](2026-10-23-p4-narrow-deployment-reserves.md). Reuse received pursuit receipts, `MarchPath.region_exit`, actual-route clipping, `bounded` transitions and ordinary defensive contact. Contraction is bounded travel to an inside layout, never coordinate clamping or cancellation of real contact.

**Tech Stack:** Godot4.7, typed engine-pure GDScript, CSV tuning, integer JSON state, GUT/SuiteData.

**Spec:** [Unit behavior and battlefield design](../specs/2026-10-17-unit-behavior-and-battlefield-design.md) §7–9/12/14; `scripts/engine/guide/battle_deployment.md`, `regiments.md`, `battle_merge.md`.

## Global Constraints

- “区域限制约束整条路线及组级部署，而非只检查单位中心。” Test full group footprints and their complete swept routes, including holes and live province changes.
- “距离和区域同时设置，先达任一限制就停止并驻防。” The earlier actual limit wins; no overshoot from rounding.
- “新同义命令不清零累计距离；只有真正的新追击任务建立新起点。” Preserve canonical battle/target/bounds continuity through reissue and merge.
- “触及边界仍在接战时停止主动推进并防御/组织脱离，不瞬移脱战；在区域内无展开空间就提前收缩。” A target allocation cannot itself move rows.
- “限制不阻止被真实攻击时自卫，也不赋予追击免疫。敌军重入范围不会自行重启已完成任务。” Defensive contacts and incoming losses remain physical.
- “搜索不读隐藏位置来挑方向。” Reuse the observer's saved known-target/search rules; no new tracking trajectory or hidden enemy input.
- Retain N0–N2's whole-metre paths, CSV spacing/depth/budget/contact/reserve factors, one transaction/day writer, pending-round freeze, engine purity, costs and lawful received command authority. No animation/scene/camera-based simulation.

## Review Focus

1. RF1 — anchor inside but a group edge or intermediate leg outside: contract or stop before crossing, even with two inside endpoints (R1).
2. RF2 — no room to contract, blocked inward path, or newly excluded occupied group: hold actual positions and defend; never snap away (R1).
3. RF3 — distance and region disagree, detours/rounding or reserve entry spend metres: earliest limit stops all further offensive travel without multiplying the budget by group count (R2).
4. RF4 — still touching an attacker at the bound: retain actual contact/incoming losses, hold instead of pursuing, and never reactivate on target return (R1/R2).
5. RF5 — JSON/failed personnel commit/alias reissue/merge while contracting: preserve saved path, receipt, accrued metres and consumed day (R1/R2).

## Delivery and current baseline

Dependency DAG: `accepted planning PR → N0 → N1 → N2 → R1 → R2`; N tasks are defined in the companion plan. All runtime nodes overlap `scripts/engine/battle_groups.gd` and the deployment guide, so none may run concurrently. Each has a new worktree/`codex/p4-<step_id>` branch/PR and exactly one implementation/Sol-low and one unique Review/Sol-medium pair, assigned once by dispatcher chat `01a15959-7582-7233-9637-1f0f9d090d70` after checking current ownership and accepted prerequisites. Escalate complexity only within the pair. Review merges only after actual required current-HEAD checks and applicable acceptance; it never creates successors. Dispatcher alone continues already authorized work, without a new permission question.

At `2158dbeb`, `pursuit_walk` already clips complete field polylines; `credit_pursuit` already saves `bounded`, clears route/departure and retains current ID. `MarchPath.region_exit` already handles holes, live manor province and inside-endpoint excursions. `engaged_counts` already excludes outside-region pursuit contact while retaining attacked self-defence; pending actions already freeze `pursuit_region`. These are regression inputs, not new deliverables. PR160 already records flank interception and pauses the original warrant without changing its target; this plan does not extend or duplicate it.

## Shared contracts and test setup

Consume N1's `BattleGroups.targets(repo: DataRepository, state: GameState, battle: Dictionary, code: String, region := "") -> Array[Dictionary]`, `move_row(repo: DataRepository, state: GameState, battle: Dictionary, code: String, slot: int, path: Array, budget: int) -> Dictionary` and N2's `fill_vacancies(...)`/remaining row budgets. Saved `battle.groups[code]` rows retain stable integer `slot`, actual coordinates, role and optional integer `path_m/target_m`. Persist additions inside existing battle/task dictionaries; no new top-level save field or serializer.

New tests define local `_fixture()` from `SuiteData.repo()/campaign()` with sorted unit/province codes and `Personnel` helpers, following `test_pursuit_route_bounds.gd`. Use its synthetic U/hole geometry and live `state.manor_province` changes; convert metre polygons with `ArmySystem.metres_to_pack`. Pin test balance values locally and clear changed MarchPath/MapEconomy caches after each test. Assertion snippets denote measured locals from production execution. Every new movement query is pure until explicit commit; preview state/RNG hashes must match before/after.

For each task execute red→minimal implementation→targeted green→commit. Commands are separate `./run_tests.sh --test <path>` invocations. Use the project's shared Godot lock resolved from the dispatcher checkpoint before running Godot, never concurrent heavy processes. At final frozen inputs run `./run_tests.sh --category engine-military` once and `./run_tests.sh --test tests/engine/test_engine_isolation.gd`; record commands, exit codes and input hashes. CI `harness-checks` plus `gut-tests` must pass on actual HEAD, with selection explicitly showing what ran. No routine full/balance/gameplay sweep is needed for these bounded contracts.

### Task R1: Constrain tactical group routes and contract at the region edge

**step_id:** `p4-pursuit-region-contraction`; depends on accepted N2.

**Files:**
- Modify: `scripts/engine/battle_groups.gd` — region-aware target/travel and inward contraction for ordinary deployment, reserve entry and rigid moves.
- Modify: `scripts/engine/battle_task_system.gd` — one shared bounded transition, tactical pursuit gate; preserve same-meaning receipt state.
- Modify: `scripts/engine/battle_charge.gd` — constrain a pursuit charge's physical group sweep before charge credit.
- Modify: `scripts/engine/guide/battle_deployment.md` — region contraction/hold/defence rule.
- Create/Test: `tests/engine/test_pursuit_group_contraction.gd`.
- Modify/Test: `tests/engine/test_pursuit_bounds.gd`, `tests/engine/test_pursuit_route_bounds.gd` (only connected assertions).

**Interfaces:**
- Consumes existing `current(state: GameState, unit: String) -> Dictionary`, `pursuit_walk(repo, state, unit, entry, here, path, step) -> Dictionary`, `credit_pursuit(repo, state, unit, metres, boundary_reason := "") -> bool`, `MarchPath.region_exit(repo: DataRepository, state: GameState, here: Vector2i, path: Array, region: String) -> float`.
- Produces `BattleTaskSystem.bound_pursuit(repo: DataRepository, state: GameState, unit: String, reason: String) -> bool`: extract `credit_pursuit`'s existing terminal transition/route cleanup without adding metres; a received pursuit becomes bounded once, preserving current ID/contact/position. Repeated calls are inert.
- Produces `BattleGroups.pursuit_region_step(repo: DataRepository, state: GameState, battle: Dictionary, code: String, path: Array, budget: int, slot := -1) -> Dictionary`: pure `{path:Array, reason:String, contracting:bool}`. `slot=-1` validates a rigid whole-unit translation; otherwise validates that row's full footprint. Empty path means wait, never permission to fall back to an unclipped target. No task/position/RNG mutation.

- [ ] **1. Write failing tests** `test_inside_anchor_outside_group_contracts`, `test_swept_footprint_cannot_leave_region`, `test_blocked_contraction_keeps_contact`, `test_region_change_does_not_teleport`, `test_bounded_pursuer_can_be_attacked`.

```gdscript
# Region rectangle x0..300,y0..200; spacing20 => footprint half-width10.
# Anchor(250,100), two rows initially(250,185),(230,100).
assert_eq(actual_before_plan, actual_after_plan) # pure planning
assert_lte(max_committed_footprint_y, 200)
assert_eq(outward_move_from_centre_y190_to_y195, 0)
assert_eq(blocked_inward_points_after_day, blocked_inward_points_before_day)
assert_eq(task_after_no_legal_layout.status, "bounded")
assert_eq(task_after_no_legal_layout.request.target_unit, original_target)
assert_eq(BattleSystem.unit_action(repo, state, battle, a).kind, "hold")
assert_eq(BattleGroups.engaged_counts(repo, state, battle, a).x, 50)
assert_gt(incoming_loss_while_bounded, 0)
assert_eq(groups_after_failed_personnel_retry, frozen_groups)
```

Use actual saved groups, not a centre-only test. In the rectangle a requested centre y195 would put its edge at205; contract toward an inside row target before advancing. Add an outside-start case by receiving a narrower region or changing a live manor province: retain that group's physical point and defensive contact, block offensive participation, permit only a clear inward path; no retroactive promise that a changed border teleported the men inside. Add a U/hole case with endpoints inside but the swept footprint outside, a disconnected inside pocket and a friendly blocker on the inward route. No legal complete layout or no reachable contraction means the pursuit terminates bounded with a reason and stays physically exposed. Terminal bounded permits lawful inward defensive reorganization but no outward chase or renewed charge approach. Region-free and actual withdrawal paths remain unchanged. If protected withdrawal/surrender/loss of capacity bars attack, that gate still precedes movement. Repeat with a reserve path and a charge sweep to close alternate writers.

- [ ] **2. Run red:** `./run_tests.sh --test tests/engine/test_pursuit_group_contraction.gd`; baseline accepts a centre-inside/group-edge-outside deployment or lacks tactical clipping.
- [ ] **3. Implement:** pass the received active pursuit region into N1 target allocation and every offensive tactical sweep; check each footprint corridor using the same edge/end-cap geometry as N1, with `region_exit` on each path segment. Prefer a feasible narrower inside layout, with overflow remaining rear, and spend normal movement budget to reach it. Persist the inward path in existing row fields; mark no contact removal just because a target changed. If the full footprint cannot advance or contract, call `bound_pursuit` at the last safe physical position. Do not reactivate a bounded/search-failed task, inherit a side attack or redirect toward an interceptor. `pending_round` freezes both contraction and its decision until commit; existing `pending_round.unit_actions` stays authoritative. Self-defence and actual withdrawal use existing legal paths and casualty contexts.
- [ ] **4. Run green:** contraction tests, `test_pursuit_bounds.gd`, `test_pursuit_route_bounds.gd`, `test_pursuit_merge_continuity.gd`, `test_reserve_entry.gd`, `test_charge_runup.gd`, `test_flank_destination.gd`, `test_battle_task_combat.gd`, then shared checks. Acceptance: all tactical writers honor complete region geometry; holding retains incoming harm and real contacts; no redundant field-route algorithm.
- [ ] **5. Commit:** `git add scripts/engine/battle_groups.gd scripts/engine/battle_task_system.gd scripts/engine/battle_charge.gd scripts/engine/guide/battle_deployment.md tests/engine/test_pursuit_group_contraction.gd tests/engine/test_pursuit_bounds.gd tests/engine/test_pursuit_route_bounds.gd` then `git commit -m "feat: contract pursuit groups at their received region edge"`. Publish own PR, hand off once, stop.

### Task R2: Share the remaining route budget with physical tactical travel

**step_id:** `p4-pursuit-group-distance`; depends on accepted R1.

**Files:**
- Modify: `scripts/engine/battle_groups.gd` — clip/credit committed row movement once, stop further offensive rows when first bound is reached.
- Modify: `scripts/engine/battle_task_system.gd` — saved tactical distance high-water, canonical reissue continuity and shared clipping/credit.
- Modify: `scripts/engine/battle_charge.gd` — actual allowed pursuit translation receives identical accounting before run-up credit.
- Modify: `scripts/engine/guide/battle_deployment.md` — route accounting semantics.
- Create/Test: `tests/engine/test_pursuit_group_distance.gd`.
- Modify/Test: `tests/engine/test_pursuit_merge_continuity.gd`, `tests/engine/test_pursuit_group_contraction.gd`.

**Interfaces:**
- Consumes R1 region constraint/terminal transition and existing field `pursuit_walk/credit_pursuit`, N1 actual walked row polyline and remaining budgets. No changes to public `BATTLE_TASK` params, paid dispatch, courier receipt or ArmySystem APIs.
- Produces `BattleTaskSystem.group_pursuit_walk(repo: DataRepository, state: GameState, unit: String, slot: int, here: Vector2i, path: Array, budget: int) -> Dictionary`: pure same walk keys as `pursuit_walk`, clipping that row's real polyline to region and remaining group allowance.
- Produces `BattleTaskSystem.credit_group_pursuit(repo: DataRepository, state: GameState, unit: String, slot: int, metres: int, boundary_reason := "") -> bool`: after one actual committed move, update only the current received pursuit, then use `bound_pursuit` for the first limit.
- Extend received `record.pursuit` with `field_m:int`, `group_route_m:Dictionary` (string slot → cumulative tactical metres), `group_high_m:int`. Existing `route_m = field_m + group_high_m`; `group_high_m` is the nondecreasing maximum cumulative path of any group, retaining retired slots. Different groups moving together never multiply distance by personnel/group count. Legacy receipts migrate lazily with `field_m=old route_m`, empty group map/high0; read-only previews derive defaults without writing. All these fields are copied on same-meaning receipt, including after alias canonicalization; new meaning resets them with the existing new pursuit start.

- [ ] **1. Write failing tests** `test_tactical_detour_spends_real_route`, `test_two_groups_do_not_double_charge`, `test_first_region_or_distance_wins`, `test_json_alias_retry_keeps_contraction_budget`.

```gdscript
# Existing field walk400; row starts(90,100), walks30north then40east
# to(130,130): tactical70, combined470, displacement50.
assert_eq(progress_after_detour.route_m, 470)
assert_eq(progress_after_detour.group_high_m, 70)
# Second row takes60, then20; maxima70 then80, never70+60+20.
assert_eq(route_after_second_row_60, 470)
assert_eq(route_after_second_row_next_20, 480)
# max_route500: first row can add30, not the whole budget100.
assert_eq(first_row_stop, Vector2i(160, 130)) # from(130,130), +30x
assert_eq(progress_at_stop.route_m, 500)
assert_eq(task_at_stop.status, "bounded")
assert_eq(later_offensive_row_points, later_offensive_row_points_before_stop)
# Parallel rigid translation80 of two groups means480, not560.
assert_eq(route_after_parallel_translation, 480)
assert_eq(retry_state.to_dict(), uninterrupted_state.to_dict())
assert_eq(same_meaning_reissue.pursuit, previous_pursuit)
assert_eq(new_meaning_reissue.pursuit.route_m, 0)
```

For independent first-bound fixtures begin at field400 and group_high0, path `(100,100)→(200,100)`, region safe footprint ends at x160: with max450 stop x150/distance450; with max500 stop x160/region460. Test diagonal inward rounding at remaining250: displacement `(176,176)` lengthceil249 is allowed, `(177,177)` exceeds250. Test ordinary step followed by reserve entry uses only the remaining daily budget and credits once; charge movement earns only actual allowed run-up. Actual withdrawal spends no offensive pursuit budget. Empty/no-fit groups do not fabricate distance, and `max_route_m=0` stays distance-unbounded while region remains effective.

Repeat mid-contraction through `GameState.to_dict`→JSON→`from_dict`, same day retry, forced personnel-write error with saved pending round, both merge side orientations, canonical alias reissue arriving after another real step, and target return after bounded. Assert physical rows/paths, current ID/reason, `route_m`, RNG and frozen actions match the uninterrupted branch. Late/pending/cancelled/replaced warrants must neither credit nor revive the old task. A genuinely new target/region/max distance retains existing fresh-start behavior; no special retry action or added cost.

- [ ] **2. Run red:** `./run_tests.sh --test tests/engine/test_pursuit_group_distance.gd`; expect missing tactical credit/overshoot assertions.
- [ ] **3. Implement:** use max cumulative group travel rather than the sum or mean: per-row allowance is `max_route_m - field_m - group_route_m[slot]`; global remaining remains `max_route_m - route_m`. A lagging group may catch up to the same travelled extent without giving the leading group extra range. Stop the whole pursuit at the first committed limit, so later rows cannot continue offensive moves that day. Field `credit_pursuit` increments `field_m` and recomputes `route_m`; group credit raises that slot and the high-water. Contraction/rear-entry detours count while the pursuit is received; terminal defensive reorganization and actual withdrawal do not. Share R1 region tests with this distance clip and choose earlier actual route limit; tie uses existing region precedence. Sum integer traversed leg lengths using the existing ceil/inward-rounding convention, not displacement or target length. Save physical move and its credit in the same existing daily transaction; previews/retries cannot repeat either. The battle aliases already preserve tasks: retain their new nested progress without resetting it or synthesizing another delivery.
- [ ] **4. Run green:** group distance/contraction tests, `test_pursuit_route_bounds.gd`, `test_pursuit_merge_continuity.gd`, `test_pursuit_bounds.gd`, `test_reserve_entry.gd`, `test_battle_save.gd`, `test_charge_runup.gd`, `test_battle_task_dispatch.gd`, then shared checks. Acceptance: hand-derived470/480/500 and earlier450/460 stop, max-route monotonicity, same-meaning continuity, actual incoming damage at the stop and zero extra calls/costs.
- [ ] **5. Commit:** `git add scripts/engine/battle_groups.gd scripts/engine/battle_task_system.gd scripts/engine/battle_charge.gd scripts/engine/guide/battle_deployment.md tests/engine/test_pursuit_group_distance.gd tests/engine/test_pursuit_merge_continuity.gd tests/engine/test_pursuit_group_contraction.gd` then `git commit -m "feat: bound physical pursuit group travel by route distance"`. Own PR/unique Review/stop; no successor creation.

## Acceptance ownership and self-review

R1 owns actual region/footprint contraction and exposed self-defence; R2 owns combined distance/region accounting and reissue/merge/retry proof. Each eventual pair runs local `visual-review` for changed geometry: real windows at800/1000/10000, narrow boundary, rear entry, contact at boundary, and returning enemy at1/2/4x. No editor asset tuning is implied. If current views do not consume these saved rows, record that concrete consumer gap for dispatcher-owned follow-up; do not claim visual acceptance from headless engine tests. Cloud work leaves the local pass open. This planning-only PR performs no runtime or visual acceptance.

Self-review: §9 route/region/bounded/search defaults are reused, remaining group geometry assigned to R1, tactical metres to R2; §7/8 capacity/admission supplied by N0–N2. All five review-focus cases map to named tests. Signatures/keys match the companion plan; saved additions are integer dictionaries/pairs; no speculative direction search, hidden truth, public action or new rendering system. Baseline route tests remain meaningful and are not reclassified as new implementation. Geometry and whole-metre numbers are explicit test inputs; art spacing remains CSV/editor acceptance, not a claimed verified historical measurement.
