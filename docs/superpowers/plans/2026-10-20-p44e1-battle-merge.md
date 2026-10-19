# P4.4e1 — actual-contact battle merging, the survivor and its aliases

Scope: the first slice of P4.4e (compatible actual-contact merging, source-
scoped terms, aliases, commander succession, dedupe;
`2026-10-18-p44a-unit-task-ledger.md` "Following P4.4 steps"). This slice merges
two live battles whose groups actually touch into one surviving record, keeps
the other id as an alias that still resolves, and carries every per-unit and
accumulated record over without re-running anything. The absorbed battle's
agreement and commanders are KEPT as source records but not yet unified: e2
chooses the unified commander, e3 makes the source-scoped terms bind across the
merged field.

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md`
§11.1 (merge only on real contact of participating units/groups of compatible
sides — overlapping boxes, map circles or nearby wars never trigger; a stable
battle id survives, the others stay as source aliases; start times, each unit's
committed and lost totals, orders, costs, event dedupe marks, siege/assault
links and agreements migrate without reopening the first round, re-feeding or
re-firing events; still several local fronts, nobody teleported to a common
centre; one unit has one battle at a time; union first, then one settlement, no
group charged twice a day; a field battle merging never ends a siege and an
assault stays linked to its town and works), §12 (aliases in the save).

## Contract

- **Trigger** (`BattleMerge.day(repo, state) -> Array` of events, called from
  `BattleSystem.prepare_day` after every battle's deploy and groups refresh and
  before withdrawals/detection): battles A and B (A.id < B.id) merge when some
  unit of A and some unit of B on OPPOSITE allegiances (crown regiment vs foe)
  have a pair of groups within `battle_group_contact_m` (inclusive, squared whole
  metres). Pairs are checked in id order; after a merge the survivor is checked
  again against later battles the same day (deterministic fixed point). Two
  battles that both have a `town` never merge; neither does a pair where either
  side is empty.
- **Survivor**: the lower id, unless only B has a `town` — then B survives (the
  assault stays linked to its town). The survivor keeps its id, place, town and
  start_day = min of both.
- **Union by allegiance**: each absorbed unit joins the survivor's side that
  holds its allegiance (crown units with crown units). Order: survivor members
  first, then absorbed members in their old order, no duplicates.
- **Migrated, never re-run**: `personnel_entries`, `unit_entries`,
  `reinforcement_evidence`, `withdrawal_costs`, `abandoned_supplies`,
  `event_modifiers`, `unit_formations`, `reserves`, `report_events`,
  `event_reinforcements_consumed` and any other per-unit/per-source dict or
  list (implementer: enumerate every key a battle can carry by reading
  BattleSystem, BattleRules, BattleFormation, BattleEvents, BattleReport,
  BattleOrders, SiegeSystem; record the list as a ruling) — merged so no entry
  is lost or doubled. `rounds` = max; `last_resolved_day` = max (a battle that
  already fought today keeps the merged one from fighting again today).
- **Source records kept**: `battle.sources[<absorbed id>] = {parley, commanders,
  actions, formations, start_day, place_x_m, place_y_m}` (the absorbed battle's
  side-level state, verbatim); the survivor's own side-level state is unchanged.
- **Aliases**: `GameState.battle_aliases` (absorbed id → survivor id, saved,
  default `{}`); `BattleSystem.battle_by_id` resolves an alias (chains too).
  Unit tasks, couriers and reports holding the absorbed id therefore reach the
  survivor; `BattleTaskSystem.combat_action` compares canonical ids.
- **Events**: one `{kind: "merge", battle_id: survivor, absorbed: id,
  reason}` per merge, journaled like other battle events (no battle letter
  wording yet: record as ruling if the report needs a template row).

## Implementer rulings pending the owner

1. Contact is group-to-group within `battle_group_contact_m`; anchors alone
   never trigger.
2. Survivor = lower id unless only the other has a town.
3. Merging is checked once a day in `prepare_day`, so no group fights twice a
   day; record any substep-level case left out.
4. The full list of migrated keys and how each merges.
5. The absorbed side-level state is kept verbatim under `sources` until e2/e3.

## Hand checks (tests/engine/test_battle_merge.gd)

- Battle 1 (crown P1 vs foe F1), battle 2 (crown P2 vs foe F2); F2's group 80 m
  from a P1 group (contact 100): after `day`, battle 2 is gone, battle 1 has att
  [P1, P2] / def [F1, F2] by allegiance (whichever side holds crown), alias
  2 → 1, start_day = min, `sources[2]` holds battle 2's parley.
- Same with 150 m: no merge.
- Groups of the SAME allegiance within 10 m (P1 and P2): no merge.
- A task issued for battle 2 still resolves (`battle_by_id(2)` is battle 1).
- personnel_entries of both survive with their counts; JSON roundtrip keeps
  aliases and sources; a second `day` call the same day changes nothing.
- Town battle 2 absorbs field battle 1 (survivor id 2, town kept).

## Steps

1. Tests red. 2. `scripts/engine/battle_merge.gd`, GameState field, alias
resolution, green. 3. `battle_deployment.md` (or `battle_and_ai.md`, where the
battle lifecycle lives) paragraph and engine `CLAUDE.md` index entry.
4. `--fast` green (+ simulation/gameplay suites); one PR.
