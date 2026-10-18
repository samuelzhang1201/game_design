# P4.4a — canonical unit task warrants

This is the first bounded implementation step of the authorized P4.4 design,
§4 (authority and delivered orders). The current harness requires one small
problem per PR. Implementation owns this PR until its single Review handoff;
Review fixes it and merges only after current-HEAD checks pass.

## Acceptance

- One saved `GameState.unit_tasks` ledger owns each unit's pending warrants,
  current task, monotonic issued/received sequence and terminal receipts.
- Seven tasks and the four existing formations are independent fields. A
  replacement takes effect only on delivery. Replaying a request is inert;
  conflicting IDs and late deliveries cannot replace the current task.
- Issue and delivery validate live unit membership, issuing authority and
  battlefield law. A general can assign unassigned units, never replace a
  player's active task. No risk score or morale threshold vetoes receipt.
  A later general deployment cannot invalidate the only in-flight royal task;
  the player's receipt sequence is tracked separately from the overall maximum.
  Pursuit requires a player task until a validated contact-plan path is wired.
- Every saved transition records source, world day and reason. JSON replay
  preserves pending/active tasks and receipts; old saves acquire an empty ledger.

## Owned files

`scripts/engine/battle_task_system.gd`, `scripts/engine/game_state.gd`,
`scripts/engine/data_repository.gd`, `data/battle/behaviors.csv`, `data/tables.csv`,
`scripts/engine/battle_rules.gd`, `tests/engine/test_battle_tasks.gd`,
`scripts/engine/guide/battle_deployment.md`
and this plan.

## Execution

1. Write failing ledger tests, including out-of-order receipt and JSON replay.
2. Implement the pure warrant ledger and indexed task definitions. Like
   `BattleOrders.issue/deliver`, these are internal operations, not player
   actions; they neither dispatch a courier nor spend resources themselves.
3. Run task, save/law/data/isolation regressions and final fast on frozen inputs.
4. Commit/push one PR; checkpoint and hand off to its unique Review session.

## Following P4.4 steps (separate PRs, after the preceding merge)

P4.4b wires the ledger into ActionSystem/OrderCosts and real local/courier
delivery, including cancellation and unit-scoped continuing orders. P4.4c owns
integer walk/run costs and carry plus known-target search/pursuit bounds.
P4.4d owns representative-group positions, movement ownership and legal contact
feeding combat. P4.4e owns compatible actual-contact battle merging and all
source-scoped terms, aliases, commander succession and deduplication. The WAR
ROOM task interface and visual-review follow the executable task path within
P4.4. No P6 work is included. P4.4 as a whole remains incomplete until these
acceptances and their integration checks pass.
