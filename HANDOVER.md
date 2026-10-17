# P1.1 resumable-day transaction — active handover

## Authorized rule and checkout

- User chose immediate combat within each fixed tactical movement substep: contact → encounter confirmation → one round for each not-yet-fought battle → advance cursor. Later-substep reinforcements join continuing battles for the next day's round. The broader P1–P7 work is authorized; do not ask again.
- Worktree: `/Users/samuelzhang/.codex/worktrees/battle-clock-isolated/game_design`
- Branch/base: `codex/p11-resumable-day-transaction`, base `fe5252a5f805ee7b2e4086aa4e7b57f56fd67b5c`.
- P1.1 is committed as `0b35c15e` and awaits acceptance. Do not start P1.2 until acceptance.

## Current implementation and acceptance

- `TickEngine._resolve_battles` persists substep/contact/fight cursors, records `substep_index` on battle journal events, and removes ended battles before later contact discovery. `finish_day` applies stances once after all substeps. Tactical protocol version 3 rejects old-order saves.
- Acceptance keeps weak/strong campaign separation: weak defense loses its town and enters HOLD on the fall day; the strong walled garrison holds through the assault window and the besieger later retreats under supply rules. It also checks casualty conservation/roster bounds, one round per battle per day, later-substep reinforcement after an earlier same-day round and actual next-day participation, post-capture combat, and deterministic JSON continuation. Observed dates/counts are diagnostics, not targets. The separate no-garrison walled siege also verifies supply-driven retreat.
- Plan, conflict review, engine guide, and this handover describe the approved immediate-substep rule. Historical trace details are diagnostic only.

## Latest verification

- Final `./run_tests.sh --fast` on unchanged code completed: 2,161/2,164 passing, 3 pending owner rulings, 794,192 assertions. The pending tests are the three existing LEDGER galaxy label/hub density checks; no failures. The LLM malformed-JSON tests print expected parser errors while passing.
- Current focused verification: `test_day_resolution.gd` 16/16 (120 assertions); `test_battle_save.gd` 6/6 (37); `test_siege.gd` 40/40 (577); `test_supply_garrisons.gd` 1/1; `test_invasion_end_to_end.gd` 5/5 (135), including both campaign JSON determinism cases; and focused strong-walled outcome 1/1 (33). The reinforcement case verifies same-day higher-substep join and actual next-day participation.
- Independent final read-only review found no remaining concrete defects in the reviewed scope.
- No source changes while a same-worktree test is running. Do not kill other worktrees' tests.

## Remaining work

1. Obtain P1.1 acceptance.
2. Start P1.2 only after acceptance.

## Next phase handoff — P1.2

Bridge the saved `resolve_day` transaction to `GameRoot` and the encounter window. On a blocked day, stop catch-up immediately, clear accumulated clock time, keep the decision pause locked across other windows, and resume the saved transaction before starting another day. Preserve the player's selected 1×/2×/4× speed after manual resume. Add the encounter panel as a request-only view of the saved decision. Use the P1.2 scenarios in `docs/superpowers/plans/2026-10-16-battle-system/01-clock-and-save.md`; run UI and fast suites, then capture real-window pause/resume evidence. No P1.2 source changes are included in this P1.1 commit.
