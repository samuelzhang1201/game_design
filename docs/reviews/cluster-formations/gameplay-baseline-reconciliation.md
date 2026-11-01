# CF-P3 gameplay baseline reconciliation

## Ownership and acceptance

- Dispatcher: `01a17398-42c1-7583-8d3f-7b15e877586c`; implementation: `01a194a8-6e4d-7172-95ec-5995ffe8c1c0`; unique Review: `01a194bb-4007-7491-b0a4-818ceb7d9f18` (Sol/medium, created exactly once).
- Authorization: direct human approval “明确授权，按此方案继续”, 2026-11-01, `request_user_input_async call_ba2059e4e4fa46c28c005719d0dcf7af item0`; dispatcher Start confirmed after registry validation.
- Worktree: `/Users/samuelzhang/.codex/worktrees/cluster-gameplay-baseline/game_design`; branch `codex/cluster-gameplay-baseline`; base `9e4bbecd83c25c595b8f43229305c7cd9360db2c`.
- Scope: genuine quiet-day withdrawal receipts, their existing public letter consumer, and truthful invasion/relief observation under current battle rules. The eight registered paths are the two engine scripts, battle guide, new receipt test/UID, original invasion/siege tests, and this report.
- Preserve every original assertion statement/order, setup, fixture, expected value, data and CI gate. No battle algorithm, contact/retreat law, casualty/cost/RNG, save format or CF04 candidate change. No successor is authorized here.

## Preserved failures remain failures

Original CF-P1 and CF-P2 were human-authorized `superseded`, unmerged, and PRs #195/#196 closed. Their original owner pairs, full previous registry records, WIP, input manifests, failed CI and independent reviews remain preserved by those owners. They are not accepted dependencies and their local PASS evidence is not this step’s acceptance.

- P1 `05f31b0ede07603c4a23abe92a7ae13fa69d4055`: CI run `41227103139`, job `124613693489`, original siege failure.
- P2 `c46b989cb21e98fc1dc59dee28fed2e659fabb3f`: CI run `41228292138`, job `124617227298`, original invasion assertions at lines 381/388 failed; 92/93 tests, 2075 assertions, 1372.309s.
- Read-only references: preserved P1 `legacy-retreat-baseline.md` and P2 `siege-relief-baseline.md` in their original worktrees. Only specific independently inspected hunks are eligible for this new PR; no whole-commit cherry-pick.

## Root causes and verification plan

`BattleSystem._fight` calls `_exits` before resolving attack intent. When a separated member actually leaves but both sides hold, the continuing-battle early return discards `left`. The existing final departure remains an `end`; the missing case needs a receipt, not a round. `BattleReport.note` already journals ordinary battle events; `MissiveWriter.battle_report` must word this event using existing departure templates.

The invasion observer currently counts only `start`/`round`, although a withdrawing main-host member can remain in physical contact on later quiet days. Count live main-host membership against live opposing membership with the engine’s inclusive separation predicate; membership alone, another host, separated columns and empty opposition are insufficient.

The relief scenario’s first round is not guaranteed to rout the besieger. Preserved diagnostics show power 44/66, odds 400, draw 803, effective 490: `1000 * 44 / (44 + 66) = 400`; integer `(803 - 500) * 300 / 1000 = 90`; effective 490 is stalemate. Observe normal subsequent isolated battle days for at most `Calendar.DAYS_PER_TICK`, accumulate every real event and stop on actual disengaging before the original siege settlement. Do not encode diagnostic day 27, alter morale or force an outcome.

Verification: new independent baseline RED; receipt/observer boundaries; unchanged original assertion proof; final invasion/siege, retreat/lifecycle/report and save/replay; then one frozen-input complete five-script gameplay run and necessary affected checks. Every Godot process uses the project shared lock. Required current-HEAD CI and unique independent Review remain mandatory.

## Independent RED and convergence

New baseline run: shared lock + `./run_tests.sh --test tests/engine/test_battle_withdrawal_receipts.gd --test tests/engine/test_invasion_end_to_end.gd --test tests/engine/test_siege.gd`, log `/tmp/cf-p3-baseline-red.log`: exit **1**, 3 scripts, 49 tests, 46 passing/3 failing, 988 assertions, 371.29s. Product sources and original scenario files were still baseline; the new receipt suite then contained its three receipt tests. Failures independently reproduced missing quiet receipt, invasion continued-contact/real-departure observations, and premature relief withdrawal observation. Baseline strong replay hash was `604d313f2d79`.

Convergence failures are preserved, not PASS: `/tmp/cf-p3-targeted-green.log` rejected a missing `People` preload in the added live-personnel boundary test (6/7 scripts ran); `/tmp/cf-p3-targeted-final.log` then correctly rejected a reused personnel-fixture transition token (67/68 tests). The final test uses unique per-unit receipt IDs through the existing source-preserving fixture writer. No product change was made to hide either failure. Corrected receipt-only runner `/tmp/cf-p3-receipts-final.log`: exit 0, 1 script, 5/5 tests, 46 assertions, 4.357s.

