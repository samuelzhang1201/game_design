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
