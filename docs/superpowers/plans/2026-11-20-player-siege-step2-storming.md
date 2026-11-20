# Player siege step 2: the storming factor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A unit attacking a town gets its arm's `army_town_defence.csv` `attack_permille` for the town's works, for both sides, with a reason.

**Architecture:** `BattleStrength.unit` already walks the arms and weights terrain by each arm's power. It weights `attack_permille` the same way when the unit is attacking (`attacking`) and stands on the `att` side of a battle (`BattleSystem.battle_of`) that has a `town`. The result is one more `formation_terrain` factor (`town:storming`) with a reason. The pinned `ArmySystem.terrain_factor` stays unchanged and still gives the works to defenders only.

**Tech Stack:** Godot 4.7, GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §4.4 "What the attacker gets", §11 step 2; `docs/superpowers/specs/2026-11-18-axemen-arm-design.md` step 3 (dropped there, built here).

## Global Constraints

- Never edit `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd`, `war_front.gd`.
- Values come from `data/army/army_town_defence.csv` `attack_permille`. The column exists already: axemen 1100/1200/1250 (town/walls/citadel), every other arm 1000.
- Whole per-mille integers, with one truncation for the weighted mean.
- The reason reads `storming the <works> of <town label> (<arm> <permille>, ...)`, one entry for each arm present.

## Review Focus

- A defender who attacks (a sally from the `def` side) must get no storming factor. This is tested.
- An attacker-side unit holding this round (`attacking` false) gets no factor. This is tested.
- A field battle (`town` == "") gets no factor. This is covered because existing battle tests keep their values.
- An arm with no table row counts as 1000.
- When every arm is 1000 the power is unchanged: infantry walls 475 → 475. This is tested.

---

### Task 1: storming factor in `BattleStrength.unit`

**Files:**
- Modify: `scripts/engine/battle_strength.gd` (`unit`)
- Test: `tests/engine/test_battle_strength.gd`
- Guide: `scripts/engine/guide/battle_deployment.md` (the `BattleStrength` paragraph)

**Interfaces:**
- Consumes: `BattleSystem.battle_of(state, code) -> Dictionary` (`att`, `def`, `town`); `repo.army_town_defence["works|arm"].attack`; `repo.burgs[town].features` and `.label`.
- Produces: in `unit`'s result `factors`, the factor `{"category": "formation_terrain", "source": "town:storming", "permille": int, "reason": String}`.

- [ ] **Step 1: Write the failing test** `test_unit_storming_weights_attack_permille_for_the_attacker_only`. It uses the existing `unit` fixture (630 base → 475 after training, morale and discipline). The town gets `features = "walls"` and a battle `{att:[code], def:["foe"], town}`. The table is set by hand: walls|axemen attack 1200, walls|infantry attack 1000.
  - axemen 600, attacking → power 570 (475 × 1200 / 1000), a factor `town:storming` with permille 1200, reason `storming the walls of <label> (axemen 1200)`.
  - infantry 600, attacking → 475, factor permille 1000.
  - the same unit on `def`, attacking → 475, no `town:storming`.
  - on `att`, `attacking` false → no `town:storming`.
- [ ] **Step 2: Run it** with `./run_tests.sh --test tests/engine/test_battle_strength.gd`. Expected: FAIL (no factor).
- [ ] **Step 3: Implement** in `unit`: before the arm loop, look for a town through `BattleSystem.battle_of` (attacking, code in `att`, `town` ≠ ""). Pick the town's works the way `works_of` does (citadel over walls over town). In the loop, add `storm_weight += power * attack`. Append the factor after the terrain factor, with permille `storm_weight / equipment` (1000 when equipment is 0).
- [ ] **Step 4: Run** the test again. Expected: PASS. Then run `./run_tests.sh --base origin/main`, which must be green.
- [ ] **Step 5: Guide + commit**: one sentence in `battle_deployment.md`; commit.
