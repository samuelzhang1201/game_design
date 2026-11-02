# Isolated body march candidate

`TickEngine.begin_body_march_candidate` and `step_body_march_candidate`, and
`ArmySystem.plan_body_march_candidate` / `commit_body_march_candidate`, are
explicit opt-in transactions. Ordinary march, predictions and `resolve_day`
retain their existing route. The accepted interface and negative matrix are in
`docs/reviews/cluster-formations/cf04a-march-contract.md`.

Begin requires explicitly initialized complete current bodies, freezes the day's
received entries/budgets on a detached clone, and runs no other day phases.
The saved v4 transaction remains present at the idle tactical boundary with a
closed `body_march` control (`version`, day, next/count as canonical decimal
strings; preceding full-plan receipt). The ordinary day validator refuses it.
`UnitBodies.validate_march_candidate` validates that exact boundary through the
foundation's ownership/count/circle validators; it does not migrate or place.
The real `BodyMotion.plan/commit` accepts the explicit boundary and binds it in
its basis; empty-boundary callers retain frozen deferral.

Each slice stages actual gait/run payment once, reserves all bodies together,
and validates every returned segment's swept measured circle against the land
grid's closed cells, water and bounds. Unit distance is the maximum actual body
polyline cost, including side legs, never the sum of rows or endpoint chord.
The anchor advances only by the minimum ordered route prefix reached by all
extant bodies; a side leg earns progress when it rejoins. Exact body poses and
paths persist independently of anchor progress. No arrival snap or settlement
runs here. Supply, commands, remaining routes, pursuit credit and both receipts
publish together only after final validation. Same-plan retries are detached
no-ops; stale, forged or inconsistent controls reject without source/RNG changes.
A completed candidate day remains frozen; this API neither eats the base meal
nor advances the calendar. Candidate acceptance does not certify production
boot/load, placement, battle, rendering or the remaining P4 acceptance.

Pursuit limits clip the desired slice, while the full received route determines
remaining waypoints and actual arrival. The pursuit helper's boundary reason is
forwarded only when the shared anchor reaches that boundary; an earlier body
reservation cannot claim it. Adjacent duplicate waypoints contribute no leg or off-route progress.
After any committed slice, including a completed day, the inner receipt must
name today's preceding slice. Only the initial cursor may retain an older day's
priority. The frozen journal must already contain an arrivals array; malformed
journals fail before planning or payment and are never repaired in place.

## Isolated locomotion timeline (`BodyMotion`, candidate v2)

`plan_locomotion_candidate` constructs stop–pivot–move operations before any
reservation. Its closed v2 plan is `{version,cursor,policy_digest,moves,reasons}`;
cursor is `{abs_day,substep,basis,intents,priority,boundary}`. Every body, including
unrequested stationary peers, has a complete integer partition of the slice.
Time precision is `BodyMotion.LOCOMOTION_Q`, angles are integer microdegrees,
shortest 180-degree ties turn positively, and a final pivot restores row facing.
The first yaw and final facing both come from that same authoritative row.
Saved v2 controls must match the current endpoint rows at both plan and commit
admission, including successor cursors; rehashing claimed headings cannot skip
the initial pivot or replace the row's actual facing.
Only complete affordable waypoint prefixes execute; unused time is a hold.
Each move's budget and start match its recorded intent. Unrequested peers have
zero budget, and a row with no translation has exactly one full-slice hold.
Move cost is ceil-Euclidean metres and time is ceiling(cost × precision / budget).
Pivots consume that same time budget. They never create route or payment credit.

Heading is proved by refining integer fixed-point intervals: Machin's identity
bounds pi, a reduced alternating atan series bounds the angle, and both interval
ends must round to the same microdegree. Base-2^15 temporary limbs prevent int64
product overflow. No platform atan2, floating heading or generated table is saved.
Rows/operations reject numbers outside JSON's exact integer range. Local deltas
and products are checked before authoritative arithmetic.

