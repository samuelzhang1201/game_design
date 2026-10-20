# P4.4e4 — a merge carries in-flight warrants and shows them on the survivor

Scope: the last slice of P4.4e, fixing two gaps in e1's merge (found by review
on #132): (1) pending side warrants (`BattleOrders`) of the absorbed battle keep
their original `request.side` and `targets`, so when the absorbed battle's
att/def orientation is the opposite of the survivor's, delivery checks the
stale side and invalidates a valid in-flight courier; (2) the presentation
(`BattlePresentation.warrants` and the unit-task view) compares a stored
`request.battle_id` directly with the survivor's id, so after a merge pending
warrants and even an active unit task vanish from the battle UI.

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md`
§11.1 (orders, costs and dedupe marks migrate; nothing re-runs; the stable
survivor id with source aliases), §4 (a delivered task stays the unit's one
primary task).

## Contract

- `BattleMerge._merge`: for every PENDING `BattleOrders` warrant (implementer:
  find where they are stored and their request shape) whose battle is the
  absorbed one, rewrite `request.side` (and any per-side `targets`) to the side
  its units now stand on in the survivor (by the same allegiance map used for
  the union); keep its id, sequence, cost receipts and courier untouched; add a
  `merge_remap: {from_battle, from_side, to_side, reason}` note. Delivered /
  terminal warrants are history and stay as they were.
- Every presentation filter that compares a stored battle id with a battle's id
  uses `BattleSystem.canonical(state, id)` (grep `battle_presentation.gd`,
  `war_room` folio/task readers and any UI-facing engine helper for
  `battle_id ==` / `["battle_id"]` comparisons; scripts/ui and scripts/war_room
  must not read `Game` from war_room — keep to the existing bridges).
- No CSV key.

## Implementer rulings pending the owner

1. Only pending warrants are remapped; history stays as recorded.
2. The list of presentation filters switched to canonical ids.

## Hand checks (tests/engine/test_battle_merge_warrants.gd)

- Battle 1: crown P1 att vs foe F1 def. Battle 2: foe F2 att vs crown P2 def
  (opposite orientation). A pending side warrant for battle 2's crown side
  (`def`, targets [P2]) is issued; merge (survivor 1, P2 → att). Delivering the
  warrant succeeds and applies to the att side; its `merge_remap` note names
  def → att.
- Same with the same orientation: side unchanged, no remap note.
- `BattlePresentation.warrants` for battle 1 after the merge lists the pending
  warrant issued for battle 2; the unit-task view for P2 shows its active task
  issued for battle 2.

## Steps

1. Tests red. 2. Code green. 3. One sentence in the merging paragraph of
`scripts/engine/guide/battle_and_ai.md` (near its size cap: keep it short).
4. `--fast` green; one PR.

## Implementer rulings (recorded)

3. `request.side` is rewritten, `request.battle_id` stays the original id (it resolves by alias). Targets are unit codes, not per-side, so they are unchanged.
4. `merge_remap` keeps the FIRST `from_battle`/`from_side` across chained merges and updates `to_side`/`reason`; no note when the side does not change.
5. `BattleOrders.issue`'s idempotent retry compares the stored request with `side` restored to `merge_remap.from_side`, so a courier retry of the original request is still the same warrant (not "id names another warrant").
6. Presentation filters switched to `canonical`: `BattlePresentation.warrants` and `task_view` (ledger loop). `battle_report`, `battle_task_system`, `battle_orders.end_battle` already used it; war_room and ui compare no stored ids.
7. No existing assertion adapted.
