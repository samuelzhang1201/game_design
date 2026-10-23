# P4 Narrow Deployment and Reserve Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Repository rules override subagent workflows: one implementation session and its sole Review per PR; no nested agents.

**Goal:** Let actual passable frontage bound deployment, retain physical rear groups, and commit reserves only after a real route reaches a vacant fighting position.

**Architecture:** Keep `battle.groups` authoritative rather than regenerating positions at every query. Add terrain-constrained target allocation and bounded group travel to `BattleGroups`; use the existing contact and strength writers. No new clock, combat multiplier, player action or personnel ledger.

**Tech Stack:** Godot 4.7, typed GDScript/RefCounted, whole-metre JSON state, CSV tuning, GUT/SuiteData.

**Spec:** [Unit behavior and battlefield design](../specs/2026-10-17-unit-behavior-and-battlefield-design.md), §6–8 and §12/14. Read `scripts/engine/guide/battle_deployment.md`, `battle_charge.md`, `battle_merge.md` and `regiments.md` before editing their owners.

## Global Constraints

- “引擎保存最多50人组的真实人数、职责、整数阵位/路径、面向、投入情况与合法接触关系”. Retain `battle_group_size`; every unit's group counts sum to its fit personnel, never rounded into extra strength.
- “正面空间有限，后排不能隔着友军全额输出；预备队进入有效位置后才投入。” Actual contact, not assignment or an animation, controls output.
- “密集友军中等待、绕行或依次补位，不穿人。” Use terrain and swept occupancy for every committed leg.
- “不能同时由旧行军和新战术移动各走一遍”. Keep `deployed_day`, pending-round freeze and the existing day transaction; no per-frame simulation.
- “所有调校数值进入data，静态外观通过编辑器资源制作”. Reuse spacing/depth/deploy-step/contact/reserve CSV keys; the numbers below are synthetic test inputs, not new historical scales or approved art tuning.
- Engine-pure, seeded determinism, integer saved coordinates, existing costs/received authority/laws, one JSON and reason-bearing task transitions remain binding. No Node, `Game`, wall clock or new RNG draw.
- Already merged at baseline `2158dbeb`: d1 groups, d2 line targets, d3 external clearance, contact/reserve strength, charge run-up, ranged fire, region eligibility, flank routing and PR160 interception. Do not reimplement these features.

## Review Focus

1. RF1 — zero/partial groups and loss/recruitment across 50: conserve exact people without refreshing survivors to new positions (N0).
2. RF2 — narrow, blocked and disconnected terrain: extra troops deepen or wait at their actual rear positions, never widen through water (N1).
3. RF3 — a vacancy behind another friendly group: waiting and detouring must precede promotion; no teleport or extra daily budget (N2).
4. RF4 — contact/output: assigned reserves cannot fight at full strength through a front rank; actual enemy attack still permits defence (N2).
5. RF5 — JSON, failed-round retry, reinforcement and merge: preserve physical positions, movement budgets, charge and received tasks (N0/N2).

## Delivery graph and ownership

`planning PR accepted → N0 → N1 → N2 → pursuit plan R1 → R2`.
Each node is a separate new worktree, `codex/p4-<step_id>` branch and PR from current accepted `origin/main`. The sole dispatcher is source chat `01a15959-7582-7233-9637-1f0f9d090d70`; only it registers/creates implementation sessions after verifying dependencies, active ownership and existing successor records. Neither author nor Review launches successors. Session IDs and absolute checkout paths are recorded at dispatch, never guessed by this plan. Implementation defaults Sol/low, Review Sol/medium; record concrete escalation within that pair if necessary.

All nodes are serial: they overlap `battle_groups.gd` and the deployment guide. The pursuit plan consumes N2's APIs. Do not parallelize by creating alternate branches over shared owners. No helper-only PR: N0 changes saved-position continuity; N1 changes actual terrain deployment; N2 changes real reserve admission.

