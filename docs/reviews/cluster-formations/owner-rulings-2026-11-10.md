# Owner rulings for cluster-formation locomotion and activation (2026-11-10)

Step `CF-R0-RULINGS`. These rulings answer the pending authority decisions in the locomotion
contracts and set the route to switching cluster formations on in ordinary play. Where an
earlier contract in this folder says otherwise, this document wins. The execution order is
`docs/superpowers/plans/2026-11-10-cluster-activation.md`.

## Goal

Cluster formations are switched on in ordinary campaign play. Merging candidate code that
stays default-off is a step on the way, not the goal.

## R-A Contact bounds (accepted)

One world value per quantity, measured on the ordinary rendered piece: ordinary scale, the
protected placement and seat transform, the rendered Terrain3D ground under the figure, all
equipped meshes and native skinning.

| # | Quantity | Bound (world m) |
|---|---|---|
| 1 | Penetration: depth of any vertex of the whole mesh below the rendered ground, in every mode | ≤ 0.60 |
| 2 | Stance hover: height of the planted material sole or hoof patch above the seated plane (ground plus the protected `map3d_unit_seat_clear` lift), stance intervals only | ≤ 0.60 |
| 3 | Tangential slide: ground-projected displacement of the planted patch from its touchdown anchor over one stance interval | ≤ 0.60 per stance |
| 4 | Seam jump: one-frame displacement of any vertex at any clip boundary (MARCH↔PIVOT, loop seam, start/stop, mid-stance cut) | ≤ 0.05 |

A world bound becomes model micrometres per arm as `ceil(bound_world_m / k * 1e6)`, where `k`
is world metres per model metre for that arm's installed piece.

| Arm | `contact_um` (bounds 1–3) | seam bound (model µm) |
|---|---:|---:|
| infantry | 22769 | 1898 |
| artillery (infantry substitute) | 22769 | 1898 |
| archers | 28474 | 2373 |
| cavalry | 29273 | 2440 |
| royal | 29338 | 2445 |

The real-window review still judges the closest zoom, where 0.60 m is about 12 px: a clip must
look no worse there than the native MARCH clips already shipped.

## Pending decision 1, contact and stance interpretation (answered)

The stance target is a fixed material patch, chosen once in the bind mesh and anchored at
touchdown. Hover is measured from the seated plane, because the seat lift is protected
placement. Penetration is measured from the rendered ground. The strict zero-separation clause
(D) is dropped; clauses A, B and C stand, and contact is certified against the bounds in R-A.

## R-B Pending decision 2, the skin diagnostic (relaxed)

The thresholds stay exactly `length > 4 × native-entry AND > 0.03 m`. A flag fails the step
unless the shipped native pose at the same phase is itself flagged. Introduced flags still fail:
the 45 introduced infantry pairs and the one mapper-only crossing must be removed by the
infantry mapper. Inherited native flags are recorded and judged in the real-window review.

## R-C Certification method (changed)

A locomotion certificate is dense Godot-native sampling of every clip, transition and turn grid
(±1 microdegree, the 180° tie and the 359° wrap included), with a sampling margin derived from
the measured vertex velocity, plus the real-window review. Continuous-domain analytic proofs
are no longer required.

## R-D Placement Gram predicate (relaxed)

The relative Gram residual limit is 1e-6, not 1e-10. A float32 transform cannot meet 1e-10;
infantry measures 1.05e-7.

## R-E Ownership

A Claude Code session carries this feature from now on. The Codex fixed implementation and
Review pairs, the dispatcher and registry bindings named in earlier contracts no longer govern
it. Each step still lands as one PR with an independent review and every required check green.

- #201 (CF04c render) is continued as the v2 stop–pivot–move consumer in a new PR; #201 closes when it merges.
- #221 (infantry pivot clips) is continued in a new PR with the infantry mapper; #221 closes when it merges.
- #231 (archer certification failure) and #236 (archer transition conditions) are evidence only.
  Under R-A the seam that failed #231 (0.841 mm, 0.0177 world m) passes; #236's transition rework is
  needed only if the sampled archer certificate fails. Both close without merging.

## R-F Parallel work (allowed)

CF09–CF13 may start as candidate work beside CF06, and CF07b beside CF09, where their files are
disjoint. Each parallel step builds on merged interfaces only.

## R-G Balance targets (pending)

The CF24 targets for a stable, recognizable formation advantage are set before its validation
seeds run.

## Unchanged

The envelope and radius gate: if a sampled envelope crosses an arm's radius, the radius in the
footprint data grows (the CF01 rule); the bound does not loosen. All twelve design §9 gates, the
protected source clips, rest, binds, weights, root, seat, scale and time remain.
