# Axemen Step 1 (the arm) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The player can raise an axe regiment (`axemen`) in the prologue through the existing recruitment panel; it fights by its own numbers and is drawn with the infantry's stand-in art.

**Architecture:** Arms are data: the pack's `military/unit_types.csv` names them and ~20 per-arm tables give their numbers; the engine iterates `unit_types`. Step 1 adds the `axemen` rows, makes the Azgaar importer append game-owned arms so a re-import keeps them, moves `ClusterLayout`'s hard-coded arm list into a table with a "counts as" column, binds the stand-in art in the editor, and re-issues the locomotion certificates and unit-body measurements the new rows invalidate.

**Tech Stack:** Godot 4.7 GDScript, GUT, CSV tables, Python certifier (`tools/units3d/certify_locomotion.py`), gdai MCP for `.tres` edits.

**Spec:** `docs/superpowers/specs/2026-11-18-axemen-arm-design.md`

## Global Constraints

- Arm code `axemen`, label `Axemen`, Chinese word 斧兵, `type` `melee`, `crew` 1, `power` 1, `separate` 0.
- Every design value lives in a CSV; no tuning number in code. Notes columns describe the rule as it stands now, no history.
- No edit to any file in `Map3DRoyalCarrierSource._SOURCES` (e.g. `scripts/engine/army_system.gd`, `scripts/map3d/map3d_formation.gd`).
- `.tres` art tables are edited through the editor (gdai MCP), never as text; check open script buffers against disk before any editor save (root `CLAUDE.md`).
- No code, tool or test names the map pack (`DataRepository.default_pack_id()`); tests take data from `tests/suite_data.gd`.
- Existing arms' numbers must not move in this step (see Task 2's matchup rule).
- PR body carries `prd_step:`, `player_outcome:`, `wired:` lines; one PR for this step.

## Review Focus

1. **Existing battles unchanged** — `ArmySystem._arm_base` averages ALL of an arm's matchup rows, so a "X vs axemen" row for an existing arm would shift that arm's power everywhere. Only the axemen's own rows are added (Task 2 test pins infantry's base).
2. **A saved game from before this PR loads** — regiments without an `axemen` key read 0 (`regiment.get(arm, 0)`); Task 6 loads a pre-PR save fixture shape.
3. **Re-import keeps the arm** — running the importer on the committed Azgaar export reproduces the pack's `military/*` byte for byte (Task 1).
4. **Recruitment of an axe regiment end to end** — quote, pay, assemble over `build_days` 3, the unit appears with `organization_arm` `axemen` (Task 6).
5. **Every certificate's input hash matches the final data** — certificates are re-issued after the last data edit, not before (Task 5 runs last among data tasks).

---

### Task 1: The importer appends the game's own arms

**Files:**
- Create: `data/army/game_arms.csv` (`unit_code,label,type,rural_rate,urban_rate,crew,power,separate,notes`; one row `axemen,Axemen,melee,0.3,0.05,1,1,0,...`). The rates only weight where opening personnel come from (`MilitaryBootstrap._origins`), not a pool size; 0.3 / 0.05 = mostly rural.
- Modify: `data/tables.csv` (index `army,game_arms`), `scripts/engine/data_repository.gd` only if `tables.csv` requires a loader (follow how a tool-only table such as an existing one is indexed; if the shape test demands a loader, add `game_arms` like `recruitment`).
- Modify: `tools/import_azgaar.gd` (the `# --- military/*` block, ~line 790, and `unit_names`/`unit_power` at ~568): after `unit_defs` is read, append each `game_arms` row whose `unit_code` is not already a unit name; its `label` is written as given (not `capitalize()`); its count in every regiment and kingdom is 0.
- Modify: `data/maps/<pack>/military/unit_types.csv`, `regiments.csv`, `kingdoms.csv` — regenerated output (row `axemen` last in `unit_types`; column `axemen` after `fleet` in `regiments` and `kingdoms`, all 0).
- Test: `tests/engine/test_game_arms.gd`

