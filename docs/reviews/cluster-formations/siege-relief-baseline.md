# CF-P2-siege-relief investigation checkpoint

- Dispatcher: `01a17398-42c1-7583-8d3f-7b15e877586c`; implementation: `01a19316-ad13-7a22-9480-100381b12a34`; Review: `01a19329-d612-71e1-a7ba-028000e2c689` (Sol/medium, created once).
- Authorization: dispatched bounded siege-relief baseline failure investigation; dispatcher start confirmation received. Dispatcher confirmed cumulative scope registration of this report and `tests/engine/test_siege.gd` on 2026-11-01. No other repository files are owned.
- Checkout: `/Users/samuelzhang/.codex/worktrees/cluster-siege-relief/game_design`; branch: `codex/cluster-siege-relief`; HEAD: `9e4bbecd83c25c595b8f43229305c7cd9360db2c`.
- Acceptance: preserve authored relief intent, all original assertions, expected values, fixtures, data and thresholds. Observe actual combat, without forced rout, fake attack or weakened gates. Separate from CF04aR and P1.

## Existing RED evidence

`/tmp/legacy-retreat-baseline.log` records four failed assertions in `test_relief_force_joins_battle_and_can_lift_siege`: no besieger disengaging, SIEGE rather than RETREAT, progress 455 rather than 0, no lifted notice. Its other failing invasion test belongs to P1 and is outside this step.

`/tmp/legacy-siege-probe.log` records the real first round: attacker power 44, defender power 66, odds 400, draw 803, effective value 490, stalemate, no exit. This is not the P1 early-return receipt failure.

Hand check: `1000 * 44 / (44 + 66) = 400`; integer `(803 - 500) * 300 / 1000 = 90`; effective 490 lies in `[400, 600)`, the authored stalemate tier. The original scenario assumes immediate rout after this single round. Current group rules explicitly seed at actual anchors, do not deploy on contact day, and count still-approaching personnel at the reserve share. Current battle rules allow continued rounds until actual rout/morale collapse/separation, with no one-round guarantee.

## Diagnostic result (isolated battle observer)

A temporary `/tmp/test_cf_p2_siege_observe.gd` copies the original test, retains all its original assertions and setup, and inserts only normal subsequent `BattleSystem.settle_day` calls with advancing running day before the final withdrawal observation. It logs round power, odds, draw, effective tier and actual exit receipts. No fixture, tuning or delivered action changes. This tests whether the assertion observes too early; it is not yet a proposed repository change.

The diagnostic command waits for the shared `/Users/samuelzhang/game_design-wt/godot_lock.sh` lock, then imports and runs only that filtered test, offline with existing pre/post hooks and timeout. Logs: `/tmp/cf-p2-import.log`, `/tmp/cf-p2-observe.log`. An initially queued full siege rerun was cancelled by terminating only this step's waiting shell before lock acquisition; it did not start Godot, and is not test evidence.

The locked diagnostic completed with exit 0: **1 script, 1 test, 52 assertions, 1 passing, 2.167 seconds**. Only the runner-allowlisted `gut_loader.gd:35` startup error appeared; no test parse/runtime error. This is a diagnostic, not a replacement for final runner/CI gates. Import also completed before it.

Real rounds (day: attack/defence, odds, draw, eff, tier):
- 20: 44/66, 400, 803, 490, stalemate.
- 21: 42/62, 403, 521, 409, stalemate.
- 22: 38/57, 400, 268, 331, attacker_checked.
- 23: 36/56, 391, 621, 427, stalemate.
- 24: 32/51, 385, 247, 310, attacker_checked.
- 25: 29/50, 367, 77, 241, attacker_checked.
- 26: 27/50, 350, 626, 387, attacker_checked.
- 27: 24/49, 328, 967, 468, stalemate; actual morale collapse starts withdrawal. All original assertions then pass, including host RETREAT, zero progress and one lifted notice. Empty round `left` here means physical separation has not yet occurred; the test correctly observes `disengaging`, not disappearance.

SHA256: temporary probe `e4cd76ea8e22f393e2abec190ceef7ee76835cd64b2ab172152283f7d3dc24c8`; diagnostic log `c9769e95884627c7f5c9c04f11bb96b4e4f4abcac77c136a672bf0124cb32e73`.

## Scope registration request

Cumulative scope needed:
1. `docs/reviews/cluster-formations/siege-relief-baseline.md` (already owned): evidence/checkpoint.
2. `tests/engine/test_siege.gd` (registered addition): retain every original assertion/setup/expected value and add bounded subsequent normal battle-day observation before the existing withdrawal assertions. The battle helper already owns the isolated combat path; do not invoke unrelated host thinking/siege/supply before actual battle withdrawal. Accumulate actual battle events for the existing siege settlement. Use the existing calendar limit/date arithmetic to bound observation, not a tuned combat threshold; no day-27 expected value.

No product, fixture, data, guide or category change is necessary on this evidence. Current battle/group guides already describe continued daily combat, first-contact deployment and morale collapse. This addition is disjoint from the two active PR scopes supplied at dispatch. The observed defect is the old test assuming guaranteed rout from the first roll despite current strength/contact rules; its relief acceptance can be retained by waiting for the actual battle result.

The final 11-line test patch observes up to one calendar month of further isolated battle days, stopping on actual disengaging. It advances the calendar with existing arithmetic, accumulates events with `append_array`, and then runs all original assertions against the full event stream. One new assertion rejects actual battle error events. It does not change actions, morale, food, personnel, RNG, host thinking or siege settlement; attack costs remain the real battle helper's responsibility. Like the original isolated helper, it does not run the full daily economy/supply loop. No guarantee is encoded for day 27.

