# P2.1 acceptance — working, not accepted

Personnel is recorded once in exclusive cohorts; equipment counts retain crew conversion. Death debits the recorded source population, recovery/capture/release preserve conservation, named commanders occupy a person and cannot command two units. Saved source parts and stable split aliases preserve typed orders, pending supplies and resumable day transactions.

The independent Sol review first found non-atomic battle casualties, a commander delivery bypass and swallowed initialization errors. Each has a regression and a fix. Final bounded review found no new actionable issue in the fixes, migration remainders, version 7 serialization, personnel power and siege acceptance.

## Siege acceptance

Production siege_rate remains 100. The same-seed 11 comparison keeps equipment and defender count fixed: legacy crew interpretation yields 8,341 people/19 units/558 supply, current crew interpretation 10,270 people/22 units/687 supply. Both begin on day 17; the control falls on day 24, current on day 27. Changed unit identities also affect deterministic combat rolls, so the evidence supports the combined crew/personnel/split/supply/combat path, not a claim that more personnel alone make sieges slower. See siege-causality.json.

The weak case still requires daily formula correctness, victory before retreat, population debit matching, personnel conservation, nonnegative supply, one conquest and the fall letter. Strong-wall survival acceptance remains unchanged. No balance-rate experiment is shipped.

## Verification

- Final targeted: 12 scripts, 119 tests, 1,899 assertions, exit 0 (.superpowers/p21/targeted-final.log).
- Weak siege acceptance: 1 test, 149 assertions passed (.superpowers/p21/siege-acceptance.log).
- UI/map/room affected run: 623 tests, five stale fixture failures corrected; all three failing UI files then passed in the final targeted run. Unchanged passing inputs are reused.
- Startup eligibility predicate ordering: same saved state hash, 1,537,694 to 564,535 microseconds on the recorded local probe; see startup-equivalence.json. This is a single local observation, not a general performance guarantee.
- First frozen fast:211scripts2202tests2188passing13failing1pending840482asserts1873.824s exit1. Raw log .superpowers/p21/fast-first.log. Six engine fixtures had obsolete wording/personnel/cost/scenario assumptions; five LEDGER gesture cases exposed halo priority, one law guard exposed illegal migration-layer access, one template case expected old wording. All causes received bounded corrections rather than disabling assertions.
- Ambient siege trace:150days each seeds11/42/7 chose undefended targets and entered RAID; zero siege-host-days and zero personnel conflicts. Controlled geometry now tests three-day arrival, clearance, stable camp and a spreading-disabled negative control:1test17asserts passed.
- Law guard/migration rerun:18tests982asserts passed. The law layer deep-copies inherited unit decree histories. Independent final Sol review found no actionable issue in these deltas.
- LEDGER diagnostic: original projected you ray hit you drawn sphere at186.0897; Merek drawn sphere missed, but its invisible halo hit at172.9115 and stole selection. Drawn-disc priority now precedes minimum-pixel fallback and links. Existing five gesture regressions and new analytic hand test pass; no special character priority or graph thinning. Hand values9,4.5,and5−sqrt5 cover visible priority, genuine occlusion and halo-only reach.
- Real-window realm card exposed an additional reader gap:16k raw equipment versus24k live personnel. An initial final-fast rerun was stopped after50seconds (not accepted). Shared ArmySystem.personnel_by_arm now provides both card and full host counts, with direct cohorts, legacy fallback and stable mixed-arm attribution. The card preserves equipment-equivalent chart strength with personnel×power/crew. Hand fixture153=31infantry+30cavalry+80fleet+12artillery also covers foreign roster-only units and read purity; GUI casualty test700crew→689 passes. Targeted3scripts23tests409asserts exit0; shutdown resource/RID diagnostics remain. Independent bounded Sol review found no correctness finding.
- Repair targeted batch:9scripts126tests124pass1pending1lawguardfailure (replacement initially missed indentation). That missed caller was corrected and the law/migration rerun above passed. Final frozen --fast is recorded below; PR CI is pending. Local full suite intentionally delegated to CI.

## Unresolved acceptance

Legacy pooled royal trains may have no original source_parts. The implementation fails closed and preserves the save/force rather than inventing an origin. A human ruling on an explicitly documented saved-garrison estimate is pending. This limitation prevents claiming complete P2.1 migration acceptance.

Known local startup gdai descriptor messages, GUT loader Nil-to-bool diagnostic and shutdown/orphan warnings remain; no leak-free claim.

## Strict-run fixture correction

The next complete fast run had211scripts2204tests2203passing1existingpending840553asserts1772.558s, but correctly exited1: the newly added hand fixture serialized a GameState with an uninitialized RNG twice. GUT assertion totals alone did not detect these SCRIPT ERRORs. Its fixture now seeds Rng(7); no production change. Strict targeted1script10tests44asserts exit0 has no unexpected SCRIPT ERROR or ignored script. The final corrected full fast passed exit0:211 scripts,2204 tests,2203 passing,1 existing LEDGER density pending,840553 assertions,1766.621s. No ignored scripts or unexpected SCRIPT ERROR. See fast-final.log and verification.json. The earlier23-test count is assertion evidence only, not a clean runtime gate.

## Current delivery state

Frozen source hashes match all107 source/test/config inputs in the staged tree. Final strict fast passed as recorded above. Independent code and real-window numeric/click review completed. PR/CI pending; legacy train provenance policy remains unresolved, so this is not full P2.1 acceptance.