**Interfaces:**
- Produces: `repo.world_table("military", "unit_types")["axemen"]` with the values above; `axemen` key in every pack regiment/kingdom row.

- [ ] **Step 1: Write the failing test** `test_game_arms_are_in_the_pack`: for every row of `game_arms.csv`, `SuiteData.repo().world_table("military","unit_types")` has the code with equal label/type/crew/power/rates; every row of `world_table("military","regiments")` and `"kingdoms"` has the key with value 0.
- [ ] **Step 2:** Run `./run_tests.sh --test tests/engine/test_game_arms.gd` — FAIL (no `axemen`).
- [ ] **Step 3:** Implement the importer append; run the importer on the committed Azgaar export into a scratch folder under the session scratchpad; copy only its `military/unit_types.csv`, `regiments.csv`, `kingdoms.csv` over the pack's. `git diff` of those three must show only the `axemen` row/column; any other difference means the pack drifted from the export — stop and report instead of committing it.
- [ ] **Step 4:** Run the test — PASS; run `./run_tests.sh --test tests/engine/test_data_csv_shape.gd` and `tests/engine/test_map_data.gd` — PASS.
- [ ] **Step 5: Commit** `Axemen: game-owned arms survive the Azgaar re-import`.

### Task 2: The axemen's numbers

**Files (rows added, notes column filled; values from the spec):**
- `data/army/recruitment.csv`: `axemen,2,10,10,1,3,0`.
- `data/army/army_matchups.csv`: ONLY axemen's own rows — vs infantry 1300/1000, vs archers 1100/900, vs cavalry 900/700, vs artillery 1200/900, vs axemen 1000/1000. No "X vs axemen" row for an existing arm (Review Focus 1); they come with the per-foe step.
- `data/army/army_terrain.csv`: `forest,axemen,1150,1150`; `jungle,axemen,1000,1000`.
- `data/army/army_town_defence.csv`: `town,axemen,1050,1100`, `walls,axemen,1150,1200`, `citadel,axemen,1200,1250` (defend, attack; `terrain_factor` reads only `defend` today).
- Copies of the infantry row with arm `axemen`: `army_speed`, `army_scouting`, `army_clearance`, `unit_footprints`, `data/screens/map3d/army_art.csv` (the stand-in plays the infantry's clips, so the infantry's stride/steps/chains).
- `data/army/army_split.csv`: `axemen,1,axe,Axemen,0`.
- `data/army/commanders.csv`: `unit_kinds` gains `axemen` in every row that lists `infantry`.
- `data/army/war_order_words.csv`: `arm_axemen,axes`.
- `data/screens/ui/resource_icons.csv`: `axemen,Axemen,<an existing icon key; shield if none fits>,Axemen: shock foot that breaks shield walls and gates.`
- `data/screens/war_room/war_drills.csv`: `axemen` in every `arms` list that has `infantry`.
- `data/screens/war_room/war_equipment.csv`: helmet, mail, round shield, hand axe rows for `axemen`, described from `assets/3D/model_wip/blender_output/infantry/preview/handaxe_shield/` in the main checkout.
- `data/council/council_seats.csv`: marshal `topics` gains `axemen|axes`.
- `data/realm/world_schema.csv`: `military.kingdoms.*.axemen` row mirroring the infantry's.
- Test: `tests/engine/test_axemen_arm.gd`

**Interfaces:**
- Consumes: Task 1's `unit_types` row.
- Produces: `repo.recruitment["axemen"]`, `repo.army_matchups["axemen"]`, `repo.army_art["axemen"]`.