Scope per task is the literal paths below (new GDScript `.uid` sidecars belong to the same creator). Tests use `SuiteData.repo()/campaign()` and `personnel_helpers.gd`; do not modify shared fixtures, categories, actions, costs, assets, scenes or save infrastructure. If a necessary additional file appears, obtain a recorded scope addition through the dispatcher before editing it.

## Common fixture and verification contract

New tests define their own `_fixture()` returning `{repo, state, battle, a, enemy}` using sorted campaign unit codes and live pack-derived realm/province bindings, following `test_battle_groups.gd`. Use `SuiteData.open_country` for open ground, `MarchPath.build/use` for synthetic land grids, and `Personnel.replace/move` for real fit counts. `after_each` calls `MarchPath.forget()` and clears map caches changed by that test. Set explicit `repo.balance` values locally; no real map-name constants.

Test assertion snippets below name local measured values; each test computes them by invoking the specified production API, not by injecting a fake successful result. For geometry use integer nonnegative points translated into the test grid. Contact is inclusive at reach; friendly occupancy blocks at separation strictly less than spacing, as in `BattleCharge._clear`. A group occupies a spacing-wide footprint: test the centre corridor and both parallel edges at half spacing, plus their end caps, against `MarchPath.clear`; reject closed destination cells even though ordinary march routing can open endpoints. Check raw grid bounds before `cell_of`, which clamps coordinates. A road result `[to]` is not proof of connectivity: validate all returned legs with `ArmySystem.leg_clear` and destination passability.

For every task: first run its explicit new test via `./run_tests.sh --test <path>` and observe its named missing-behavior assertion fail; then implement, rerun it and the listed regressions. Use the project shared Godot lock (resolve the current lock from the dispatcher checkpoint before starting Godot), one heavy Godot process at a time. After convergence run `./run_tests.sh --category engine-military` once on frozen inputs and `./run_tests.sh --test tests/engine/test_engine_isolation.gd`; retain commit/input hashes and output evidence. If a named existing test's expectation changes, update its geometry assertion with a hand calculation, never weaken a gate. Each Review checks actual current-HEAD `harness-checks` and `gut-tests` and all applicable acceptance before merging.

### Task N0: Preserve deployed group positions through refresh and merge

**step_id:** `p4-group-position-continuity`.

**Files:**
- Modify: `scripts/engine/battle_groups.gd` — reconcile counts without re-laying out existing physical rows; rigid movement primitive.
- Modify: `scripts/engine/battle_charge.gd`, `scripts/engine/battle_task_system.gd` — charge/flank moves explicitly translate rows instead of relying on refresh to do so.
- Modify: `scripts/engine/battle_merge.gd` — fold absorbed groups/facing/anchor snapshots before refresh.
- Modify: `scripts/engine/army_system.gd` — synchronize rows after live legacy/saved withdrawal movement, never from a preview.
- Modify: `scripts/engine/guide/battle_deployment.md` — saved physical group contract.
- Modify/Test: `tests/engine/test_battle_groups.gd`, `tests/engine/test_battle_deployment_lines.gd`, `tests/engine/test_battle_merge.gd`, `tests/engine/test_battle_task_retreat.gd`.

**Interfaces:**
- Consumes existing `refresh(repo: DataRepository, state: GameState, battle: Dictionary) -> void`, `layout(...) -> Array[Vector2i]`, `counts(n: int, size := 50) -> Array[int]`.
- Produces `BattleGroups.translate(repo: DataRepository, state: GameState, battle: Dictionary, code: String, movement: Vector2i) -> void`: commit an already validated rigid delta to stored unit anchor and all its groups exactly once. No routing, charge credit or receipt mutations inside.
- Produces `BattleGroups.follow_anchor(repo: DataRepository, state: GameState, battle: Dictionary, code: String) -> void`: compare the current committed anchor to saved `battle.group_anchor_m[code]:[x,y]`, shift physical rows by that delta and update the snapshot, without moving the anchor again. Call after both live ArmySystem march commits (legacy and saved), including foes/withdrawal; never in `_march_one` previews or `_publish_march_state` on private copies. `translate` updates the same snapshot, so a later refresh cannot apply the delta twice.
- Existing row keys `count:int`, `role:String`, `x_m:int`, `y_m:int` remain. Add `slot:int` (monotonic per-unit identity) and optional `path_m:Array` of integer `[x,y]` pairs. Save per-unit next identity in `battle.group_next_slot:Dictionary`; no Vector2/float in saved additions.

