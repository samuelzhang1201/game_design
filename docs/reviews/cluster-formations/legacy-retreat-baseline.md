# CF-P1 legacy retreat baseline diagnosis

Implementation: `01a19303-bc2a-7901-bf6f-9a2f9968573b`; dispatcher: `01a17398-42c1-7583-8d3f-7b15e877586c`. Review unassigned. Branch `codex/cluster-legacy-retreat`, clean runtime inputs at base `9e4bbecd83c25c595b8f43229305c7cd9360db2c`. Initial owned scope was this report only; dispatcher registered cumulative product/test/guide scope before edits. No acceptance waiver.

## Frozen baseline

Command: `/Users/samuelzhang/game_design-wt/godot_lock.sh ./run_tests.sh --test tests/engine/test_invasion_end_to_end.gd --test tests/engine/test_siege.gd`.

Godot 4.7.2, offline runner, shared lock. Exit 1: 2 scripts, 46 tests, 44 passing, 2 failing, 967 assertions, 368.459 seconds. Strong invasion fails unchanged assertions at lines 381 and 388; relief-force siege fails four assertions. Strong and weak invasion save/determinism checks pass. This is failed acceptance, not a passing suite.

## Withdrawal observations

A temporary copy of the unchanged invasion test logs actual saved positions, battle membership, actions and day events on days 29–33. Its first version had a diagnostic-only parse error (a broad insertion reached a second loop); the corrected second version executes the selected strong test and reproduces both failures. No product file was edited.

On strong day 31, battle 2 still contains two main-host units. On day 32, its remaining main-host archers are 4,856 metres from a defender: within the configured 5,000-metre contact range. Both battle sides have received retreat actions. No new `start` or engaged `round` is appropriate. The unchanged `_run.main_fought` observer counts only those two event kinds, so its zero does not demonstrate immunity or missing physical contact.

`BattleSystem._fight` also has a separate observable defect: `_exits` can remove one actually separated member while others remain; the no-engagement return discards the resulting `left` array. Battle 2's main-host horse disappears between day 31 and 32 without a departure event. This loses a truthful withdrawal receipt even though membership changes correctly. Callers and public report handling must be included in any repair; no artificial combat round should be introduced.

## Relief-force siege observation

A temporary copy of the unchanged relief test records one real field round: attacker power 44, defender power 66, odds 400, eff 490, tier `stalemate`, empty `left`. The garrison does not sortie. The expected one-round rout is not produced by the actual current combat inputs. This is distinct from the non-engagement receipt omission; altering combat strength, fixtures, thresholds or expected outcomes to force a rout is outside this diagnosis.

## Scope gate / next step

Dispatcher registered the bounded receipt repair and its existing public consumer. `BattleSystem._fight` now emits `withdrawal` only for actual partial exits on a non-engaging day. `MissiveWriter.battle_report` uses the existing authored `battle_left_*` wording. Final departure still emits only `end`. No old assertion, fixture, data, law, cost, formation, combat formula or CF04aR-owned path changes; the old invasion observer receives the explicitly registered correction below. The new independent test is selected by the existing `test_battle_*` military glob; no category manifest change.

RED: `/tmp/legacy-retreat-receipts-red3.log`, 3 tests / 1 failing, exactly the absent departure event. Earlier red attempts had a test type-inference error and an encoded-save comparison mismatch; neither is claimed as the behavioral RED. GREEN: `/tmp/legacy-retreat-targeted-green.log`, 4 scripts / 45 passing / 589 assertions / 28.082 seconds (new receipts, task retreat, lifecycle, battle report). Final added before-settlement JSON replay: `/tmp/legacy-retreat-save-green.log`, 3 passing / 31 assertions / 4.005 seconds. It verifies identical receipt/state after saving before settlement, persisted journal/public fact, zero new rounds/RNG/extra supply, no same-day or JSON-retry duplication, no exit while touching, and final end receipt only.