- [ ] **Step 1: Write the failing tests** (hand-computed):
  - `test_axe_base_is_its_matchup_mean`: `ArmySystem._arm_base(repo, "", "axemen", 0)` == ((1300+1000)/2 + (1100+900)/2 + (900+700)/2 + (1200+900)/2 + (1000+1000)/2) / 5 = (1150+1000+800+1050+1000)/5 = **1000**.
  - `test_infantry_base_unchanged`: `_arm_base(repo, "", "infantry", 0)` == (1000 + 950 + 1250 + 1000)/4 = **1050**.
  - `test_axe_forest_and_jungle`: `ArmySystem.terrain_factor(repo, "forest", "axemen", "attack", "")` == 1150; `("jungle","axemen","defend","")` == 1000.
  - `test_axe_walls_defence`: `terrain_factor(repo, "plains", "axemen", "defend", "walls")` == 1150 (plains has no axemen row → 1000 × 1150/1000).
  - `test_axe_recruits_in_three_days`: `repo.recruitment["axemen"]` build_days 3, equipment 1.
  - `test_every_land_arm_has_its_rows`: every `unit_types` arm that is not `naval` has a row in `army_speed`, `army_scouting`, `army_clearance`, `unit_footprints`, `army_split`, `army_art`.
- [ ] **Step 2:** Run `./run_tests.sh --test tests/engine/test_axemen_arm.gd` — FAIL.
- [ ] **Step 3:** Add the rows.
- [ ] **Step 4:** Run the test — PASS; then `./run_tests.sh --category` for the engine categories the selector picks from the diff (`./run_tests.sh --base origin/main`) — PASS, or fix tests that enumerate arms by literal list.
- [ ] **Step 5: Commit** `Axemen: the arm's numbers in every per-arm table`.

### Task 3: Cluster arms move into a table

**Files:**
- Create: `data/battle/cluster_arms.csv` (`arm,counts_as,word`): infantry/infantry/步兵, archers/archers/弓兵, cavalry/cavalry/骑兵, artillery/artillery/炮兵, axemen/infantry/斧兵, plus the `units` word row the code uses for "作战单位" (`units,,作战单位`).
- Modify: `data/tables.csv`, `scripts/engine/data_repository.gd` (load it as `repo.cluster_arms: Dictionary` keyed by arm).
- Modify: `scripts/engine/cluster_layout.gd`: delete `ARMS` and `ARM_WORDS`; a member's arm must be a key of `repo.cluster_arms` with a non-empty `counts_as`; recipe counts and slot templates use `counts_as`; missing-words read `word`. `_members` and `_missing` gain the `repo` parameter.
- Test: `tests/engine/test_cluster_layout.gd` (extend)

**Interfaces:**
- Produces: `repo.cluster_arms[arm] -> {"counts_as": String, "word": String}`.

- [ ] **Step 1: Write the failing test** `test_axe_fills_an_infantry_slot`: `ClusterLayout.options(repo, units)` with two controllable fit `axemen` units and one `infantry` unit marks `steady_line` (`infantry:2`) eligible; with three `axemen` units and no infantry, `strong_wing` (`infantry:3`) is eligible and the missing-words of an ineligible formation name 步兵, never 斧兵.
- [ ] **Step 2:** Run `./run_tests.sh --test tests/engine/test_cluster_layout.gd` — the new test FAILS, the old ones pass.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run — all PASS.
- [ ] **Step 5: Commit** `Axemen: cluster arms and their foot slot come from data`.

### Task 4: Stand-in art in the editor

**Files (editor only, gdai MCP; a worktree editor on its own gdai port per memory `worktree-editor-on-its-own-gdai-port`, or ask the coordinator for the main editor):**
- `assets/3D/units/army_models.tres`: `axemen` → `scenes/models/units/infantry.tscn`.
- `assets/2D/paintings/armies/army_paintings.tres`: `axemen` → `infantry.png`.
- `assets/3D/war_room/war_pieces.tres`: `axemen` → the infantry's piece.
- `assets/audio/units/unit_sounds.tres`: `axemen` → the infantry's sound; `settle_sounds.tres` likewise if its keys are arms.
- Test: `tests/engine/test_axemen_arm.gd` (extend)