- [ ] **1. Write failing tests** `test_refresh_keeps_physical_rows`, `test_count_boundary_keeps_surviving_positions`, `test_merge_keeps_absorbed_rows`.

```gdscript
assert_eq(BattleGroups.counts(0), [] as Array[int])
assert_eq(BattleGroups.counts(51), [50, 1] as Array[int])
assert_eq(counts_after_120_to_101, [50, 50, 1])
assert_eq(counts_after_101_to_100, [50, 50])
assert_eq(surviving_points_after_refresh, surviving_points_before)
assert_eq(points_after_translate_30_40, [Vector2i(230, 240), Vector2i(190, 240)])
assert_eq(anchor_after_translate, anchor_before + Vector2i(30, 40))
assert_eq(absorbed_points_after_merge, absorbed_points_before_merge)
assert_eq(charge_after_merge, charge_before_merge)
assert_eq(task_after_merge.pursuit.route_m, 77)
```

Use two initial rows `(200,200),(160,200)` for the delta check. Test 0/1/49/50/51 and 800/1000/10000 counts, removal of departed members, same-input JSON equality and read-only refresh on unchanged counts. Assert a live withdrawal anchor delta(30,40) moves its saved groups by exactly(30,40), a repeated saved substep does nothing, and previewing it changes neither rows nor the snapshot. Test explicit facing/formation changes: they update desired orientation, not physical coordinates. Legacy saved rows acquire identity in array order; legacy battles without rows seed once with existing `layout`, preserving its current migration contract. New members seed around their actual arrival anchor, never on the battle's destination line.

- [ ] **2. Run red:** `./run_tests.sh --test tests/engine/test_battle_groups.gd`; expect physical-position assertion failure against baseline regeneration.
- [ ] **3. Implement:** reconcile by stable row order with existing `counts` distribution, retaining corresponding saved positions/paths/identity; trim only missing tail rows and append new reserve rows at the current rear continuation of the unit's layout. A changed count is regrouping, not a second casualty writer. Growth never moves existing rows; new rows are rear reserves until N2 admits them. Existing invalid legacy positions are retained as facts and cannot acquire offensive contact through terrain. Ordinary rigid deployment, charge and flank call `translate` after their existing clearance checks; replace their direct anchor writes and keep their budget/phase handling. Preserve `group_facing` on merge; recompute desired facing separately from physical relocation. Pending rounds freeze tactical reconciliation/movement until commit; ordinary physical withdrawal follows its existing transaction, without stale groups left at the old battle line.
- [ ] **4. Run green:** new tests, `test_battle_deployment_lines.gd`, `test_battle_merge.gd`, `test_charge_runup.gd`, `test_flank_destination.gd`, `test_battle_save.gd` via separate `--test` invocations, then common checks. Acceptance: a refresh, casualty boundary, formation change or merge cannot move a surviving group or renew charge momentum; old saves still load.
- [ ] **5. Commit:** `git add scripts/engine/battle_groups.gd scripts/engine/battle_charge.gd scripts/engine/battle_task_system.gd scripts/engine/battle_merge.gd scripts/engine/army_system.gd scripts/engine/guide/battle_deployment.md tests/engine/test_battle_groups.gd tests/engine/test_battle_deployment_lines.gd tests/engine/test_battle_merge.gd tests/engine/test_battle_task_retreat.gd` then `git commit -m "fix: preserve physical battle groups across refresh and merge"`. Publish own PR and hand off once to its unique Review; stop.

