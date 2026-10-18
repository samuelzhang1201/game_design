# P4.4b3 — delivered unit attack/hold actions

Authorized by the predecessor checkpoint; implement inline, one PR, one sole
Sol/medium Review. No new planning approval or additional owner is needed.

Scope: BattleTaskSystem resolves received advance/flank/charge to existing
attack and defend/guard_flank to hold. Charge checks its own legality and reuses
attack's existing costs/factors; no positional bonus. Unsupported movement tasks
retain existing side behavior. Routing/actual retreat wins. Pending tasks never
participate. Live laws/terms and unit/target membership constrain execution.

Owned: BattleTaskSystem, BattleSystem, focused test_battle_task_combat.gd,
battle_deployment/prisoners_and_reports guides, BattleReport and this plan. No data/formula changes.

1. Add failing tests using real campaign personnel: receipt-only unit factors,
   replacement/cancellation, live law and target loss, mixed attack/hold daily
   power/morale/costs, depleted-unit fallback, JSON pending-round retry and
   same-day inert settlement.
2. Add a pure unit combat-action resolver, reuse it for unit strength/morale,
   engagement and attack-context checks. Preserve side defaults for unassigned
   units and legacy side fallback. Freeze actual unit actions with the day's
   saved casualty plan so retries use the same effects and extra supply costs.
3. Run focused battle/task/courier/day/save regressions, then affected functional
   selection once on frozen inputs. Commit/push a new PR; hand off once to its
   unique Review. Review owns fixes and current-HEAD CI/merge, then stops.

Review focus: stale battle IDs cannot affect a new battle; ceasefire after receipt
blocks combat; one unit's depleted supplies cannot veto another's explicit task;
cancel in flight keeps the old task; failed personnel commit plus JSON reload
must consume neither another RNG draw nor another extra supply charge.

Excluded: formations, retreat/pursuit movement, run/search, group contact,
battle merging, UI, P6. P4.4b as a whole remains incomplete.

Ruling: canonical side/code ordering in BattleReport is in scope: a terminal
retry exposed insertion-order differences after JSON. Freeze report participants
and their supply lines in that order; no battle outcome or public access changes.

Ruling: shock context counts only mounted personnel actually attacking; held
cavalry cannot grant a foot task that existing attack effect. The focused test
uses 600 mounted + 600 foot, crew one and a 400-per-mille threshold: holding
mounted contributes zero; attacking mounted contributes 500 per mille. Pursuit
context retains the existing side-order authorization; a task attack alone
does not authorize it. Final local regression is the bounded battle/task,
courier, day transaction, supply, save, isolation and guide scripts recorded in
checks-command.txt; broad category exploration was superseded, not a pass.