Hook tests 51/51, selector tests 23/23, runner tests 5/5 and deadline tests 5/5 passed serially; shell syntax, config parsing, guide caps and whitespace checks passed. Final affected run (functional categories plus explicitly requested gameplay) uses frozen 1,914-file runtime input SHA256 `f93d95e6907542a496525d965db59b358204236d8e54e43d5746cb8b72cadf78`, file list/hashes `/tmp/legacy-retreat-final-input.json`, selector `/tmp/legacy-retreat-selection.json`, log `/tmp/legacy-retreat-affected.log`. It was intentionally interrupted at dispatcher request before contract convergence; exit 1 after SIGTERM to this run’s own Godot child only. Reason and exact PID are preserved in `/tmp/legacy-retreat-affected-interruption.txt`. No broad PASS claimed; do not repeat it until remaining acceptance converges.

## Remaining acceptance and smallest reviewable next proposal

The original strong invasion observer's `main_fought` is a count of `start`/`round`, while its assertion text requires continued physical exposure. Existing battle 2 remains in physical contact through retreat without either event kind, under the explicit rule that retreat/hold does not attack or spend RNG. This patch does not change that observer or manufacture an attack. The new `withdrawal` receipt is sufficient to observe actual separation, not proof of a fought round.

The smallest proposed observation correction is in `tests/engine/test_invasion_end_to_end.gd` only: after each real day, read remaining actual `s.battles` membership, and add that day to the existing `main_fought` observer when a main-host member is still within inclusive contact distance of its opposing side (`not BattleSystem._separated`). Deduplicate against existing start/round observations. This preserves every old assertion expression and expected value verbatim; the assertion asks for physical exposure, not another attack. Keep combat rounds, casualties and RNG strictly on actual round events. The historical observer name needs a comment explaining continuing contact. Dispatcher registered that additional test path before implementation. The original 84 assertion statements, including continuation lines, remain byte-identical to base (`/tmp/legacy-retreat-assertion-proof.txt`). The observer additionally requires fit actual main-host and opposing members. Boundary regression covers exact contact range, one metre beyond, another host and an empty opposing side. The temporary original strong test passed 1/1 with 39 assertions in 56.94 seconds (`/tmp/legacy-strong-observer-probe.log`); the formal entire unchanged-assertion invasion suite plus receipt/observer regressions passed with runner exit 0: 2 scripts, 9/9 tests, 315 assertions, 282.147 seconds (`/tmp/legacy-retreat-observer-final.log`). Final frozen inputs `/tmp/legacy-retreat-observer-input.json` (1,914 files), SHA256 `8d26eb3631d18861ad37e3c82b3d9530bd76b29d32fddb96533dab642df71201`, rechecked unchanged. Weak hash remains `f1c695261ac6`; strong is now `edb4fbae037b` versus baseline `604d313f2d79`, because the saved journal gains real departure records. The original strong deterministic/save tests prove equal final state across its three replay paths; no claim of a baseline-identical full state. Siege/home dates and garrison casualties are unchanged. If the intended requirement instead demands a new attack after homeward intent, it conflicts with the received retreat/hold rules and needs a product decision rather than a receipt patch.

The relief siege's single-round `stalemate` has no missing withdrawal to report. Its independently registered follow-up must first trace why the intended overwhelming relief has actual power 66 versus 44 (including fit crews, live groups, laws and actions), identify a concrete shared calculation defect if one exists, and retain the current assertion and data. This step neither prescribes a numerical adjustment nor authorizes forcing a rout. It remains on the P4/current-CI blocker list.

The original strong scenario now passes on the formal final observer. The distinct siege scenario remains failed and is assigned to the dispatcher for a separate bounded step; its failure is not waived. Both remain required in applicable current-HEAD CI. Review must compare this PR against the original registered acceptance and cannot merge on receipt-only green checks or silently narrow acceptance. No review, PR or successor has been created yet.

## Evidence hashes

- `/tmp/legacy-retreat-baseline.log`: SHA256 `708dfefe8bd9600bc615c14a8fb2f13c1661900b89ff09ab78b2340e91ed3972`
- `/tmp/legacy-retreat-probe.log`: SHA256 `e8270fba4a75084c9f2190ec70b25f57fb648d78ea6f27838629e920f3906d58`
- `/tmp/legacy-retreat-probe2.log`: SHA256 `dd2251ddd89c51e895be20c882815c7e30898f95166d83e9749ed18b34db8a26`
- `/tmp/legacy-siege-probe.log`: SHA256 `56b62cea1c983bfe426b40674e86b5d5719a028e9431ee039b9c45032a1205f9`
