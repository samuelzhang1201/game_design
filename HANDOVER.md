# Battle system P3 handover

## Goal and authorization
Continue the already-approved autonomous implementation of the battle-system plan. Work in this managed worktree only. This checkpoint closes P3.1 (physical king location, movement/following, command radius and dispatch origin) and hands off to P3.2 field camps. Do not restart planning or ask for approval.

## Checkout
- Worktree: `/Users/samuelzhang/.codex/worktrees/battle-system/game_design`
- Branch: `codex/battle-system`
- Base before P3.1: `ffacff09` (`feat: seed king position for courier dispatch`)
- P3.1 commit: fill in after commit.
- Original checkout `/Users/samuelzhang/game_design` is not a target for game edits.

## P3.1 delivered
- Persisted whole-metre king position and route; deterministic daily movement, follow/rendezvous, safe departure and physical battle-radius checks.
- Derived, non-cumulative battle morale support.
- Typed KING_MOVE / KING_FOLLOW / KING_SAFE_DEPARTURE actions with authored cost/signature data.
- Battle reports outside the king's range dispatch a paid report courier from battle event coordinates, track the moving king, and persist in transit.
- Added engine/data guide rules and king movement/report tests.
- Relevant spec/plan: `docs/superpowers/plans/2026-10-16-battle-system/03-king-and-camps.md`, section P3.1; `docs/superpowers/specs/2026-10-16-battle-system-design.md` §11.

## Checks
- Targeted king/courier/battle/data suite: 52/52 passed; king tests 11/11 passed; stance-menu regression 8/8 passed.
- Final `./run_tests.sh --fast`: 2313 total, 2312 passed, 0 failed, 1 existing LEDGER War density Pending. Log: `/tmp/p3-king-fast-final2.log` (GUT output was `/private/tmp/gut_test_output_26888.txt`, removed by runner).
- Independent `tests/engine/test_ledger_galaxy.gd`: 16/17 passed; its unrelated performance tripwire measured 123.1ms against 120ms. Earlier run 129.4ms. No king code involved.
- `git diff --check` passed before final handover edits.

## Next task: P3.2 field camp state
Read this file, verify branch/status, then inspect only P3.2 in the plan and the applicable army/battle guidance and code. Implement `CampSystem` / saved `camp_state` per P3.2: building, camped, packing, daily progress, one full packing day, deterministic blocked-day/save-resume behavior, combat preserving packing progress. Add focused GUT tests and update engine guidance. Keep changes bounded to engine/data/tests/docs owned by P3.2. Run affected test files, then `./run_tests.sh --fast` before its commit. Stop after P3.2 is committed and update this handover for P3.3.

## Files and unrelated work
P3.1 owns: `scripts/engine/king_system.gd`, `battle_system.gd`, `courier_system.gd`, `tick_engine.gd`, `action_system.gd`; `data/army/balance.csv`, `data/council/policy_actions_court_additions.csv`, `data/realm/action_signatures.csv`, `data/realm/order_costs.csv`; `data/CLAUDE.md`, `scripts/engine/CLAUDE.md`, `scripts/engine/guide/development.md`; `tests/engine/test_king_system.gd`.

There are many unrelated dirty portrait/imagegen/pipeline/P3 inventory files in this worktree. Do not stage or alter them. Stage only the explicit P3.1 paths above. No active test process remains after the final fast suite.

## Known risks
- No visual implementation was done in P3.1.
- Report courier fee is charged from the ordinary courier kind and records its reason in king state; review whether the game should expose an economy ledger line in a later polish pass.
- LEDGER performance baseline above is a pre-existing unrelated failure.
