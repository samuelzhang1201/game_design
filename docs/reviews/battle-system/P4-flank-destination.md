# P4 reachable flank destination

Step `p4-flank-destination`; implementation `01a15a34-3077-7162-8b5b-d044300df472`. Sol/medium is authorized for known-state geometry, group facing and saved task integration. The sole Review is assigned at handoff; no subagents or third participants.

Received targeted flanks select the shorter of two outboard terrain-checked approaches from the recipient's own visible target position, facing and group geometry. Field travel keeps normal packing and saved march budgets; battle movement replaces only that recipient's generic deployment and stays within its daily metre budget. Actual group contact commits the approach. The existing single formation flank factor requires real side/rear contact and disappears when the target faces the incoming group. No task label or distant opposing anchor grants a bonus.

Known geometry and whole-metre corners survive JSON. Unseen position/facing changes cannot steer the route. Observed displacement supplies a field column's heading when it has no explicit facing. Lost sight retains the known route and finite search; a visible field target that is captured or wounded-only completes the task. A committed approach cannot revive after leaving battle or through a synonymous receipt on the same canonical battlefield. Old battle tasks cannot turn a new battlefield's groups. Switching to flank discards unfinished charge momentum while preserving a previous impact's disengagement/regrouping obligation.

## Acceptance evidence

Frozen runtime/test input SHA-256: `f04fae6e0739f16be9b8230a2608ac27c14a227d507b931ccb87786f61bf952d` (base `75e10a30093a1a56245c42050528f62b7dd6ca91`). The worktree's `.superpowers/p4-flank-destination/frozen-inputs.json` lists inputs; `validation.json` retains exact commands, results and log hashes. Inputs were rehashed unchanged after the final run.

- Convergence: 3 scripts, 34/34 tests, 318 assertions.
- Final targeted regression through the shared Godot lock and `run_tests.sh`: 25 scripts, 289/289 tests, 2,170 assertions, exit 0. Includes tasks/dispatch/combat/retreat/view, formations/groups/deployment, charge, known-target tracking, pursuit limits/merge continuity, ranged geometry, terms, save, strength, resolution/events/merge, engine isolation, data layout and guide caps.
- The 12 new flank tests cover real courier receipt and day resolution, saved field substeps and JSON continuation, failed personnel settlement and frozen retry/RNG, hidden-state invariance, visible incapacity, heading changes, actual contact and turning, stale battle identity and charge interruption. Initial and intermediate RED logs retain the observed missing behavior; they are not reused as frozen verification.
- Hand geometry: one 50-person group facing west at `(11000,10000)` has a northern contact point `(11000,9900)`. Starting at `(10000,10000)`, the approach walks 100 m across and 1,000 m along, with each battle step bounded to 50 m in the fixture. Turning the target north makes that same contact frontal. The compact rank contributes exactly one `850` flank factor. A blocked northern endpoint chooses the reachable 600 m southern route; a severed land component yields no route. A deep wedge contacts its actual side group instead of stopping at its bounding circle.
- Battle balance CSV columns/unique keys and `git diff --check` pass. No full local suite, duration sweep or UI/art acceptance is claimed. Required current-HEAD CI remains the sole Review's merge gate.

## Boundaries

Owned changes are BattleTaskSystem, BattleGroups, BattleFormation, the battle balance/guide, scoped formation test, new flank tests and this report. ArmySystem/BattleSystem need no edits. BattleMerge/BattleRanged remain untouched for the parallel step.

The planner compares two explicit outboard routes; a terrain router shortcut through known enemy contact circles is rejected and blocked group corridors wait. Exhaustive battlefield deployment-capacity routing and temporary interceptor self-defence remain separate dispatcher-owned steps. A committed task has no automatic second disengage/regroup/circle cycle; repositioning requires a different received task. No extra attack multiplier, RNG stream, clock, movement budget or model call is introduced.

## Independent Review

Sole Review `01a15a49-6fcb-73b3-a66d-08f31a3476f7` reviewed receipt, known-target geometry, real deployment/contact, turning, charge continuity and saved retry paths. Fresh flank/formation verification passed 23 tests and 264 assertions.

Final CI exposed a fixture conflict: the ordinary-day resume test expected treasury 100 while a commander battlefield choice could spend 7 gold. The failure reproduced locally (21/22 passing). The dispatcher appended that test file to this step. The test now clears its copied event definitions to isolate monthly settlement; it retains the original treasury assertion and production event costs. The affected day-resolution, flank and battle-event scripts pass 57/57 tests, 549 assertions, exit 0 through the shared Godot lock. Final current-HEAD CI remains required before merge.