- [ ] **Step 1: Write the failing test** `test_axe_has_its_stand_in_art`: `GameArt.path(table, "axemen")` equals `GameArt.path(table, "infantry")` for each of the tables above.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Edit the four (or five) tables in the editor; save; confirm `git diff` shows only the new rows and their ext_resource lines.
- [ ] **Step 4:** Run the test plus `tests/ui/test_editor_owned_look.gd` and `tests/map3d/test_map3d_editor_owned_look.gd` — PASS.
- [ ] **Step 5: Commit** `Axemen: stand-in model, painting, war piece and sounds`.

### Task 5: Locomotion row, measurements and certificates

**Files:**
- `data/army/balance.csv`: `body_locomotion_axemen_turn_q` 400000, `body_locomotion_axemen_contact_um` = the infantry's value (same model, same size).
- `tools/units3d/measure_unit_bodies.gd`: `axemen` in the arm list with attack bone `cc_weapon.r` (the stand-in's). Then regenerate `docs/reviews/cluster-formations/evidence/cf01/measurements.json` the way the last re-issue did (`git show e6f9d613`).
- Create: `docs/reviews/cluster-formations/evidence/locomotion/axemen/certificate.config.json` (copy of the artillery's with `arm` `axemen`, `radius_m` 927, its note naming the infantry stand-in; any real axe model voids it) and `README.md` (short, as the artillery's).
- Run `tools/units3d/certify_locomotion.py --config .../<arm>/certificate.config.json --out .../<arm>/certificate.json` for all six arms (infantry, archers, cavalry, artillery, royal, axemen) AFTER every other data edit of this PR; write each new digest into `data/army/unit_locomotion.csv`, adding the `axemen` row (provider `scripts/map3d/map3d_infantry_locomotion.gd`, the infantry's phases and stride).
- Test: the existing locomotion certificate tests (find with `grep -rl unit_locomotion tests`).

- [ ] **Step 1:** Add the balance keys, measure-tool arm and axemen config.
- [ ] **Step 2:** Regenerate measurements, then certify all six arms; each must report NUMERIC_PASS.
- [ ] **Step 3:** Update `unit_locomotion.csv`.
- [ ] **Step 4:** Run the locomotion/certificate tests and `./run_tests.sh --category map3d` — PASS.
- [ ] **Step 5: Commit** `Axemen: locomotion row; re-issue the six certificates`.

### Task 6: Raise one in the prologue

**Files:**
- Test: `tests/gameplay/test_raise_axemen.gd` (or the folder the recruitment tests live in; find with `grep -rl RecruitmentSystem tests`).

- [ ] **Step 1: Write the test** `test_raise_an_axe_regiment`: from `SuiteData.campaign(repo, seed)`, quote and pay a `new` recruitment with `arm` `axemen`, an eligible commander and a town of the player's realm, through the same `Game`/`ActionSystem` path the panel uses; advance 3 days; the new unit exists, `MapObjects.regiment_arm` is `axemen`, its `axemen` count > 0. Also `test_old_save_without_axemen_loads`: a campaign copied through the save format with every `axemen` key removed loads and its regiments read `axemen` 0.
- [ ] **Step 2:** Run it — PASS (Tasks 1–5 already wired the arm; a FAIL names the missing wire).
- [ ] **Step 3:** Real-input check per memory `verify-ui-through-real-input`: in a real window, open the recruitment panel, pick Axemen, raise it, see the stand-in on the 3D map march and the card show the infantry painting. Screenshots into the PR.
- [ ] **Step 4:** Run `./run_tests.sh --base origin/main` — PASS.
- [ ] **Step 5: Commit**, push `claude/axemen-arm`, open the PR with `prd_step:`, `player_outcome: the player can raise an axe regiment in the prologue`, `wired: recruitment panel lists Axemen; battles use its rows`.
