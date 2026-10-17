# Battle system P3 handover

## Goal and authorization
Continue the already-approved autonomous implementation of the battle-system plan. Work in this managed worktree only. P3.1 (physical king location, movement/following, command radius and dispatch origin) and P3.2 (field camps) are implemented and committed. Continue with the approved P3.1 acceptance repairs, then proceed through the approved battle-system phases. Do not restart planning or ask for approval.

## Checkout
- Worktree: `/Users/samuelzhang/.codex/worktrees/battle-system/game_design`
- Branch: `codex/battle-system`
- Base before P3.1: `ffacff09` (`feat: seed king position for courier dispatch`)
- P3.1 commit: `ba3de2c4` (`feat: add physical king movement and battle presence`).
- P3.2 commit: this handover’s containing commit, `feat: stage camps and enforce a full packing day`.
- Original checkout `/Users/samuelzhang/game_design` is not a target for game edits.

## P3.1 delivered
- Persisted whole-metre king position and route; deterministic daily movement, follow/rendezvous, safe departure and physical battle-radius checks.
- Derived, non-cumulative battle morale support.
- Typed KING_MOVE / KING_FOLLOW / KING_SAFE_DEPARTURE actions with authored cost/signature data.
- Battle reports outside the king's range dispatch a paid report courier from battle event coordinates, track the moving king, and persist in transit.
- Added engine/data guide rules and king movement/report tests.
- Relevant spec/plan: `docs/superpowers/plans/2026-10-16-battle-system/03-king-and-camps.md`, section P3.1; `docs/superpowers/specs/2026-10-16-battle-system-design.md` §11.

## Checks
- P3.2 focused camp/army/movement/battle/courier/AI/supply/tick suite: 150/150 passed.
- P3.2 final `./run_tests.sh --fast`: 2324 total, 2323 passed, 0 failed, 1 existing LEDGER War density Pending.
- P3.1 acceptance repair session must rerun targeted checks and the final fast suite after fixes.

## Next task: P3.1 acceptance repair
The first P3.1 implementation passed its original checks, but the existing source audit identified acceptance gaps. Repair them in the existing authorized sequence; read `/Users/samuelzhang/game_design/.superpowers/session-handovers/king-repair-HANDOVER.md` and `.superpowers/sdd/2026-10-16-battle-system-implementation/p3-king-acceptance-audit.md` first. Preserve the accepted P3.2 camp behavior and tuning. The audit calls out unbounded/stale king follow; impassable fallback routes and safe-departure teleport; fixed supply rear accidentally following king; immediate remote intelligence leakage and empty report payload; unauthorized automatic-report fee; local dispatch and immutable origins; follow target/detach/order-cost gaps. Add focused hand-computed tests, obtain independent review, then run the final fast suite and commit. Continue the approved battle-system phases after that repair.

## Files and unrelated work
P3.1 owns: `scripts/engine/king_system.gd`, `battle_system.gd`, `courier_system.gd`, `tick_engine.gd`, `action_system.gd`; `data/army/balance.csv`, `data/council/policy_actions_court_additions.csv`, `data/realm/action_signatures.csv`, `data/realm/order_costs.csv`; `data/CLAUDE.md`, `scripts/engine/CLAUDE.md`, `scripts/engine/guide/development.md`; `tests/engine/test_king_system.gd`.

There are unrelated dirty portrait/imagegen/pipeline/P3 inventory files in this worktree. Do not stage or alter them. P3.2 stages only its owned engine/data/tests/docs files and this handover. No active test process remains after the final fast suite.

## Known risks
- No visual implementation was done in P3.1.
- Report courier fee is charged from the ordinary courier kind and records its reason in king state; review whether the game should expose an economy ledger line in a later polish pass.
- LEDGER performance baseline above is a pre-existing unrelated failure.
