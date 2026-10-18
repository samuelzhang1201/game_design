# P4.4b4 — delivered unit withdrawal

Scope: resolve a received retreat task through BattleSystem's existing withdrawal API. No pursuit, formation, new movement module or visual change. Approved design: unit-behavior-and-battlefield §10; predecessor checkpoint supplies continuation authority.

Owned: battle_task_system.gd, battle_system.gd, battle_deployment.md, focused test_battle_task_retreat.gd and this plan. Callers are BattleSystem's action/strength and exit resolution; dispatch/courier, save schema, data and exports retain existing contracts.

1. Add failing tests for pending/received recipient isolation and real packing/route separation.
2. Extend received action resolution to retreat and reuse _start_retreat from existing exit checks. Actual withdrawal remains authoritative after task cancellation/replacement.
3. Check unreachable routes, current eligibility/terms, JSON and failed casualty retries without repeated withdrawal costs. Run focused battle/camp/courier regressions on frozen inputs.
4. Commit one small PR and hand off once to its sole Sol/medium Review. Review owns fixes, required current-HEAD CI and merge; only after merge may it start the next authorized P4.4b slice.

Review focus: old pending rounds must preserve frozen actions; no added side-wide retreat, teleportation, camp deadline bypass, route immunity or duplicate supply/morale costs. Reuse the existing single writers for fees, casualty and daily meals. Legacy side withdrawal semantics remain binding.