### Task N1: Fold actual deployment into reachable terrain capacity

**step_id:** `p4-narrow-deployment-capacity`; depends on accepted N0.

**Files:**
- Modify: `scripts/engine/battle_groups.gd` — pure legal target allocation and ordinary per-group travel.
- Modify: `scripts/engine/guide/battle_deployment.md` — capacity and physical admission rule.
- Create/Test: `tests/engine/test_narrow_deployment.gd`.
- Modify/Test: `tests/engine/test_battle_deployment_lines.gd`, `tests/engine/test_battle_groups.gd` (replace only obsolete regeneration assumptions).

**Interfaces:**
- Consumes N0 rows/translation and existing `deployment(...) -> Dictionary` unit-anchor goals, `BattleFormation.slots(formation: String, figures: int, frontage_permille := 1000) -> Array[Vector2]`, `MarchPath.road/clear`, `MarchRoute.walk`.
- Produces `BattleGroups.targets(repo: DataRepository, state: GameState, battle: Dictionary, code: String, region := "") -> Array[Dictionary]`: one target per saved slot, `{slot:int, x_m:int, y_m:int, role:String}`, or no target for a waiting row. Pure; `region` optionally restricts every footprint and path, used by R1.
- Produces `BattleGroups.move_row(repo: DataRepository, state: GameState, battle: Dictionary, code: String, slot: int, path: Array, budget: int) -> Dictionary`: `{at:Vector2i, path:Array, moved_m:int, arrived:bool}`; commits only clear swept steps, rounds inward to budget. The returned vectors are ephemeral; persist pairs only. Excludes this row from occupancy, includes every other row including own reserves. No second anchor move.

- [ ] **1. Write failing tests** `test_one_lane_adds_depth`, `test_no_legal_front_waits`, `test_disconnected_destination_rejected`, `test_partial_group_uses_one_slot`, `test_seed_and_reinforcement_do_not_snap`.

```gdscript
# spacing=20, depth=20; face +x; legal lane centre y=100 only;
# target front x=200; rear positions are 180,160,140,120,100,80.
assert_eq(front_targets, [Vector2i(200, 100)])
assert_eq(rear_targets_for_101, [Vector2i(180, 100), Vector2i(160, 100)])
assert_eq(group_counts_for_101, [50, 50, 1])
assert_eq(front_count_for_1, 1)
assert_eq(targets_for_0, [])
assert_eq(front_count_when_lane_closed, 0)
assert_eq(actual_after_disconnected_step, actual_before)
assert_eq(actual_after_same_day_retry, actual_after_first_step)
assert_eq(new_member_points_after_join, new_member_points_at_arrival)
```

Build a grid with a dry strip y89..111: a spacing20 footprint centred y100 fits, while an adjacent lane at y80 or120 does not; footprint must fit completely. Add a dry strip y79..121 with two requested lane centres y90/110 to assert two fronts and extra depth, and a closed wall separating an otherwise open target to prove `[to]` fallback is rejected. Initial rows stay at actual rear/arrival positions; targets do not move them. A budget10 step from `(100,100)` toward `(120,100)` reaches `(110,100)`, never the destination. A flank-side rock that closes one candidate reduces width rather than enlarging across it. Repeating with 800/1000/10000 personnel bounds frontage by the same lane count, preserving all people in deeper rows or at their existing waiting points.

