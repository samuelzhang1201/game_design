# Heavy Infantry Step 1 (the arm) Implementation Plan

**Goal:** The player can raise a heavy-infantry regiment (`heavy_infantry`) through the existing
recruitment panel; it marches at 16 km a day, fights by its own numbers and is drawn with the
infantry's stand-in art.

**Spec:** `docs/superpowers/specs/2026-11-20-heavy-infantry-arm-design.md` (step 1 of 3). The model
is the axemen's step 1 (`docs/superpowers/plans/2026-11-18-axemen-arm-step1.md`, PR #341): arms are
data, so this step is rows, two tool arm lists, editor-made art rows, re-issued certificates and
tests. No engine code changes.

## Global Constraints

- Arm code `heavy_infantry`, label `Heavy infantry`, Chinese word 重甲步兵, `type` `melee`, `crew` 1,
  `power` 1, `separate` 0, rates rural 0.05 / urban 0.15.
- Every number is the spec's first draft, used as written; it lives in a CSV, never in code.
- No edit to any file `Map3DRoyalCarrierSource._SOURCES` pins.
- `.tres` art tables are edited through the editor (gdai on a worktree editor), never as text.
- No code, tool or test names the map pack; tests take data from `tests/suite_data.gd`.
- Steps 2 (opening regiments) and 3 (the 3D soldier) are not started here.

## Review Focus

1. **The recruitable pool does not grow.** `rural_rate` / `urban_rate` are read only by
   `MilitaryBootstrap` (`_origins` and the migration's weights), as weights for where a unit's
   opening personnel come from; a pool is `recruitment_eligible_permille` of the source population.
   With every pack count 0 the new row weights nothing.
2. **Existing arms' bases move, on purpose.** `ArmySystem._arm_base` averages all of an arm's
   matchup rows, and the spec adds each existing arm's row against heavy infantry. Hand sums
   (attack + defence, halved, then the whole mean):
   - heavy infantry: (1150 + 1100 + 1200 + 950 + 1050 + 1000) / 6 = **1075**
   - infantry: (1000 + 950 + 1250 + 1000 + 900 + 900) / 6 = **1000** (was 1020)
   - archers: (1000 + 1000 + 750 + 950 + 1000 + 850) / 6 = **925** (was 940)
   - cavalry: (850 + 1250 + 1000 + 1200 + 1150 + 800) / 6 = **1041** (was 1090)
   - artillery: (900 + 850 + 700 + 1000 + 900 + 950) / 6 = **883** (was 870)
   - axemen: (1150 + 1000 + 800 + 1050 + 1000 + 1000) / 6 = **1000** (unchanged)
   Tests that pin an old mean are re-computed by hand, never loosened.
3. **A save from before this PR loads**: a regiment without the key reads 0.
4. **Certificates are issued last**, after every data and `.tres` edit, so each `input_sha256`
   matches the final tree.

## Tasks

### 1. The arm in the pack
- `data/army/game_arms.csv`: row `heavy_infantry,Heavy infantry,melee,0.05,0.15,1,1,0`.
- The default pack's `military/unit_types.csv` gains the row; `regiments.csv` and `kingdoms.csv`
  gain a `heavy_infantry` column after `axemen`, all 0 — the importer's output mirrored (the pack
  has older drift from the export in other files, so the importer is not re-run over it).
- `tests/engine/test_game_arms.gd`: the importer reads the heavy infantry's def.

### 2. Its numbers
Rows `heavy_infantry` in: `army_matchups` (own rows and the five existing arms' rows against it),
`army_town_defence` (1150 / 1350 / 1450, attack 1000), `army_terrain` (jungle 700/700, marsh
800/800, forest 900/900), `army_speed` (16), `army_scouting` (12, 120), `army_clearance` and
`unit_footprints` (the infantry's), `army_split` (ring 1, `heavy`, `Heavy foot`), `recruitment`
(2, 10, 10, equipment 3, `build_days` 8), `commanders` (`unit_kinds` gains it after `infantry`),
`war_order_words` (`arm_heavy_infantry`), `screens/ui/resource_icons`, `screens/war_room/war_drills`,
`war_equipment`, `council_seats` topics, `realm/world_schema`, `battle/cluster_arms` (`counts_as`
`infantry`, 重甲步兵), `screens/map3d/army_art.csv` (the infantry's row).

### 3. Stand-in art (editor)
`army_models.tres`, `army_paintings.tres`, `war_pieces.tres`, `unit_sounds.tres`,
`settle_sounds.tres`: `heavy_infantry` → the infantry's resource. After each save `git diff` shows
only the new row.

### 4. Locomotion
- `data/army/balance.csv`: `body_locomotion_heavy_infantry_turn_q` 400000, `_contact_um` 23217.
- `tools/units3d/measure_unit_bodies.gd`: the arm in both lists; regenerate
  `docs/reviews/cluster-formations/evidence/cf01/measurements.json`.
- `docs/reviews/cluster-formations/evidence/locomotion/heavy_infantry/`: config (the axemen's with
  the arm renamed), README, certificate.
- `certify_locomotion.py` for all seven arms; digests into `data/army/unit_locomotion.csv`.

### 5. Tests
- `tests/engine/test_heavy_infantry_arm.gd`: the hand sums above, terrain and works factors, the
  recruitment row, every land arm's rows, stand-in art, and `ArmySystem.base_pace_km` of a
  heavy-only regiment = 16 (and 16 with infantry beside it, 12 with guns).
- `tests/engine/test_raise_heavy_infantry.gd`: `ARMY_RECRUIT` end to end over 8 days; a save with
  every `heavy_infantry` key stripped passes `MilitaryBootstrap.migrate` and
  `MilitaryReorganization.reconcile`.
- `tests/engine/test_cluster_layout.gd`: a heavy unit fills an infantry slot.
- Run the categories the selector picks from the diff; open the PR.

## Left for a real window
The recruitment panel offers Heavy infantry; a raised regiment marches as the infantry's figure.
