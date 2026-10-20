# P6.1c — issuing and receiving an area task

Scope: slice c of P6.1 (split in `2026-10-20-p61a-task-coverage.md`). The
`ARMY_TASK` action turns a legal preview into a real, paid, saved order that
reaches each unit by courier (or at once within the king's range). A unit acts
only on the revision it has RECEIVED; nothing moves yet (d executes).

Approved design: spec `2026-10-16-battle-system-design.md` §13.1 (drawing and
previewing are free; the order pays; within the king's command range delivered
on the spot, remote orders pay and send a courier; the real task is saved apart
from paper war plans; a changed circle is a new order that takes effect only
when delivered; flags: hollow pending, solid received), §13.6 (pending → … ;
changing or cancelling takes courier time; deleting a map mark never cancels a
real task); P6 plan P6.1 "Interfaces" (`issue`, `receive`; per-unit
received_revision; a group of units does not pretend to receive at once).

## Contract

- **Saved** `GameState.army_tasks` (id → task, default `{}`): `{id, kind,
  unit_codes, center_x_m, center_y_m, radius_m, known_target_id,
  encounter_policy, supply_floor (0 until f), return_target (the units' camp or
  seat at issue, by unit), revision, issued_day, units: {code: {status:
  "pending"|"received"|"cancelled", received_revision, received_day}}, history:
  [{day, revision, status, unit, reason}]}`. Ids from a saved counter
  (`army_task_next_id`).
- `ArmyTasks.issue(repo, state, task) -> Dictionary`: runs `preview`; refused →
  no state change; ok → a new task (revision 1) or, for `task.id` of an
  existing task, the next revision (same units, new circle/kind/target/policy).
  Each unit becomes `pending` for the new revision (an older received revision
  keeps acting until the new one arrives).
- `ArmyTasks.receive(repo, state, task_id, revision, unit) -> Dictionary`: a
  courier's (or local) delivery; accepts only a revision newer than the unit's
  received one; sets `received`; a stale one is recorded as superseded; a
  cancel revision sets `cancelled`.
- **Action** `ARMY_TASK` (and `ARMY_TASK_CANCEL`) in `ActionSystem`: validate
  through `preview`; pay `OrderCosts` (row added in b) once per issue; per unit,
  deliver locally when `KingSystem.can_command`, else dispatch one courier per
  unit via the existing courier path (an order kind the courier carries;
  implementer: follow how `BATTLE_TASK` rides couriers, incl. `joinable`),
  which calls `receive` on arrival; a lost/expired courier leaves that unit
  pending with a reason. `action_signatures.csv` rows as other actions have.
- Exact retry by request id returns the saved result before costs (as
  BATTLE_TASK).

## Implementer rulings pending the owner

1. Revision semantics for a changed circle; cancel as a revision.
2. One courier per unit vs one per task batch (follow the existing courier
   batching rules; record what applies).
3. `return_target` captured at issue.

## Hand checks (tests/engine/test_army_task_orders.gd)

- Issue a search for two units, one within the king's range, one far: cost paid
  once (+ one courier fee), unit A `received` revision 1 at once, unit B
  `pending`; after the courier's ride B `received`.
- Re-issue (revision 2) before B's first courier arrives: B ends with revision
  2; the revision-1 courier arriving late is superseded.
- A refused preview (fleet) changes nothing and pays nothing.
- Exact retry of the same request id: same result, no second payment.
- JSON roundtrip mid-ride keeps the task and the pending courier.

## Steps

1. Tests red. 2. Code + CSV rows green. 3. "Area tasks" paragraph in
`scripts/engine/guide/regiments.md` (size cap: keep it tight). 4. `--fast`
green; one PR.

## Implementer rulings (filled in P6.1c; pending the owner)

1. **Revisions**: a changed circle/kind/policy is the SAME task id with `revision + 1` (request carries `task_id`, same unit set required); each revision is a saved snapshot (`revisions["n"]`). A unit's `received_revision` only rises; an older one arriving later is `superseded` (history line, no state change). Cancel (`ARMY_TASK_CANCEL`) is a revision with `cancel: true`; a unit that receives it is `cancelled`, and `ArmyTasks.acting` is `{}` for it. A unit's status is `received` only when its received revision is the task's newest, else `pending` while the newer one rides.
2. **Couriers**: one courier ORDER per unit (a courier targets one regiment, as for every order); the existing `CourierSystem.joinable` rule still lets an order ride with a courier already waiting for that unit, and then no new fee is paid. The fee is one ordinary courier fee per unit that needs a NEW courier.
3. **return_target**: the unit's position in whole metres at first issue (`{x_m, y_m}` by unit); a revision keeps it. Camp/seat resolution is left to slice d.
4. **ARMY_TASK_CANCEL** gets its own cost row, signature row and `policy_actions_domain` rows (`ARMY_TASK` too, so `data.actions` knows them).
5. **Preview cost changed (b's `ArmyTasks.preview`)**: the courier fee is now per remote unit via `courier_fees`, not one flat fee for the batch, so the quote equals what is paid. Single-unit behaviour is unchanged (test_army_tasks.gd passes untouched).
6. **Lost / expired courier**: `ArmyTasks.lapse` writes a `lapsed` history line with the courier's reason; the unit's status and received revision stay as they were (no automatic resend).
7. **Law recheck at receipt** is not done here (BATTLE_TASK does it; the area task's laws are re-read by slice d when it acts).
8. Request replay data lives in `army_tasks[id].requests[request_id] = {task_id, params, outcome}`.
