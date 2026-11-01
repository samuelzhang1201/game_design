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
metadata operations, preserving the complete frozen payload and costs.

Closed plans bind the raw source, request, boundary, configuration and actual
terrain pixels. Commit independently recomputes all placements/effects before
publishing one detached validated candidate. The saved control is only
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
