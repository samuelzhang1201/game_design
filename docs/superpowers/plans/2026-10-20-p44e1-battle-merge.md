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

## Implementer rulings (as built)

1. Contact is group-to-group (any saved group of a crown unit against any of a foe unit, `battle_group_contact_m` inclusive, squared whole metres); anchors alone never trigger.
2. Survivor = lower id unless only the other holds a `town`.
3. Merging runs once per day, inside `BattleSystem.prepare_day` (after deploy/refresh, before withdrawals and detection). A mid-day substep (`discover_contacts`) never merges: left to a later slice. A battle with a non-empty `pending_round` (either one) is skipped, so no half-resolved round is ever re-labelled.
4. Every key a battle dict can carry, and how it merges (survivor S, absorbed G; "S wins" = a key already in S is kept):
   - `id`, `town`, `place_x_m`, `place_y_m`: S's (the town rule picks S); G's place is kept in `sources`.
   - `att`, `def`: union by allegiance via `_side_for`, S members first, no duplicates (no `battle_max_units` cap re-check: nobody is dropped).
   - `start_day`: min. `rounds`: max. `last_resolved_day`: max. `deployed_day`: max.
   - `personnel_entries`, `unit_entries`, `unit_formations`, `reserves`, `abandoned_supplies`, `event_checks`: per-key union, S wins; `side` inside personnel/unit entries, `reinforcement_evidence` and `abandoned_supplies` is re-read from the merged sides.
   - `reinforcement_evidence`, `withdrawal_costs`, `event_modifiers`, `event_reinforcements`, `event_reinforcements_consumed`, `report_events`, `family_changes`: list union in order, no equal entry twice.
   - `groups`, `group_facing`: rebuilt by `BattleGroups.refresh` (no unit moves).
   - Side-level, kept verbatim under `sources[<G id>]` and NOT folded: `parley`, `commanders`, `commander_nominees`, `actions`, `formations`, `routed_side`, `inspire_cooldown`, `inspire_until`, `start_day`, `place_x_m`, `place_y_m`. A G unit with no `unit_formations` entry gets a copy of G's side formation so its formation does not change silently. G's own earlier `sources` are carried.
   - `pending_round`: never present at merge (blocks it). `report_outcome`: only set when a battle ends; not merged.
   - `sources` itself is new (S's own kept; G's added).
5. The absorbed side-level state stays under `sources` until e2/e3; absorbed units now act on S's side action (`BattleOrders.kind`) until e2/e3.
6. Outside the battle dict: `GameState.battle_aliases` (string id -> int id, saved; old saves `{}`); `battle_events` records with `battle_id` == G are re-pointed to S, and `BattleEvents._offer_record` treats a same-day record for S under another token as today's check (no second roll). `BattleSystem.canonical` is used by `combat_action`, `BattleOrders.end_battle` and the report's prisoner/warrant filters; `step_battle` removes the battle by its real id (a step through an alias fights the survivor once, guarded by `last_resolved_day`). `battle_holder:<id>:` custody event ids keep the absorbed id (custody lines of a merged battle's report may omit pre-merge holder events; left to e2/e3).
7. Event: `{kind: "merge", battle_id: S, absorbed: G, reason}`; journaled into S's `report_events` directly (`BattleReport.note`); no report template row yet.
