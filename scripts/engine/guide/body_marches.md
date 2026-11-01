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
Retries recheck certified pivot durations and the full sweep, independently
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
