# Player siege step 8: bombardment, engines, repair and the siege works — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spec §11 row 8 (§3 `integrity`, `breach`, §4.2, §4.4 "What the works give in the assault"). The besiegers' `engines` men build engines for gold, the `bombard` men crew them and the stationed guns, every crewed engine knocks `bombard_damage` off the record's `integrity` a day, the defenders mend it, built engines wear out, and at `siege_breach_integrity` a section is down (`breach` 1). In a town battle the defenders' works now count only as much as the walls still stand: the "siege works" factor in `BattleStrength`.

**Architecture:** `SiegeTactics.bombard(repo, state, id)` (the day) over two pure helpers, `fit_guns` and `batter`. `SiegeSystem._siege_day` calls it right after `SiegeTactics.day` (the plan), before the blockade. `BattleStrength.unit` gains the factor `town:works` for a defender of a besieged town fighting a battle at it. No pinned file is touched.

**Tech Stack:** Godot 4.7 GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §3, §4.2, §4.4, §11 row 8. Step 7's pool: `2026-11-26-player-siege-step7-allocation.md`.

## Global Constraints

- Pinned, never edited: `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd`, `war_front.gd`.
- Every rate is data: `data/battle/siege_tactics.csv` `bombard_damage` by works (`town` 0: an open town has no works to batter); `battle/balance.csv` `siege_engine_man_days`, `siege_engine_gold`, `siege_engine_crew`, `siege_repair_per_100_men`, `siege_engine_wear_days`, `siege_breach_integrity`.
- Whole numbers, fixed orders, no random number. New record fields `engines_built`, `engine_work`, `engine_wear`, `breach` read 0 when absent (an old save).
- Out of scope: mining (row 9), ladders, the assault rule and the retired timer (row 10), terms (row 11), `SIEGE_PLAN` and the crown's letters (row 12), the 3D staging (row 15). A breach is a `history` line and a flag only; nothing storms because of it yet.
- `wired: true`: every siege day runs the engines, the bombardment and the repair, and every town battle at a besieged town reads the works factor.

## The day (`SiegeTactics.bombard`, in this order)

1. A town whose works' `bombard_damage` is 0 (an open town): nothing; its engine and bombard men stand idle and no gold is spent.
2. **Build**: `engine_work += men_for(engines)`. While `engine_work ≥ siege_engine_man_days` and the chest holds `siege_engine_gold`, the gold is paid (the crown: `metrics.treasury` through `WorldLedger`, reason `siege engine before <town>`; an AI record: its leading host's `plunder`), `engines_built += 1`, `engine_work −= siege_engine_man_days`, a `history` line `engine_built`. Short of gold, the work waits at the need.
3. **Fire**: engines = the stationed besiegers' `fit_guns` (a unit's `artillery` × fit / personnel capacity, whole) + `engines_built`; crewed = min(engines, `men_for(bombard)` / `siege_engine_crew`). Guns are crewed first.
4. **Batter and mend** (`batter`): `integrity = max(0, integrity − crewed × bombard_damage)`, then, while it is above 0, `+ garrison_fit × siege_repair_per_100_men / 100`, never above 1000.
5. **Wear**: a day a built engine fired (crewed > guns) adds 1 to `engine_wear`; at `siege_engine_wear_days` one built engine is lost (`history` `engine_worn`) and the count restarts. Guns never wear.
6. **Breach**: `integrity ≤ siege_breach_integrity` sets `breach` 1 (`history` `breach`, once). It stays.

## The works factor (`BattleStrength`, source `town:works`, category `formation_terrain`)

For a unit on the DEFENDING side of a battle at a town that has a siege record, listed by `SiegeSystem.defenders_of`, and the town's works `walls` or `citadel`: each arm's scaled figure is `1000 + (defend − 1000) × I / 1000` (`I` the record's integrity, 0 with a breach). A unit that already holds the works (`ArmySystem.works_of` not "") gets scaled × 1000 / full (never above 1000); any other defender gets the scaled figure. Equipment-weighted over its arms like the storming factor; reason `the walls of <town> at <I>/1000`.

## Implementer's calls (for the owner to check)

- An open town is not bombarded and builds no engines (its `integrity` is 0 by §3).
- Build, then fire: an engine finished today fires today. Guns take the crews first, so built engines wear only on the days they fire.
- An engine short of gold waits finished-but-unpaid; the work does not bank past one engine.
- Repair runs every day the walls stand above 0, also when nothing fires; after a breach the flag stays even if the walls are mended (step 10's repulse keeps it).
- A defender who does not hold the seat (a crown camp unit, a woken unit in the camp, an occupying host's column) gets the scaled works, as the spec's "every unit the record lists as a defender".
- The main doctrine's first draft (`siege_engines_permille` 150, `siege_bombard_permille` 0) builds engines it never crews: unchanged here, its tuning is step 16's run.

---

### Task 1: The data

**Files:** `data/battle/siege_tactics.csv`, `data/battle/balance.csv`, `scripts/engine/data_repository.gd`.

- [ ] `bombard_damage` column (town 0, walls, citadel smaller); six balance keys with notes.

### Task 2: The day

**Files:** `scripts/engine/siege_tactics.gd`, `scripts/engine/siege_system.gd`, `scripts/engine/siege_record.gd`. Test `tests/engine/test_siege_bombard.gd`.

- [ ] Hand fixture: `batter` day by day to a breach (engines × damage against repair).
- [ ] Through a crown record: engines built from men and gold, crews, repair by the defenders, wear, breach line; an open town spends nothing.

### Task 3: The works factor

**Files:** `scripts/engine/battle_strength.gd`. Test `tests/engine/test_siege_bombard.gd`.

- [ ] Fixture: the scaled figure for a seat holder and for an unseated defender at integrity 1000, 500 and a breach.

### Task 4: The run, the guide, the PR

- [ ] Bounded runs: `test_siege*`, `test_battle_strength*`, `test_battle_data`, `test_raid`, `test_invasion_end_to_end`.
- [ ] `scripts/engine/guide/siege.md`: the bombardment paragraph, the works factor.
- [ ] PR: `prd_step: Step 8`, `player_outcome:`, `wired: true`, `GUT_INCLUDE: gameplay`.