The basis has two SHA256 digests: `source` binds the exact precommit save, canonical
intents, requested cursor and context; `result` binds the expected endpoint save and context with
the self-referential `body_motion` control omitted. Context binds footprints,
balance, certificates, terrain and diplomacy. This permits changed-state retry
rejection without saving a second state or motion authority. Commit replans and
compares the entire plan, then returns a detached candidate, leaving its source
unchanged. The sole saved v2 control has exactly
`{version:"2",abs_day:String,substep:String,receipt,priority,plan}`. Control integers
are canonical decimal strings; the embedded plan retains integral JSON numbers.
Its hash, cursor, priority and actual endpoint rows must agree. Identical retries
return a detached no-op, including after JSON load; changed controls/state reject.
`GameState.from_dict` canonicalizes only integral JSON numbers in the v2 control
in both provenance branches. Fractions and numeric-looking strings remain raw,
so legacy rounding/value decoding cannot launder them into a valid receipt.
Every v2 source admission, including successor cursors, rechecks the bound
policy, certified pivot durations and full terrain/relative sweep, independently
validating original start circles before using the sweep's t=0 exception.
V1 loading is unchanged; a frozen v1 boundary cannot acquire v2 timing.

Policy is unsupported unless both per-arm `body_locomotion_<arm>_turn_q` and
`body_locomotion_<arm>_contact_um` rows match an explicit footprint
`locomotion_certificate={digest,turn_q,contact_um,radius_m,clips,all_turns}`.
This candidate accepts a certificate supplied by its caller's repository; it
does not load, create or certify one. Test-injected certificates are fixtures,
never installed arm support. Actual certification/installation remains separate.
All timed operations, including stationary pivots and tails, share one continuous
sweep. Translated measured circles and stationary circles must fit the land grid.

`sample_locomotion_candidate({version:2,moves},time_q)` accepts a copied admitted
subset only, validates all rows before returning any, and interpolates transient
float X/Y/yaw with next-interval boundary selection. It reads no repository,
state, admission, orders or clock. It never mutates or saves presentation values.
V1 APIs, production callers, frozen march protocols, art and rendering stay
separate; this API does not activate v2 or resolve PR201's acceptance boundary.

## Explicit v2 march integration

`ArmySystem.plan_locomotion_march_candidate` / `commit_locomotion_march_candidate`
and `TickEngine.begin_locomotion_march_candidate` /
`step_locomotion_march_candidate` are separate opt-in consumers of the accepted
integer locomotion timeline. Ordinary callers and v1 entrances retain their
protocol. Begin never converts an existing frozen day, including an exhausted
candidate day; the owning caller must first reach a closed day boundary.
A prior day's valid v1 receipt survives v2 begin unchanged. No policy is installed
by this integration: every land arm requires the explicit matching repository
policy/certificate, or the detached transaction returns an unsupported error.

The v2 outer plan retains the closed march-plan fields with integer `version:2`;
its `motion` is the complete accepted BodyMotion v2 plan. The outer control retains
`version,abs_day,next_substep,substep_count,last`, with string `version:"2"`.
Its initial `last` is empty; thereafter it is exactly
`{substep:String,receipt:String,result:String}`. Receipt hashes the complete outer
plan. Result hashes the final whole state and march context with only this result
field omitted, binding rows, inner receipt, routes, payment, tasks and journal for
same-plan retry and successor admission after direct or whole-JSON restore.
An identical retry returns a detached no-op; changed state/context or receipt
rejects before payment or becoming a new slice basis. A v2 frozen day admits
no outside state mutation after its first committed slice. Inner
and outer protocols must match after every committed slice. The ordinary day
consumer refuses both candidate protocols and unknown/mixed controls fail closed.

