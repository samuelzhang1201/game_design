# P4.4b5 — delivered unit pursuit

Scope: received royal pursuit tasks enable the existing withdrawal pursuit context, only through the recipient and for its designated available withdrawing enemy (or available withdrawing opponents when unspecified). Reuse attack strength, supply and atomic daily settlement. Ordinary task attack grants no pursuit; retain legacy side action compatibility. No new movement, search, distance, region, formation or visual behavior.

Approved design: `2026-10-17-unit-behavior-and-battlefield-design.md` §§4,9–10. Existing automatic P4.4b continuation authorizes this single slice.

Owned: battle_task_system.gd, battle_system.gd, test_battle_task_combat.gd, battle_deployment.md and this plan. Callers: unit_action, unit_strength, side_power, daily engagement/cost/loss planning and combat_context. No dispatch, save schema, data or export changes.

1. Add failing received/pending isolation, target/protection/cancellation and JSON frozen-round tests.
2. Resolve pursuit as attack only against an available withdrawing target; retain pursuit authorization and target in the frozen action. Existing legality/control/supply checks remain binding.
3. Derive withdrawal context from actual lawful attacking pursuers, using per-unit rates where targeted enemies differ. Reuse single casualty and cost writers.
4. Run focused battle/task/transport/save/law regressions on frozen inputs, commit and create one PR. Hand off once to its unique Sol/medium Review; it fixes in scope, checks CI and merges before one next authorized P4.4b slice. Stop after P4.4b; no agents or third owner.
