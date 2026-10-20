# P4 ranged contact merge

Step `p4-ranged-contact-merge`; approved unit-behavior spec §11. Implementation
`01a15a2e-ed23-70c3-98f9-41f67c6f15ed`; independent Review `01a15a37-036d-7fb1-82b9-84b89632ab55`.
Prerequisites: ranged geometry PR154 and pursuit bounds PR151, accepted on main.

## Result

An attacking ranged-equipped unit's positive lawful cross-field firing count
now joins compatible battles through the existing merge path. The probe retains
source commands, tasks, reserves, pursuit bounds, facing and local sight; both
fields contribute friendly obstruction and party-scoped protection. The merge
rejects a union that changes any cross-field pair's realm hostility. No positions,
personnel, supplies, fees, RNG or journal entries are changed by the probe.
The existing survivor, aliases, record migration and atomic round receipts apply.

No cadence, machinery deployment, flank movement, deployment geometry or visual
change is included. Scope additions for `BattleRanged` and its guide were approved
and registered by the sole dispatcher before editing.

## Hand-derived checks

Each fixture unit has 40 fit personnel and one group. The shooter stands at
(1000,1000), facing its original enemy 4000 m east; a different field's enemy
stands 300 m east. With contact 100 m and ranged reach 400 m, the segment satisfies
100² < 300² <= 400² and the eastward cone. It yields exactly 40 firing, 0 melee,
40 fit; the original distant opponent yields zero firing. A friendly centre at
(1150,1020) is tangent to the 20 m blocking disc and blocks. A 401 m target fails.
Received designated targets, retreat, reserve, capture, source ceasefire, protected
withdrawal, target-source restrained pursuit and incompatible realm relations all prevent the ranged trigger.

## Verification

- RED before production edits: the real `BattleSystem.prepare_day` case stayed
  at two battles, with no alias/merge event; JSON/receipt fixture likewise failed
  to merge. New controls passed (8 tests, 2 failed). Log:
  `/tmp/p4-ranged-contact-red.log`.
- GREEN: new cross-field checks plus existing merge and ranged geometry tests:
  3 scripts, 45 tests, 204 assertions passed. Log:
  `/tmp/p4-ranged-contact-final-targeted.log`.
- A second RED check reproduced target-source restrained terms wrongly permitting
  pursuit fire (14 tests: 13 passed, that protection case failed). Log:
  `/tmp/p4-ranged-contact-terms-red.log`.
- Final frozen connected regression covers 15 scripts: merge/warrants, unified
  command, rules, atomic/save, task combat/retreat, group/formation, pursuit bounds
  and continuity, plus both ranged suites: **15 scripts, 172 tests, 1243 assertions
  passed**, exit 0. Log: `/tmp/p4-ranged-contact-frozen.log`. Runner selected-count,
  parse/runtime and expected-error gates passed without changed thresholds.
- An earlier full military-category run was deliberately stopped after discovering
  the additional restrained-term boundary; it is not claimed as passing evidence.
  A test fixture type-inference parse error was corrected before the second RED.
- `git diff --check` and both edited topic guide size checks passed.

The real daily-entry test checks unchanged unit positions and the stable survivor.
JSON-before-merge with reversed battle storage order produces the same merged
record and aliases; a later merge pass is inert. A pre-existing daily receipt
prevents fresh personnel/supply/round settlement through the absorbed alias.
The real post-merge round test verifies casualties occur and a second alias call
has no further state effects; task records, treasury and supplies survive the
merge itself. Existing merge regressions cover source records, terms, commanders,
warrants, town priority and pending-round exclusion in the military category.

CI and independent review remain required on the final PR HEAD before merging.

## Independent review

Reviewed the actual diff and connected daily preparation, ranged geometry,
per-unit action resolution, source-scoped agreements, allegiance mapping and
existing merge/alias/round migration. Found and fixed one in-scope issue:
a protected target that was routed (or had a received unit retreat task)
could be treated as stationary when its side order still said hold. The
cross-field probe now reads the target's actual unit action; default same-field
calls retain their previous semantics. No unowned files were changed.

The regression first failed with an unexpected merge: 15 tests, 14 passed,
1 failed (`/tmp/p4-review-retreat-red.log`). After the fix the same 15-script
connected regression command from the implementation checkpoint passed:
**173 tests, 1245 assertions, exit 0**, including actual daily entry,
hand-derived firing geometry, source protection, JSON/reversed order and
once-only settlement (`/tmp/p4-review-frozen.log`). Relevant inputs are frozen
in the local `REVIEW_FROZEN_INPUTS.json`; earlier evidence remains preserved.
`git diff --check` passed. No visual changes or visual acceptance are involved.

Final-HEAD required CI and merge result are recorded in the local checkpoint.
