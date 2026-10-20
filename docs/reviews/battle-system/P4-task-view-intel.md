# P4 task target menu intelligence isolation

Scope: `BattlePresentation.task_view` and its target menu only. Dispatcher explicitly narrowed `task_view/target previews` to this menu projection. This step does not accept task quotations or P4 as a whole.

## Reproduced defect and change

On baseline `e7f8e9858680a6585304d6afda2d1fe913008c9d`, transferring a remote enemy's fit personnel to wounded removed its target menu entry. The same changed menu survived JSON save/load. The menu used `_can_fight` and `captured` directly even when the king could not observe that opponent.

Remote opponents now remain named by existing battlefield membership. Live fit/captured filtering applies only within `BattlePresentation.local_unit`'s royal observation boundary. No personnel, order validation, simulation formula, save schema, look resource or task lifecycle changes.

## Acceptance

`tests/engine/test_task_view_intel.gd` checks hidden position/personnel invariance, JSON round-trip equivalence, read-only projection, direct observation of unfit opponents, and hidden versus directly observed capture. Existing task-view, general presentation and merged-warrant checks remain unchanged.

Local check results and frozen input hashes are recorded in the implementation's worktree-local `.superpowers/p4-task-view-intel/HANDOVER.md`. Required current-HEAD CI and independent Review must pass before merge. Pure menu-data regression checks provide no claim of real-window visual review.

## Explicit remaining quotation gap

Actual RED regression also confirmed that zero hidden enemy fit personnel changes a flank quote's refusal from empty to `The designated enemy can no longer be tasked against.`

Call chain: `BattlePresentation.task_quote` → `ActionSystem.validate` → `_validate_task` → `BattleTaskSystem.refusal_of` → `_refusal` → target `_can_fight`/`captured` checks. This PR leaves that chain intact. No error-string masking or relaxed execution validation is introduced.

The dispatcher owns a separate future step after PR #145 and this step are delivered. It needs explicit ownership of `scripts/engine/battle_task_system.gd` and potentially `scripts/engine/action_system.gd`, with quotation invariance and preserved law/affordability/execution rejection checks. Original failing regression and full RED log are preserved under `.superpowers/p4-task-view-intel/quote-regression.gd.txt` and `RED.log` for that step; they are not silently skipped tests in the committed suite.