- [ ] **2. Run red:** `./run_tests.sh --test tests/engine/test_narrow_deployment.gd`; expect absent `targets`/capacity assertions to fail.
- [ ] **3. Implement:** derive the requested front row from the current formation, existing spacing and line goals. Test contiguous lanes centred on the side's target line in stable centre-out order (negative side first on ties), bounded by requested frontage; never jump a blocked lateral gap to claim another patch as the same front. Allocate sorted units/slots across that side without duplicate targets, then add rear rows at configured depth; terminate at the finite requested number of groups, leaving unreachable rows waiting at their current positions. Apply the same dry-footprint/routed-leg checks to all four shapes; retain their native shape where it fits, fold only overflow behind the legal front. `deploy_day` routes ordinary rows to legal targets using `move_row`, sorted side/code/slot order and each row's one existing daily step budget. `refresh` never snaps to targets. Synchronize the unit anchor to the rounded mean of its actual rows after non-rigid movement; it remains a summary/communication point, never a second writer of travel. Charge/flank keep rigid paths and existing clearance/run-up checks; their blocked deployment cannot force a wider layout. N2 will admit reserves to vacancies; do not change strength here.
- [ ] **4. Run green:** narrow tests, `test_battle_groups.gd`, `test_battle_deployment_lines.gd`, `test_deployment_clearance.gd`, `test_charge_runup.gd`, `test_flank_destination.gd`, then common checks. Acceptance: capacity changes actual targets and bounded travel, no water/scarp crossings or instantaneous narrowing. Existing march exclusion reads actual saved rows through `_deployment_reach/_group_reach`; no replacement whole-unit collision system.
- [ ] **5. Commit:** `git add scripts/engine/battle_groups.gd scripts/engine/guide/battle_deployment.md tests/engine/test_narrow_deployment.gd tests/engine/test_battle_deployment_lines.gd tests/engine/test_battle_groups.gd` then `git commit -m "feat: fold battle deployment into passable frontage"`. Own PR/unique Review/stop.

### Task N2: Admit reserves through a real vacancy path

**step_id:** `p4-reserve-entry`; depends on accepted N1.

**Files:**
- Modify: `scripts/engine/battle_groups.gd` — stable vacancy allocation, per-row route/admission and legal physical contact.
- Modify: `scripts/engine/guide/battle_deployment.md` — admission versus existing whole-unit event reserves.
- Create/Test: `tests/engine/test_reserve_entry.gd`.
- Modify/Test: `tests/engine/test_narrow_deployment.gd` — multi-unit vacancy fixture.

**Interfaces:**
- Consumes N1 `targets/move_row`, N0 saved identities/paths, existing `engaged_counts(...) -> Vector2i` and `engaged_permille(...) -> int`.
- Produces `BattleGroups.fill_vacancies(repo: DataRepository, state: GameState, battle: Dictionary, budgets: Dictionary) -> void`: called inside `deploy_day`; `budgets` maps unit → slot → remaining metres after ordinary movement, never grants a second step. Assigns legal front vacancies to reachable reserves in code/slot order, preserving an existing assignment while legal; paths live in that row's `path_m`, target in optional `target_m:[x,y]`.
- `role=front` only after arrival in a legal unoccupied front slot; `role=reserve` while travelling/waiting. Roles do not immunize a physically attacked reserve; defensive contact can include it, while offensive output still requires admission. Keep `battle.reserves` (event/unit flag) distinct from group roles and preserve its existing round-commit writer.

- [ ] **1. Write failing tests** `test_vacancy_requires_real_entry`, `test_occupied_route_waits_then_advances`, `test_reserve_contact_and_output`, `test_failed_round_and_json_freeze_entry`.

```gdscript
# spacing20/depth20/budget10/contact10/reserve200, fit70=[50,20].
# 50 actually contacting in front,20 behind: floor((50000+4000)/70)=771.
assert_eq(BattleGroups.engaged_counts(repo, state, battle, a), Vector2i(50, 70))
assert_eq(BattleGroups.engaged_permille(repo, state, battle, a), 771)
# Other allied front unit is removed by real Personnel loss; rear group at x160
# takes four budget10 days to reach vacant front x200, all at y100.
assert_eq(rear_x_by_day, [170, 180, 190, 200])
assert_eq(rear_roles_by_day, ["reserve", "reserve", "reserve", "front"])
assert_eq(offensive_contact_before_arrival, 0)
assert_eq(offensive_contact_after_arrival, 20)
assert_eq(blocked_rear_after_day, blocked_rear_before_day)
assert_eq(groups_after_failed_round_retry, frozen_groups)
assert_eq(reloaded_state.to_dict(), uninterrupted_state.to_dict())
```

