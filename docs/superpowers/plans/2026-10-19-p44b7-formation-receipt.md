# P4.4b7 — task formation receipt

Approved spec: `2026-10-17-unit-behavior-and-battlefield-design.md` §§4.1–4.3.

One internal delivery slice: a task warrant with a nonempty formation validates recipient suitability at issue and receipt, then calls BattleFormation.request for that unit only after authority/law/sequence checks. Receipt atomically replaces the task and starts existing CSV reforming costs. Empty formation and cancellation leave the physical deployment/progress/disorder intact; they do not magically undo received preparation. A later explicit formation retargets through the existing longest-disorder rule. Failed/stale/repeated receipt cannot change deployment.

Owned: BattleTaskSystem, its existing task tests, battle_deployment guide and this plan. No public ActionSystem fields, CSV, UI, map or save schema changes. Public BATTLE_TASK still rejects formation, so public integration and visual acceptance remain next work; P4.4b is incomplete.

- [x] Add red tests for receipt-only isolated reforming, suitability atomicity at issue/receipt, real courier/local delivery adapters, cancellation/replacement, disorder/progress and JSON replay. Update existing internal fixtures to include actual battlefield coordinates and suitable personnel for all-shape combinations.
- [x] Reuse BattleFormation.refusal/request in the ledger; do not duplicate costs or progress formulas.
- [x] Run focused task/formation tests, then bounded task/combat/transport/save regressions on frozen inputs; record commands/results/input hashes. Create one PR and hand off once to its sole Sol/medium Review. No third owner.

Review focus: failed formation may not replace current task; pending cancellation cannot touch deployment; late lower sequence cannot re-form; no-formation replacement retains physical costs; general cannot override royal deployment; old no-formation records stay inert; JSON replay cannot reset progress or deadlines.

Verification: six targeted tests failed before implementation. Focused task/formation 30/30 passed. Final frozen-input regression 21 scripts, 184 tests, 1652 assertions, exit 0; command/result/log and 2273 input hashes are in the implementation handover directory. No full/campaign/balance suite or visual acceptance; public formation integration remains deferred.
