# P4 task quotation intelligence boundary

Step: `p4-task-quote-intel`. Implementation: `01a15a12-075f-7282-9c98-30ea9fa2dd89`. Unique Review: unassigned until implementation handoff. Dispatcher alone owns successors.

## Scope and acceptance

A task quotation must remain identical when only unobserved enemy fit personnel, capture or position changes. Current direct royal observation may refresh the target condition. Unknown/friendly targets, own incapacity, received laws, battlefield agreements, formation suitability, request validity and actual affordability must still constrain the quote. Actual issuance, delivery and combat retain their real-state validation. No save schema, simulation formula, UI look or combat geometry changes.

Owned source: `battle_presentation.gd`, `action_system.gd`, `battle_task_system.gd`; rule: `guide/battle_events.md`; regression: `test_task_quote_intel.gd` and UID; this report. PR154's ranged files are excluded.

## Root cause and minimal implementation plan

`BattlePresentation.task_quote` calls `ActionSystem.validate`, which reaches `BattleTaskSystem._refusal`. Its designated-target predicate reads live fit/captured enemy state even when the king has no direct observation. The menu's existing intelligence boundary does not protect this second read.

1. Reproduce using equal observer evidence, real campaign personnel and JSON replay. Keep full red-run evidence in the worktree checkpoint directory.
2. Carry an explicit target-observation argument through quote validation to the shared task refusal. Ordinary validation defaults to actual condition checking; execution and receipt keep that default. Split target membership from condition so preview cannot authorize unknown or friendly targets. Do not mask refusal strings or replace enemy truth with invented state.
3. Run the new regression and connected presentation/task dispatch, receipt, combat, formation, tracking, bounds and isolation checks through the shared Godot lock on frozen inputs. Record exact results/hashes in the checkpoint.
4. Create one PR and one independent Sol/medium Review; register one-to-one handoff and stop implementation. Review owns fixes, all required current-HEAD CI, acceptance and merge.

## Verification

Baseline `5a551e50d2705276175b04912896b91c158a5c59`: red regression produced 2 failing tests of 4 (hidden personnel/capture altered the quote before and after JSON; hidden condition also masked law/affordability reasons). Final shared-lock runner: 13 scripts, 134 tests, 1261 assertions, all passed, exit 0. This includes the new four-test regression, existing task view/dispatch/receipt/combat/retreat/formation, pursuit bounds/route/merge continuity, engine isolation and guide caps. Frozen input SHA-256: `ada1535b23c82edabdcfb628cf05d4583728148cade251768ead48665326e8c4`; exact commands and full logs remain in `.superpowers/p4-task-quote-intel/`. `git diff --check` passed. Required current-HEAD CI and independent Review remain mandatory before merge. No visual acceptance is needed because this step changes no look resources. Full campaign/balance sweeps are outside this bounded defect.
