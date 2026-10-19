# P4.4d1 — representative groups and their saved positions

Scope: the first slice of P4.4d (representative-group positions, movement
ownership, legal contact feeding combat; `2026-10-18-p44a-unit-task-ledger.md`
"Following P4.4 steps"). This slice adds only the engine fact: each battle
unit's fit personnel split into groups of at most 50 with whole-metre positions
laid out by its formation, saved in the battle and re-converged daily. Nothing
reads the groups yet: no combat factor (d3), no clearance change (d2), no view.

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md` §6.1
(F = (N + 49) / 50, the remainder group keeps its real count, two units never
pooled), §6.3 (when N changes the groups converge to F; a group index is not a
permanent identity; sums conserved), §7.1 (spacing and depth per 50-group from
data, in the pack's world metres), §7.2 (group positions and the unit's anchor
are one simulated fact), §8.2 (each group saves real count, role, whole-metre
position, facing), §12 (group split, positions, roles and facing in the save).

## Contract

- `BattleGroups.counts(n: int) -> Array[int]`: `battle_group_size` (50) per
  group, the last group the remainder. Hand: 0 → [], 1 → [1], 49 → [49],
  50 → [50], 51 → [50, 1], 800 → 16 × 50, 1000 → 20 × 50, 10 000 → 200 × 50.
- `BattleGroups.layout(repo, formation, count, anchor: Vector2i, facing_deg: int)
  -> Array[Vector2i]`: `BattleFormation.slots(formation, count)` scaled by
  `battle_group_spacing_m` across and `battle_group_depth_m` back (slot y grows
  away from the enemy), rotated so the front faces `facing_deg`, rounded to whole
  metres once. Facing 0 = +x... (implementer: match `WarFront.facing_deg`'s
  convention and state it in the guide).
- `BattleGroups.refresh(repo, state, battle)`: for every unit of both sides in
  sorted code order, `battle.groups[unit] = [{count, role, x_m, y_m}]` and
  `battle.group_facing[unit] = facing_deg` toward the mean position of the other
  side's units (0 if none). `count`s are `counts(ArmySystem.fit_count)`; role is
  `front` for slot rank 0 and `reserve` otherwise; formation is
  `BattleFormation.of_unit` (its current). The anchor is the unit's own
  `x_m/y_m`. Called when a battle starts (`_start`), when a unit joins
  (`join`), and once at the start of each battle's daily round. A unit that has
  left the battle loses its entry. Old saves: a battle without `groups` gets
  them at its next refresh.
- Conservation: the sum of a unit's group counts equals its fit count after
  every refresh.
- CSV (`data/battle/balance.csv`): `battle_group_size` 50,
  `battle_group_spacing_m`, `battle_group_depth_m` with notes (implementer
  picks starting values from the model-scale audit in
  `scripts/map3d/CLAUDE.md` / formations.csv `frontage_m`; e.g. line frontage 500
  m over 10 groups → 50 m spacing; record the choice as a ruling).

## Implementer rulings pending the owner

1. Spacing/depth defaults (record the values chosen and why).
2. Rank 0 is the front, every deeper rank reserve.
3. Facing is toward the mean of the enemy units' anchors.

## Hand checks (tests/engine/test_battle_groups.gd)

- `counts` table above.
- `layout("line", 3, (0,0), facing)` positions hand-computed from slots
  (-1,0), (0,0), (1,0) × spacing, rotated.
- A battle of a 120-fit unit vs a foe: groups [50, 50, 20], sum 120; after 30
  dead the next refresh gives [50, 40].
- JSON roundtrip keeps groups and facing.

## Steps

1. Tests red. 2. `scripts/engine/battle_groups.gd`, CSV keys, the three call
sites, green. 3. `battle_deployment.md` paragraph (and the engine
`CLAUDE.md` topic index line naming `BattleGroups`). 4. `--fast` green; one PR.

## Implementer rulings pending the owner (as built)

1. Spacing 50 m across, depth 40 m back (`battle_group_spacing_m`, `battle_group_depth_m`): 50 m matches the plan's 500 m line over 10 groups; depth 40 m is a first draft (a rank behind sits under one spacing).
2. Rank 0 = every slot at the foremost slot y (the minimum), so a double rank has two front groups and a diamond's north point is front; all others reserve.
3. Facing: `WarFront.facing_deg` convention (0 = +x, y down); across = facing + 90 degrees, back = -facing; toward the integer-mean of the enemy anchors, 0 if none.
4. Refresh is called in `_start` (after enrol), `join` (after `_halt`) and `prepare_day` (per battle, after `ensure`, before withdrawals/detection), so a mid-day join/start also refreshes.
5. `line` ignores `frontage_permille` (default 1000): one rank abreast, as the slots function does.
6. A refresh also runs at the end of `step_battle` (battle not ended): the round's losses and exits change fit counts, and `test_battle_duration` requires a same-day retry to leave the state hash unchanged, which a refresh only at the day's start breaks.
