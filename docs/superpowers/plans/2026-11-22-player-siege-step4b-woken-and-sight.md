# Player siege step 4b: woken garrisons, the enemy's sight of a militia — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The rest of spec §11 row 4 after 4a (`2026-11-22-player-siege-step4-militia.md`). A foreign town's standing roster units wake as defenders when a siege opens and go back with their losses. The enemy weighs a would-be militia, and besieges an empty town instead of raiding it.

**Architecture:** `TownMilitia` gains `wake` / `send_back` (beside `raise` / `stand_down`) and `defend_power`. `SiegeRecord._open` wakes before it raises, and `SiegeSystem.settle_day` sends back after it stands down. `EnemyAi._gather` adds `defend_power` to an undefended town's defence. `EnemyAi.arrival_mode` answers DEPLOYING for an undefended town, and the arrival sites open the record at once (`SiegeRecord.ensure_for`), so the militia is on the seat before any column can walk into an empty town.

**Tech Stack:** Godot 4.7 GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §5, §8, §11 row 4.

## Global Constraints

- Pinned, never edited: `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd`, `war_front.gd`.
- Old saves: `migrate` (levy false) wakes no unit and raises no militia.
- Every number comes from data. The AI reads the walls at full strength (spec §14).
- `wired: true` (the invasion run changes). Step 5 re-tunes, so `test_raid` / `test_invasion_end_to_end` fixtures that need a raid take a plain manor.

## Review Focus

- A woken unit that the town's fall leaves standing there (the holder changed) stays an ordinary foe and loses its `garrison_of` mark.
- A woken unit in a battle when the record closes waits for the battle to end.
- A save round-trips a woken foe (`garrison_of`, the record's `woken`).
- A host that arrives at an empty town while a crown unit stands at it still fights in the field (arrival answers "").
- An empty town besieged by a reserve before the main host: the reserve's arrival opens the record and the militia is raised once.

---

### Task 1: Woken garrisons

**Files:** Modify `scripts/engine/town_militia.gd`, `scripts/engine/siege_record.gd`, `scripts/engine/siege_system.gd`. Test `tests/engine/test_siege_woken.gd`.

**Interfaces:**
- `TownMilitia.standing_at(repo, state, town, k) -> Array`: kingdom `k`'s land `army_roster` rows with no state (not in `foes` / `regiments`), on `town`'s seat or with `camp_town` `town`, in code order.
- `TownMilitia.wake(repo, state, id) -> Array`: for a record whose defender is not the crown, each of `standing_at` goes into `foes` (`ArmySystem.starting_state`, `host` "", `garrison_of` the town). The record's `woken` lists them.
- `TownMilitia.send_back(repo, state) -> Array`: each foe with `garrison_of` that no record's `woken` lists and that is in no battle. Alive (`living_count` > 0), at the town (`SiegeSystem.at_town`) and its kingdom still holding it → its `foes` entry is erased, so it is a roster unit again. Its losses stay in its cohorts. Otherwise the mark is dropped. Event `{kind "garrison_returned", unit, town, day}` for a return.

- [ ] Tests: the woken units are exactly `standing_at`, and the town raises no militia. A seated woken unit fights from the works (`ArmySystem.works_of` ≠ ""). After the record closes with 10 dead, the unit is back (not in `foes`), its living is 10 less, and its seat is kept. The fall leaves it a foe without the mark. A battle holds it. Save round-trip. `migrate` wakes none.
- [ ] Implement. `_open` adds `"woken": []` and, with `levy`, calls `wake` before `raise`. `settle_day` appends `send_back` after both `stand_down` calls.

### Task 2: The enemy's sight of a militia

**Files:** Modify `scripts/engine/town_militia.gd`, `scripts/engine/enemy_ai.gd`. Test in `tests/engine/test_siege_woken.gd`.

- `TownMilitia.defend_power(repo, state, town) -> int` = `ArmySystem.power_of_arms(repo, elements, men, army_start_training, army_start_morale, "defend", terrain_at(town point), works_of_town(town))`, with elements = men / crew per arm of `size`. 0 for no militia.
- `_gather`: a town candidate with no seen defenders takes `defend_power` as its `defence`.
- [ ] Test: an empty crown town's candidate `defence` equals `defend_power` (> 0), and `defend_power` equals the hand-built `power_of_arms` call.

### Task 3: Empty towns besieged, not raided

**Files:** Modify `scripts/engine/enemy_ai.gd`. Test in `tests/engine/test_siege_woken.gd`, plus the gameplay fixtures that need a raid.

- `arrival_mode`: a town that is held, with no seen defenders at it, gives `ARRIVAL_RETHINK` (another non-reserve host besieges it) or `MODE_DEPLOYING`. RAID only for a manor.
- Both arrival sites call `SiegeRecord.ensure_for(repo, state, code)` after `_start_deployment`.
- [ ] Tests: a host at an empty crown town turns DEPLOYING, the record is opened and its militia is on the seat (in `regiments`). A plain manor still gives RAID.
- [ ] Run `test_raid` / `test_siege` / `test_invasion_end_to_end`. Point any raid fixture at a manor.

### Task 3b: A beaten militia breaks up (found by the invasion run)

The no-orders run storms an empty town. The militia, beaten, started a battle withdrawal it can never walk, so the battle stuck and the attacker bled against no one.
- `TownMilitia.disperse(repo, state, code) -> int`: releases its fit and wounded (event `<code>:broke`, reason `militia of <town> broke`), once.
- `BattleSystem._start_retreat` disperses a militia and returns false. `_exits` lets a militia that would leave, or whose side retreats, leave at once as `broken`.
- [ ] Test `test_a_beaten_militia_breaks_up_instead_of_marching` (`test_siege_militia.gd`). `test_army_clearance`'s invasion run passes.

### Task 4: Guide and PR

- [ ] `guide/siege.md`: the woken units, the sight, and the arrival. `guide/battle_and_ai.md`: the arrival line.
- [ ] PR body: `prd_step: Step 8`, `player_outcome:`, `wired: true`, `GUT_INCLUDE: gameplay`.