V2 uses the existing daily integer remainder partition, gait/run payment and
simultaneous reservation path. The requested slice is clipped through BodyMotion's
integer prefix/timeline checks to an affordable route prefix, retaining the full
received route separately. V2 progress is checked against each body's actual
received rounded slice path, not exact collinearity with an uncut distant leg.
A bounded integer inverse proves that a rejoined point is an exact canonical
rounded prefix; no geometric tolerance grants progress to side legs. Remaining
waypoints follow their original order, including duplicate zero-length legs.
Pursuit clips only that geometry; it retains the
received slice capacity so turning cannot strand a body at its final metre.
Translation, all pivots and the final hold share one Q;
there is no final-slice catchup or carry of unused pivot/hold time. Running pays
its existing slice charge once, even for a blocked hold; failure publishes none
of the staged cost. Distance, pursuit and anchor progress count only actual
translation, never pivot time or stationary holds. All required stationary peers
participate, while zero personnel invents no body. Body paths, anchor, remaining
route, supply, pursuit, receipts and cursor publish on one detached candidate.

The completed transaction remains frozen without eating the base meal, advancing
the calendar or settling the unit. This integration changes no production
activation, placement, battle, renderer, installed art, save version or save file.
Test-injected policy/certificates provide numerical coverage only; full arm/contact,
real-window and final live-world acceptance remain separate.

## Shared battle movement transaction (`BodyBattleMotion`)

`collect_candidate`, `plan_candidate` and `commit_candidate` consume only an
explicit CF05 battle `move` boundary. The frozen `march_budgets` cover every land
unit, including stationary and battle-owned peers. Quotient/remainder shares and
existing `UnitGait` run payments are applied once per unit; tactical movement is
also capped by that slice's share of `battle_deploy_step_m`. It never adds march
and tactical budgets or charges per body. Selected writers are, in order,
withdrawal, pursuit march, flank, charge, deployment, nonbattle march and hold.
Packing, incapacity, pursuit limits and received law can hold the selected writer.
No second writer then executes. Base food remains with the normal supply phase.

The optional explicit provider dictionary supplies pure tactical Callables with
`(repo, source, battle_id, unit, budget_m)` and the CF05 closed contribution shape.
It is transient, not saved configuration. Missing selected tactical providers
error; there are no installed tactical providers or production callers here.
Tests supply explicit contributions. Providers receive a detached source and
state/RNG mutation rejects. The collector computes budgets and hostility, retains
all stationary peers, and rejects malformed routes before numerical operations.
`ArmySystem.march_intent_candidate` shares received route/pursuit extraction with
v2 MARCH; its settlement helper preserves the existing actual-prefix accounting.

All bodies use the same `BodyMotion` v2 timing/reservation core through explicit
battle entrances. Their desired affordable slices and returned measured-circle
paths must clear terrain, including closed edges/corners, water, scarps and map
bounds. Pivots and tails occupy their full continuous intervals. The shared
anchor receives the minimum ordered route prefix, and unit distance is the
maximum actual body path cost. No additional distance comes from pivot time.

The inner battle receipt binds full cost-staged source plus intents, boundary
and TIME context; its result binds only canonical authoritative bodies, owners
and slot counters. The outer move plan binds the full original source and shared
context. Commit independently replans, stages running costs, commits the inner
timeline, settles anchors/routes, and publishes contact stage and next sequence
with the full outer receipt and endpoint digest. `UnitBodies` admits active
battle motion only with the exact consumed move boundary, both proofs, reconstructed
start-world validation and complete timed terrain/collision checks. Ordinary
TIME/MARCH admission and hash projections remain separate.

Direct/JSON latest-plan retries validate the full endpoint and inner plan before
returning a detached no-op. Modified cost, RNG, queues, receipts, policy or terrain
rejects. Failures publish no staged cost, pose, route or RNG. The inner commit is
private staging and cannot replay an outer contact endpoint. This step leaves
that active timeline at contact; closure, later lifecycle/providers, day driver,
installed policy, rendering and production activation remain separate work.