Use independent fixtures for the771 strength calculation and vacancy travel. In the vacancy fixture use two legal front lanes, one existing front of the reserve unit on the other lane, and a separate allied front on lane y100; eliminate that ally and let the reserve enter its vacated lane. Use separate real allied units for the eliminated-front vacancy, so aggregate casualties do not invent a per-group hit ledger. Add a friendly group on the straight corridor: no crossing it; route around when a passable spacing-wide alternative exists, otherwise wait. Assert each route leg's dry/occupancy check, sum of walked leg lengths ≤ remaining budget, no double movement through ordinary deployment and filling. A touching enemy attack permits reserve self-defence; a withdrawing enemy behind a friendly row does not create pursuit output. Empty/partial reserve, no vacancy, simultaneous reserves (stable winner), new reinforcement and a vacancy erased by enemy occupancy all have explicit role/position assertions. JSON midway, pending personnel-error retry and merge retain assignment/path and consumed day; regrouping does not reset `entry.charge` or task progress.

- [ ] **2. Run red:** `./run_tests.sh --test tests/engine/test_reserve_entry.gd`; expect premature promotion or missing entry behavior.
- [ ] **3. Implement:** allocate only actual vacated legal front positions; after every move update occupancy before the next reserve. Keep target ownership stable until unavailable; recompute only invalid routes. Use N1's validated terrain router, no indirect trajectory subsystem. `engaged_counts` retains exact fit denominator and CSV reserve contribution; front contact requires passable physical contact, rear offensive contribution cannot become full merely by role assignment. Defensive incoming attack remains lawful and real. Queries change no position, RNG or receipt. No new damage formula, bonus or supply writer.
- [ ] **4. Run green:** reserve/narrow tests, `test_battle_tasks.gd`, `test_battle_task_combat.gd`, `test_battle_save.gd`, `test_charge_runup.gd`, `test_pursuit_bounds.gd`, `test_battle_merge.gd`, then common checks. Acceptance includes real contact at the fourth step, obstruction, exact771 hand formula, and state-identical save/retry.
- [ ] **5. Commit:** `git add scripts/engine/battle_groups.gd scripts/engine/guide/battle_deployment.md tests/engine/test_reserve_entry.gd tests/engine/test_narrow_deployment.gd` then `git commit -m "feat: move reserves through real front vacancies"`. Own PR/unique Review/stop.

## Visual and release acceptance

These PRs change engine geometry that existing readers may display. Each eventual implementation/Review pair must apply `visual-review` using real windows, `tools/snapshot_screen.gd --resolution WxH`, for its changed geometry; no headless3D. Compare open/narrow ground at800/1000/10000 fit, arriving reinforcements, blocked flanks and rear entry at near/far zoom and1/2/4x. Verify map/WAR ROOM consume the same physical group facts; use existing rendering contracts, do not add renderer work to an engine PR without registered scope. Model-scale/camera/art tuning and changes to static resources require their own approved editor-owned visual step, not invented numbers here. A cloud-only implementation leaves local acceptance explicitly open and cannot treat it as passed. This planning PR runs no visual acceptance.

## Planning self-review

Spec §7 → N1 capacity/arrival and external occupancy; §8 → N0 physical continuity/N2 admission/contact; §9 → R1/R2 in the companion plan. Header, exact paths, typed interfaces, dependency serialization, red/green/commit actions and five focus cases checked. No new action/config/public export, no repeated interception implementation. Count reconciliation and legacy migration are explicit; no promise that saved unit totals identify which individual front soldier died. Event-reserve flags and charge phases retain their existing owners. Review may reject a node whose actual diff grows beyond its single behavior; split before dispatch, never accumulate another node in its PR.
