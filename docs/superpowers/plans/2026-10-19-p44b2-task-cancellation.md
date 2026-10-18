# P4.4b2 — paid unit-task cancellation

Authorized continuation after merged PR93. One PR and one sole Review.

BATTLE_TASK_CANCEL accepts only request_id, regiment and battle_id. It sends a
player cancellation warrant through the existing unit-task ledger and physical
local/courier path. Internally task=cancel is a terminal control warrant, never
a behavior. Validate live ownership/membership and costs before mutation and
again on receipt; cancellation does not require permission to execute the old
combat action. Keep the current task until receipt. Receipt cancels the current
task with a reason, clears current_id, and advances the same player/overall
sequence barriers so older warrants cannot revive it. Cancellation may arrive
before any pending assignment. No-current cancellation is still a received
barrier. Exact retries, including JSON replay, return the original action
outcome without fees/history/couriers; cross-action ID reuse fails.

Owned: ActionSystem, BattleTaskSystem, existing action/signature/cost tables,
focused dispatch tests, battle deployment guide and this plan. Test red first,
then targeted military/action/courier/save/data regressions on frozen inputs.
Exclude combat effects, formation execution, UI and P6. Deliver one new PR,
then hand off once to its unique Review and stop.