Static verification: all **302 complete original assertion statements** in the file are byte-identical, in the same order. Ordered original assertion SHA256 `9d3429dc860753152c8587bfb02a658fbb3588f87cadc86b08015279d3a03e1d`. The entire source prefix through the original first-field-battle assertion is unchanged, preserving setup/fixture and first-contact checks. `git diff --check` passes.

After dispatcher permits Godot: run filtered original RED / final GREEN through the project runner gates, add only necessary replay/save determinism verification for this observer, then run the siege suite and required frozen-input affected/gameplay checks. Dispatcher requested no new heavy Godot run until CF04aR's queued nine-suite run finishes; honor that scheduling constraint.

## Final local verification

All Godot runs used the shared lock, `CC_FORCE_OFFLINE=1`, timeout wrapper and existing pre/post hooks. No engine/data/fixture input changed after these checks. Frozen manifest `/tmp/cf-p2-frozen-inputs.sha256` covers 517 engine/data/test/fixture/runner files; manifest SHA256 `675c352ba0b8c1883b90077c17b3a1dd4884852393a5c1e1eaf46b8e7153a769`.

- `./run_tests.sh --test tests/engine/test_siege.gd`: **exit 0**, 1 selected/ran script, **41/41 tests, 712 assertions, 90.213s**. Includes `test_siege_is_deterministic` (actual JSON mid-siege file save/replay) and `test_siege_draws_no_random_number`. Final test file SHA256 `2c6a4b56bb8ab9ddc6fc57db0ae12b036baf6af038596743979711dfa44d784a`; log `/tmp/cf-p2-siege-final.log`, SHA256 `62fc278feebaf3cc6beab15b002a6434ad47afde8033fe94011d778676cb7173`.
- Filtered original RED: copy of `git show 9e4bbecd:tests/engine/test_siege.gd` in `/tmp/test_cf_p2_siege_red.gd` (SHA256 `1de54c808960609cc8d80e3155889e31f6d666892b87c13c0a550c52d4341d8d`), direct GUT `-gtest=/tmp/test_cf_p2_siege_red.gd -gunit_test_name=test_relief_force_joins_battle_and_can_lift_siege`: **exit 1**, 1 test, 52 assertions, same four expected failures, 1.646s. Log `/tmp/cf-p2-formal-red.log`, SHA256 `763947c9865e163a283dbfd983858e5b4e4614a4d1b1648464f63e3447e25767`.
- Final-loop actual JSON save/replay diagnostic: `/tmp/test_cf_p2_siege_replay.gd` (SHA256 `f81872c6f2d3b578a889123d93dad6493acba8cf9bf333bd52ac5d85722d1bde`) saves immediately after first contact via `SaveLoad.save_game`, reloads it, advances both through the exact final observer loop, and asserts identical `SaveLoad.state_hash` and accumulated engine events/costs. Direct filtered GUT: **exit 0**, 1 test, **76 assertions**, 2.621s. Log `/tmp/cf-p2-replay.log`, SHA256 `a1c407c5eebb34b1ecd0c4c900bfd27dfb80726229c03f73cdadb5c3a2f1c2cb`. No test runtime/parse error; only runner-allowlisted GUT loader startup error.
- `./run_tests.sh --base 9e4bbecd83c25c595b8f43229305c7cd9360db2c`: **exit 0, no GUT scripts selected** (changed suite is explicitly opt-in gameplay). No functional check is represented as run by this command.
- Selector with `--request-text 'GUT_INCLUDE: gameplay'`: one gameplay batch containing army clearance, invasion end-to-end, raid, siege and sighting invasion. PR must retain this explicit request; CI/current HEAD remains pending.
- `git diff --check`: exit 0. Original complete-assertion byte/order proof: 302/302 retained; setup source prefix unchanged.

The direct diagnostic commands use `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd`, `-gpre_run_script=res://tests/pre_run.gd -gpost_run_script=res://tests/post_run.gd -gexit`, `tools/run_with_timeout.py 120`, and the stated test/name options. They do not replace the complete final runner gate above.

## PR / fixed-pair handoff

PR: https://github.com/samuelzhang1201/game_design/pull/196. Tested implementation commit: `e3cb2c7fdf4e072361d3d5d82fc7408ee6892c53`; subsequent report-only ownership update changes no frozen runtime/test input. Branch/worktree above are clean after commit. Unique Review is recorded above; implementation owns all possible review fixes, Review only audits/re-audits/merges. Dispatcher is not a third reviewer. No successor is assigned or authorized here.

Review acceptance: inspect actual test diff and preserve 302 original complete assertion statements/order and unchanged setup/data; verify observer does not drop events, bypass actual combat costs, issue an attack or force rout. Retain isolated-helper semantics. Reuse unchanged-input local evidence; require current-HEAD CI harness-checks, gameplay and aggregate all successful before merge. Any failure is returned to the original implementation session. No visual change or formula change is involved.

## Stop / next

Scope is registered and final local checks above are complete. No running process or queue remains from this step. PR #196 and its unique Review exist. Implementation hands this PR to that Review and waits; it resumes only for review findings or required main/conflict synchronization. Review checks all current-HEAD CI before merge; skipped/absent/failed checks are not acceptance. Separate P1 PR #195 was open when inspected; do not modify or review it. Any baseline gameplay failure from that step must await its accepted merge rather than duplicate its implementation. After merge both owners finish; no successor dispatch.
