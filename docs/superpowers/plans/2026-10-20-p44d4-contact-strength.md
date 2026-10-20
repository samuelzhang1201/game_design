# P4.4d4 — legal group contact feeds combat

Scope: the last slice of P4.4d. A battle unit's strength counts its personnel
by whether their group is actually in contact: a front group within reach of an
enemy group fights in full; every other fit person (reserve ranks, a front still
approaching) adds only `battle_reserve_permille`. One factor with a reason in
the existing `unit_strength` factor list. No view change.

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md` §8.2
(the engine settles on real front, flanks, terrain and numbers from the saved
groups; front space is limited; rear ranks cannot strike in full through their
own line; a reserve counts only once in an effective position), §8.3 (contact
pairs at legal positions), §15 (coefficients belong to the implementation plan,
in data, with hand-computed tests).

## Contract

- `BattleGroups.engaged_permille(repo, state, battle, code) -> int`:
  `(engaged × 1000 + (fit − engaged) × battle_reserve_permille) / fit` (integer
  division, 1000 when the unit has no saved groups or no fit man), where
  `engaged` is the summed `count` of the unit's `front` groups that stand within
  `battle_group_contact_m` (inclusive, squared whole metres) of ANY group of a
  unit on the other side.
- `BattleSystem.unit_strength` appends `{source: "contact:engaged", category:
  <a contact category>, permille, reason: "N of M in contact with the enemy
  line"}` for a unit in a battle with saved groups. Register the category with
  its clamp in the table `BattleStrength` reads (implementer: find it; state the
  bounds as a ruling).
- CSV (`data/battle/balance.csv`): `battle_group_contact_m` (first draft 100 —
  the line gap of d2, so fronts deployed opposite each other engage),
  `battle_reserve_permille` (first draft 500).
- Siege assaults, town battles and events use the same `unit_strength`, so they
  inherit the factor; nothing else changes.

## Implementer rulings pending the owner

1. Contact reach and reserve share defaults; their effect on the balance and
   simulation suites (run both, report the totals, and list every pinned
   outcome that moved and why — never loosen an unrelated assertion).
2. A front group still approaching counts as reserve.
3. Category and clamp chosen.

Recorded rulings (implementation):

- Category: new `contact` category in `BattleStrength.CATEGORIES`, between
  `formation_terrain` and `action`. Bounds are not per-category: every factor
  gets `battle_strength_factor_min_permille` 0 / `battle_strength_factor_max_permille`
  3000 (data/battle/balance.csv) in `BattleStrength.unit`; the factor range is
  500..1000, so the clamp never bites.
- Defaults kept: `battle_group_contact_m` 100, `battle_reserve_permille` 500.
  A front group still approaching counts as reserve (no enemy group in reach).
- Reason text counts people: "N of M in contact with the enemy line".
- Adapted test: `test_battle_lifecycle.gd::test_steady_retreats_below_retreat_odds`
  computed the day's odds before the battle existed (no contact factor) and
  expected settle to match; it now calls `BattleSystem.prepare_day` first so the
  battle and its groups exist when the odds are read. Thresholds (margin 1 / 0)
  unchanged.

## Hand checks (tests/engine/test_group_contact_strength.gd)

- A 120-fit unit (groups 50 front, 50 reserve, 20 front in double_rank), its
  two front groups within 100 m of an enemy group: engaged 70 → (70 000 + 50 ×
  500) / 120 = 791.
- Same with no enemy group in reach: (0 + 120 × 500) / 120 = 500.
- No saved groups: 1000 and no factor.
- `unit_strength` lists the factor with source `contact:engaged`.

## Steps

1. Tests red. 2. Code, CSV green. 3. `battle_deployment.md` paragraph.
4. `--fast`, `--category simulation`, `--category balance` green (balance
moves recorded as rulings); one PR whose body carries the line
`GUT_INCLUDE: simulation,gameplay,balance`.