Original complete assertion statements are byte-identical and retain order: invasion 84/84, siege 302/302 (one additional battle-error assertion). `/tmp/cf-p3-assert-proof.py` lexically extracts complete calls, including multiline calls, and checks ordered byte identity. Ordered statement SHA256 including source indentation/newlines: invasion `960f59c3dcddee5dc8d3c27983530c2604c46d74c24e040ca0df8e85f803b04a`; siege `3398e7592464e0655d266a014261bb753337e05a52c89f058613e241ae23174c`. Diff contains only insertions; all original setup, fixture, expected values and statement order remain intact.

The final relevant-input manifest `/tmp/cf-p3-final-inputs.sha256` covers 2416 tracked script/data/test/fixture/tool/GUT/runner/project/workflow files plus the new receipt test/UID. SHA256 `5d9f18ee53d5f6ead76be014b7d7d1bc43ca75e3176cd9e982fc750f22b9dbbd`. Report-only changes do not invalidate runtime checks. Input verification must precede reuse.

Harness checks: hook 51/51, selector 23/23, runner gates 5/5 and timeout 5/5, each unittest command reported OK. Selector command uses `--format json`; an initial unsupported `--format matrix` was rejected and corrected without configuration changes. The actual affected union is engine-core, engine-economy, engine-military (four CI batches), gameplay, ledger3d, map3d, UI and war-room (11 CI jobs). PR retains `GUT_INCLUDE: gameplay`; no category/gate edits.

## Final frozen-input acceptance

- Locked project runner: seven receipt/retreat/lifecycle/report/report-details/battle-save/save-load scripts, **exit 0; 68/68 tests, 748 assertions, 34.172s**, `/tmp/cf-p3-targeted-accepted.log`.
- Locked actual JSON relief diagnostic `/tmp/test_cf_p3_relief_replay.gd`, **exit 0; 1 test, 77 assertions, 2.626s**, `/tmp/cf-p3-relief-replay.log`. Saved immediately after first contact, reloaded through `SaveLoad`, replayed exactly the same bounded normal battle days, compared whole-state hashes and every accumulated event/cost. Direct GUT uses offline mode, timeout 120, existing pre/post hooks, exact filtered name. Parse/runtime/count gates independently checked; only allowlisted GUT loader startup error. It supplements the project runner, never replaces it.
- Locked `./run_tests.sh --category gameplay`: **exit 0; all five scripts, 93/93 tests, 2076 assertions, 532.154s**, `/tmp/cf-p3-gameplay-final.log`. Includes unchanged original invasion 5/5 and siege 41/41, their actual mid-run JSON save/replay tests, all clearance/raid/sighting scenarios, and unchanged round-only randomness test. No failure, skip, timeout or cancellation counted as PASS.
- Invasion weak remains fall day 22/home day 24/hash `f1c695261ac6`; strong remains siege day 16, best progress 710, lifted/home day 31, garrison dead 584 (reported 584). Strong final hash **changes** from `604d313f2d79` to `edb4fbae037b` because real quiet withdrawal events now enter saved logs/missives. Same-input repeats and actual mid-run saves agree on the new hash; this is not byte identity with the old incomplete journal.
- Frozen manifest verified unchanged after gameplay. The complete-assertion proof, all RED/convergence/final logs, diagnostic, selector JSON and input manifest are copied under `.superpowers/evidence/gameplay-baseline/`; local checkpoint names processes/next action. `git diff --check`, shell/config parsing and guide caps pass.

Product delta is nine engine lines, one battle-guide rule, sixteen invasion-observer lines, eleven relief-observer lines and the new focused receipt/observer regression suite. No visual asset/layout changes, new formula, schema/migration, CSV value, fixture or battle algorithm change.

## Review and stop contract

Unique Review above is read-only until formal PR/HEAD handoff; implementation owns every possible fix, CI failure and conflict resolution. Review independently audits the actual diff and unchanged-input evidence and merges only with all required **current-HEAD** CI jobs/aggregate and applicable acceptance green. Affected CI includes 11 GUT matrix jobs plus harness and aggregate; no check waiver. PR body must contain `GUT_INCLUDE: gameplay`. No local full functional rerun is claimed: targeted functional checks plus complete requested gameplay ran locally, and the whole selected functional union remains required in CI.

This baseline repair does not accept the CF04 candidate, complete P4 §9’s twelve acceptance items, or erase the old 55 failures/6 pending items. Those remain with the dispatcher and their original records. After actual accepted merge both owners stop; only the dispatcher may authorize/launch later work.
