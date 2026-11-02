# Isolated body placement candidates

`ArmyGround.plan_body_placement_candidate`, `commit_body_placement_candidate`
and `body_placement_candidate` implement the closed opt-in transaction in
`docs/reviews/cluster-formations/cf04b-placement-contract.md`. Ordinary ground,
split, spawn and march callers retain their existing route.

A request explicitly names initialization, compatible missing legacy poses,
already staged recruitment, camp/seat metadata, or an actual host code.
`ArmySplit.initialize_bodies_candidate` never splits personnel again;
`EnemyAi.spawn_body_candidate` resolves actual roster membership itself.
Personnel and paid costs remain the outer transaction's responsibility.

Only missing rows obtain a first pose. Measured homes rotate about the saved
anchor, then search the configured finite camp lattice in deterministic order.
Every proposed circle reserves against all existing and proposed bodies,
including foreign and battle-owned rows. The actual ArmySystem swept-terrain
predicate validates stationary circles against grid bounds, water and scarps.
Saved command anchors are retained; they are not additional physical bodies.
Survivors keep their points, paths, roles and identities. Growth allocates
monotonic slots and never reuses retired identities. Exhaustion defers the
entire transaction without changing source, RNG, people or money.

Camp/leave/seat/refill/reconcile change metadata at the real current position.
A seat or host assembly requiring travel defers with `requires_motion`; only
candidate motion/march can move existing bodies. Ordinary frozen transactions
defer unchanged. The exact completed candidate MARCH receipt permits only
metadata operations, preserving the complete frozen payload and costs. V1
completion retains its existing receipt protocol. Explicit v2 completion uses
the strict proof entrance below; neither protocol is silently promoted.

Closed plans bind the raw source, request, boundary, configuration and actual
terrain pixels. Commit independently recomputes all placements/effects before
publishing one detached validated candidate. At safe/v1 boundaries the saved control is
`military_migration.body_placement={version,sequence,operation_id,receipt}`.
Version and sequence are canonical decimal strings; operation IDs require
`placement:` with a nonempty suffix to survive imported-save deep decoding.
Only the latest exact original-plan retry is a no-op. Convenience retries return
`retry_requires_original_plan`; they never reconstruct a plan or pay twice.
Malformed, stale, unsupported or tampered inputs fail closed. Raw boundaries
and frozen protocols are checked before recruitment reconciliation can defer.
Personnel cohort references must be unique and owned by their roster's unit
before any placement count is computed.

This candidate API does not activate ordinary boot/load, personnel/cost,
courier/arrival, battle or rendering dispatch. The full twelve formation gates,
eight playable formations, legal old-save compatibility, real campaign
activation, real-window visual review and performance acceptance remain due.
CF01's finite pose calibration and artillery substitute remain limits.

## V2 completed-MARCH metadata proof

The closed boundary is `{version:2,kind:"march_complete",abs_day:String,receipt}`,
where the receipt is the original outer MARCH plan hash. The saved placement
control has string fields `{version:"2",sequence,operation_id,receipt,completion_json}`.
`completion_json` is the canonical JSON string of `{version:1,origin,plans}`:
one complete original save image and the linear list of closed placement plans.
Contract: `docs/reviews/cluster-formations/placement-v2-completion-contract.md`.

Before decoding or legacy consumers, admission compares all frozen probe inputs
with the admitted endpoint: rosters/personnel, the entire day, foes, battles,
calendar, military controls except placement, and regiments except `camp_town`.
The camp field must be a string and the prior placement control closed v1.
It checks raw numeric/schema validity before lossless private rehydrate,
then validates the origin through the original v2 MARCH predicate. Every prefix
recomputes the actual metadata rules and entire preceding-state placement basis;
its receipt is published only after computing that plan. The final whole-save
comparison includes the proof string itself. Declared effects never apply as a
patch. Nested origins, malformed/noncanonical strings, changed context, rehashed
illegal effects, changed endpoints and stale prefixes reject atomically.

Only settle/leave/take-seat/refill/reconcile are admitted. Rows, poses, identity,
slots, paths, personnel, anchors, supply, run-up, RNG and the complete frozen day
and inner motion control remain unchanged. Unit camp-law inheritance uses the
existing law rules without extra law effects or payment. A no-effect operation
still records one receipt. Latest original-plan retries return the exact detached
endpoint, including after either provenance branch's whole JSON restore.
Successors append one plan at the next sequence; overflow and reused IDs reject.
Proof storage grows with this completion's operations; no truncation is defined.

Each public v2 entrance fully admits its source. Private metadata staging reuses
that admission only within the same call on the unchanged source. Explicit
plan commits independently recompute and compare the whole caller plan;
convenience commits stage once. Both validate the unpublished candidate through
complete origin/prefix replay and whole-endpoint comparison. Replay calls the
shared completed-MARCH predicate only after canonical proof and raw frozen-origin
checks plus lossless rehydrate; it does not repeat that origin's public entrance.
Original full-result, cursor exhaustion and outer-receipt checks remain in that
predicate. Admission results are never cached across calls.

Original MARCH/BodyMotion and TickEngine consumers remain strict: this proof is
not their original endpoint, a day closure, a resume permission or a new-day
source. A future owning lifecycle must atomically consume it with actual closure;
manual proof/day deletion is not closure. This API activates no production path.
