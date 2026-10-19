# P4.4d2 — deployment lines own the battle units' movement

Scope: the second slice of P4.4d (after d1's `BattleGroups`). Once contact is
confirmed the battle deployment, not the march, moves a battle unit: each unit
has a target slot on its side's deployment line at the battle place, and each
day its anchor (`x_m`/`y_m`, the one position every system reads) and its groups
step toward that slot by whole metres. No combat factor (d4), no clearance
change for outside marchers (d3), no view.

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md` §7.1
(the battlefield is deployment and contact areas on the same world, sized by
fit numbers and formation frontage), §7.2 (after contact the deployment takes
over the groups' actual positions; never both the old march and the new tactical
movement; the unit anchor and its groups are one simulated fact — no soldiers
across a river while the unit logic stays on the other bank), §8.1 (standoff and
deployment can take days), §12 (integer positions saved).

## Contract

- **The lines** (`BattleGroups.deployment(repo, state, battle) -> {unit: Vector2i}`,
  pure): the axis runs from the mean anchor of `def` toward the mean anchor of
  `att` (integer means; if they coincide, +x). Each side's line centre is the
  battle place ± axis × `battle_line_gap_m` / 2 (att on the + side). A side's
  units stand abreast along the line in sorted code order, each taking the width
  of its front groups (front count × `battle_group_spacing_m`, at least one
  spacing), the whole side centred on its line centre. A unit's target anchor is
  the centre of its width on the line, rounded to whole metres once.
- **Who the deployment moves** (`BattleGroups.deploy_day(repo, state, battle)`,
  called in `prepare_day` before the groups refresh, once per absolute day per
  battle via a saved `battle.deployed_day`): every unit of both sides EXCEPT one
  withdrawing (`battle_retreat` or `disengaging`), captured, with no fit man, or
  seated in a town (`ArmyGround.seated_in(repo, state, code) != ""` — the town's
  walls are its line). Its anchor steps toward its target by at most
  `battle_deploy_step_m` (straight line, whole metres, stopping exactly on the
  target). The march never moves a unit in a battle (unchanged).
- The groups then refresh around the moved anchors (d1), facing the other side's
  mean anchor.
- CSV (`data/battle/balance.csv`): `battle_line_gap_m` (first draft 100),
  `battle_deploy_step_m` (first draft 2 500) with notes.

## Implementer rulings pending the owner

1. A town-seated unit and a withdrawing unit are not moved by the deployment.
2. The deployment steps once a day at `prepare_day` (the standoff and approach
   take days; contact is within `battle_contact_km`, so an attacker 5 km out
   takes two days at 2 500 m).
3. Line gap and step defaults as above; record any change and why.
4. Record how existing tests that pinned a battle unit's position were adapted
   (only if a pinned position moved because of this rule — never weaken an
   unrelated assertion).

## Hand checks (tests/engine/test_battle_deployment_lines.gd)

- Two units, def at the place (0, 0), att at (4 000, 0): axis +x; def target
  (−50, 0), att target (50, 0). After one day att stands at (1 500, 0)
  (4 000 − 2 500), def at (−50, 0) (moved 50); after the second day att at
  (50, 0).
- Two att units of 120 fit (three groups in double_rank: 2 front → width
  100 m each): targets at line centre ± 50 m across the axis.
- A seated town defender and a `battle_retreat` unit do not move.
- `deploy_day` twice the same day moves once; JSON roundtrip mid-battle keeps
  `deployed_day` and positions.

## Steps

1. Tests red. 2. Code + CSV green. 3. `battle_deployment.md` "Battle groups"
paragraph extended with the lines and who moves. 4. `--fast` green; one PR.

## Implementer rulings (as built)

1. Town-seated, captured and fitless units are not moved (as drafted).
2. A withdrawal stops the WHOLE battle's deployment (`BattleGroups.withdrawing`: a side ordered `retreat`, or any unit with `battle_retreat`/`disengaging`), not only the withdrawing unit. Otherwise the winner walked after a routed side and broke the binding "actual separation ends the routed battle" (test_battle_lifecycle) and moved a withdrawing camp's unit before its retreat started (test_battle_duration).
3. `_start` stamps `deployed_day` = the day of contact, so a battle born in `_detect` does not deploy on a same-day retry (test_each_engaged_round_draws_once_and_same_day_retry_is_inert, a state-hash check). First deployment is the next day.
4. Targets use the current mean anchors, so the axis can shift slightly as units move; line gap 100 and step 2 500 as drafted.
5. Withdrawing units still count in their side's line widths.
6. No existing test assertion was adapted; the pinned positions of test_battle_duration / lifecycle / enemy_invasion hold with rulings 2-3.
