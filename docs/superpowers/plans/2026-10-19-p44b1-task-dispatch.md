# P4.4b1 — paid unit task dispatch

Authorized subset of P4.4b, after merged P4.4a (PR89). One PR, implementation
and its sole Review. This step connects the canonical ledger to physical
receipt, without changing combat resolution.

Acceptance:
- BATTLE_TASK accepts request_id, regiment, battle_id, task and optional
  target_unit only; authority is always player and scope is exactly one unit.
- Validate law, live membership, realm ownership and affordability before any
  mutation. Pay the OrderCosts filing fee once and a new ordinary courier fee
  only when dispatched. Reserved battlefield gold cannot fund the request.
- Local receipt uses existing king command range. Remote dispatch remains
  pending until courier arrival, rechecks law/membership, and terminates on
  lost target or courier deadline. A merged courier carries separate warrants.
- Exact retry (including after JSON save) returns its original outcome without
  payment, new courier or history; conflicting IDs/extra authority fields fail.
- A late warrant cannot replace a newer receipt or another unit's task.

Owned: ActionSystem, BattleTaskSystem, CourierSystem; action, signature and
OrderCosts CSV rows; focused task dispatch tests; battle deployment guide;
this plan. Test first, implement, targeted regressions, then selected functional
checks on frozen inputs. Deliver one PR and one Review handoff, then stop.

Ruling: split the broad P4.4b integration here. Cancellation, combat continuing
orders and formation execution are separate follow-on steps. The action does
not expose formation until its unit-scoped execution is wired; the existing
ledger retains its internal independent formation field. No UI/visual change.
