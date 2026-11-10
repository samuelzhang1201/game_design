# Royal native contact feasibility and parameter-provider boundary

> **Superseded in part (2026-11-10):** the owner rulings in `owner-rulings-2026-11-10.md` win where this document differs (contact bounds, skin diagnostic, certification method, Gram predicate, ownership).

Step `LOCO-ROYAL-CONTACT-FEASIBILITY`, 2026-11-02. Implementation:
`01a19c47-d970-7621-8597-e6b2603fc752`; sole dispatcher:
`01a17398-42c1-7583-8d3f-7b15e877586c`. Unique Review is assigned by the
dispatcher before handoff and recorded in the PR/checkpoint. Base:
`43d75e7e7aa3838411b458f364174ff919b591b3`. Accepted dependencies:
CF04c-locomotion-contract, LOCO-TIME and LOCO-CLIP-ROYAL (#219, merge
`6eb5cf6d283523828e357c4210875aee02f8f6a8`). Scope is this document only.

**Decision:** use an endpoint-first, material-surface contact test, followed by
terrain-aware, coupled contact-trajectory synthesis with exact native endpoints.
The existing cavalry solver is a candidate reconstruction kernel, not the missing
royal author/provider. A fixed baked pivot is not the provider. No contact budget,
source correction, scene correction or production provider is installed here.

**Present result:** royal full-domain contact certification remains FAIL.
Neither feasibility nor impossibility of the original *unspecified finite-error*
contract has been proved. A physical endpoint witness gives a necessary lower
bound; it is not a justified tolerance. The executable decision procedure and
conditional implementation boundaries below are the deliverable. In particular,
there is no unconditional promise that a solver can repair protected endpoints.

## 1. Evidence, authority and the exact adverse facts

The [CF04c contract](cf04c-locomotion-contract.md) and accepted
[BodyMotion](../../../scripts/engine/body_motion.gd) remain authoritative for
integer time/heading, original finite contact error, ordinary scale, full radius,
native transitions and all P4 gates. LOCO-CERT-ROYAL is a **failure input**, not
an unmerged dependency. Its four files and failed acceptance remain with original
implementation `01a19bf2-0bbc-7281-88dc-34b3648cf95d`. This document does not
review, import or run that owner's unmerged certifier code.

Read-only evidence roots, kept distinct:

- `C = /Users/samuelzhang/.codex/worktrees/cluster-loco-cert-royal/game_design`:
  `.superpowers/cluster-loco-cert-royal/checkpoint.json` is the original proposal;
  `docs/reviews/cluster-formations/evidence/locomotion/royal/` contains the frozen
  failed reports. These are observations, not accepted product code.
- `A = /Users/samuelzhang/.codex/worktrees/cluster-loco-clip-royal/game_design/assets/3D/units/royal/model_wip/loco_clip`:
  accepted clip source/native evidence. Preserve the old originals, failed
  variants and process receipts. No wakeup of the completed clip pair is needed.

Pinned bytes used by this document:

| Root/path | SHA256 |
|---|---|
| C: evidence/locomotion/royal/source.json, under docs/reviews/cluster-formations | `e6071e563d2fd731fffd018f939e59a123d7c97fe62cc21ff9ff4305ca03375c` |
| C: same directory/pivot-contacts.json | `ca9090ce9dda8aef5f9e80a24f3c9d9337de5a1982423435c666669a68cc37e1` |
| C: same directory/pivot-envelope.json | `6967df7b030ee8e41147f6b64e1e939cabbfa486c69cf4304d19aaa390232ce7` |
| A: source-facts.json | `1cb04a433bf53ffbc740109b60d5b1b30b35f212cc1f399d4724d24e2c505af6` |
| A: native_probe/native-v2-results.json | `c4c2a50dd93f1237b10664e5e97032e3c49d9b0ee0ee7cf35aaee789e62e7379` |
| A: provider-input-native.json | `bbd622754be79ed18282467ffb84434940d07bf04640af8b28c395e558307d36` |
| A: native-ground-frame-confirmed-query.json | `dfe208af5e53a0b3e753a31a99a3e439c6feff37fa14a6f2a5e9ec96c5daa02e` |
| A: sole-frame-calibration.json | `9fac14923b15c253ce96c66d470b1090d6ccdbad957fb544d6fb66234810bd7a` |
| A: visual/sequence-lowland/manifest.json | `cb8b63d1f7a6b47c948a0d07bec369d49db36a6828531c68711c65bdeb271840` |
| A: visual/visual-evidence-R2.json | `1fa627839cd79fc88c0e7b9e07695fe0723c84e8db04505512cfc2cc7f8de89e` |

The accepted installed source chain is owner `knight_rig_anim.blend` → retained
20k source → authored pivot copy → `royal_install` → installed GLB → pair-only
native import → `scenes/models/units/royal.tscn`. Source hashes in source-facts:
original blend `98425f71356e5354b0e445428141fd34dcb08169bcc668affa417d07f79efb75`,
20k blend `7f506320d1df4a5a4ae82c456832691d78dfa07bc6fd359c22e43e914e321f8d`,
20k GLB `11014742c71c6ef85cbabdfb053ad2050815191b37551486c44cf73c37db74de`.
Installed GLB is `265cefc8aabb9860b7ad18b036d158fd255943b96127fdead127574ec349fe0f`;
import is `5c17fddf7820092f51bdafa47e9c80eb614f98f899316db040aaa89fabde4f7c`;
scene is `b9d7b89500a6778fa24aa0c53c2a016d229874e6a8fd2411284299c152a4c375`.
These are different from the pre-pivot GLB; equality is asserted only for the
protected old-five curves/geometry/binds, not for whole old/new GLB files.

Keep the following channels separate:

1. Frozen raw-GLB FK/LBS witness: MARCH phase .73, FrontHoof.R vertex 21308,
   model Y `-.05927695958939805`; existing flat-seat addition
   `.0360048115253448`; separation `-.023272148064053248 m`.
2. Actual imported native query: same phase/hoof minimum
   `-.0592770278453827 + .0360048115253448 = -.023272216320037897 m`.
   Native and raw interpolation are not generally identical (a retained
   forearm matrix discrepancy reaches about .199); the near agreement at this
   one phase does not authorize a raw sampler as native authority.
3. Actual rendered-frame lowland manifest: first figure at .73 has terrain
   heightmap separation `-.504600524902344` built-world units and reported
   source-equivalent separation `-.0248103348948813 m`. This includes the actual
   seated transform. It is a finite terrain witness, not a constant flat-plane
   offset or proof for every location. The rows labelled yaw0/90/180 have the
   same figure transforms and changing camera transforms: do **not** count them
   as three independently changed body-yaw/terrain cases.
4. Fixed PIVOT_LEFT/RIGHT endpoint versus MARCH .73: full-skin maximum difference
   `1.5245736529360432 m`, vertex 18953. This rejects **bake-only** arbitrary-phase
   playback. It says nothing about the endpoints of a prospective provider that
   actually returns the requested native pose.
5. Raw dense MARCH radius `748.8595829969472` simulation metres; conservative
   real-arithmetic upper `789.9554707346122`; unchanged R = 749. The upper fails
   to establish containment; it is **not an observed escape**. Fixed-pivot upper
   `631.9712956279132` bounds those baked curves only, not a future parameter map.

The clip's normal-window sequence batch has a collected exit 0. The supplementary
438-frame parameter native process has a lost/UNKNOWN exit receipt despite DONE
output and guards; UNKNOWN stays UNKNOWN. Accepted217's finite native caller
probes have their own actual exit-0 receipts. None is full-domain certification,
actual production-clock pause/1x/4x acceptance or representative FPS evidence.

## 2. Physical meaning and the endpoint obstruction

Use actual native geometry: all 23,774 vertices, four packed influences as stored,
59 named Skin inverse binds and actual full parent-relative local affines. Do not
normalize weights, substitute Blender matrix_basis, remove troublesome vertices,
fit ground through a hoof or choose a different lowest vertex as a planted anchor.
For a material point v, including fixed barycentric points on sole triangles:

`p_v(u) = XYZ(sum_k w_vk G_k(u) B_k^-1 [v,1])`

`x_v(u) = T_ground(u) Y_committed(u) p_v(u)`.

T contains the existing seat and ordinary scale, derived independently of the
animation. Y is the engine's yaw. A stationary pivot never translates its XZ.
Use the actual upright body-row transform for the eventual CF04c consumer;
retain legacy tilted-seat measurements as a separate placement domain. A legacy
14-degree envelope does not authorize tilting upright body rows. Heightmap
sampling and the rendered Terrain3D surface/LOD error are separate recorded
inputs; unknown surface discrepancy is not zero uncertainty.

A material sole patch is chosen once in the bind mesh, with named faces/vertex
IDs and anatomical provenance. The old dominant-weight/lowest-5-mm/PCA cohort
is a **diagnostic seed**, not already an authored stance declaration or tolerance.
During stance its anchors are fixed physical terrain points chosen at touchdown,
with fixed terrain normals. Toe roll explicitly changes the active material patch
at a declared boundary; it does not silently move an anchor. Swing need not have
zero hover or tangent slip, but penetration is checked for the entire mesh in
every mode, including both endpoints. Relabelling .73 as swing cannot remove
its below-ground point. Record stance/swing and source airborne intervals rather
than inventing support or exempting all four hooves for the whole pivot.

For a planar patch (unit normal n, fixed ground point g, anchor a):

`d_v = n dot (x_v-g)`; `s_v = norm((I-n n^T)(x_v-a))`.

Stance error is `max(abs(d_v), s_v)`; all-mode penetration is `max(0,-d_v)`.
Also record patch-normal mismatch and full affine/skin deformation. For actual
nonplanar terrain, evaluate the real terrain surface at the point and bound each
intersected cell/triangle; a root-height sample or fitted tangent plane alone
cannot certify a sole spanning multiple cells. Include triangle interiors against
terrain; vertices above a hill do not imply the spanning triangle clears it.
Convert built-world distances to
model metres by the **actual unchanged** uniform scale; keep any world-unit to
simulation-metre conversion explicit. Normals transform by inverse transpose.
The existing clearance remains in T; do not subtract it from physical errors a
second time to redefine the ground.

Let E = contact_um × 10^-6 model metres, with separately justified capture,
skinning, terrain and arithmetic uncertainty η. A sound acceptance comparison
uses an outward **upper** error bound U ≤ E. A sound impossibility witness uses
a **lower** bound L > E, e.g. max(0, measured penetration − η). E, η and actual
turn_q are currently absent; absent values yield UNRESOLVED, never guessed zero.
The cavalry helper's EPS = 1e-5 is its reconstruction residual, not E or η.

If exact native endpoints, geometry and placement are immutable, then for every
provider F, `F(0;φ0,φ1)=Native(φ0)` and `F(1;φ0,φ1)=Native(φ1)`. Consequently:

`sup_domain error(F) >= sup_native_endpoints penetration(Native)`.

At the raw .73 point, ignoring uncertainty **only for the arithmetic example**,
`ceil(.023272148064053248 × 10^6) = 23273 µm`. Native gives the same integer
lower threshold, but the actual terrain example gives `24811 µm`. These numbers
are necessary floors for those witnesses, not proposed policies, whole-domain
maxima or PASS limits. For illustration E=20,000 µm fails the flat native witness
if η < 3,272.216320 µm; E=30,000 µm is not disproved by this one witness, but
does not establish feasibility, justify that budget or clear visual penetration.

This is a finite-E obstruction. The special case E=0 is also impossible at that
fixed below-ground endpoint, but is **not** a claim that CF04c approved E=0 or
that every original finite E is impossible. A constant common height shift can
only remove one class of error by changing protected seating and potentially
creating hover elsewhere; a phase-dependent shift violates the same boundary.
No interior solver can change this endpoint inequality.

The authority decision is therefore precise: **do not enlarge E from these
measurements and do not approve the present baseline as physically safe**.
Retain absolute adverse values and their uncertainty. An admissible E requires
independent physical/visual error justification under the original near/far
scale and contact requirements, reviewed with the certificate; it cannot be
`ceil(max failure)` or a source-equality allowance. No such justification exists
in the supplied frozen evidence. A budget below a proved L requires an explicitly
authorized endpoint/source or placement amendment; a budget at least L still
requires the construction and full-domain proof below. This is a missing
acceptance input with a numerical decision boundary, not permission to shrink
the domain or to declare the original contract contradictory without E.

## 3. Selected construction and callable boundary

The selected route is **physical contact trajectories first, coupled full-skin
verification second**, using the accepted
[Map3DCavalryPivot.sample](../../../scripts/map3d/map3d_cavalry_pivot.gd) only
when its measured royal inputs satisfy its existing contract. Its exact native
endpoints, fixed origins/stretch/shear, joint limits, attachment positions and
other-local pass-through rules stay unchanged. Independent hoof solves do not
prove safety of vertices influenced by several bones or horse/rider/gear.

Proposed pure API (new names, not installed behavior):

```gdscript
Map3DRoyalLocomotion.prepare(source: Dictionary, physical: Dictionary,
    operation: Dictionary, boundary_kinematics: Dictionary,
    profile: Dictionary) -> Dictionary
Map3DRoyalLocomotion.sample(prepared: Dictionary, phase: float) -> Dictionary
```

Prepare returns `{ok, prepared, diagnostics}`; sample returns
`{ok, locals, contacts, diagnostics}`. Rejection has empty prepared/locals,
named reason, parameter cell and witness; no partial pose. No Node, Game, clock,
state read, file loading or mutation in either method. Inputs/outputs are detached
copies. Prepared binds hashes of all inputs and the applicable certificate/profile.
It never repairs an endpoint, clamps an invalid phase or converts failure to idle.
These candidate methods remain unconnected until the separate consumer step.

Inputs and data flow:

1. A source adapter reads the accepted installed AnimationPlayer resource,
   Skeleton3D and Skin once. It supplies immutable hierarchy/rest/true binds,
   anatomical landmarks, exact native MARCH tracks/interpolation/loop semantics,
   all mesh arrays, packed weights, source digests and operation endpoint values.
   Capture exact requested phases; finite cached phases cannot be nearest-neighbor
   native authority. Reconstruct tracks only after native API equivalence is
   bounded at keys, off-keys and loop seams. Cache identity includes import/Godot
   version and all source hashes. A stale or incomplete cache rejects.
2. The admitted consumer supplies the validated copied operation: integer
   start_heading_udeg, signed turn_udeg, t0_q/t1_q (duration_q=t1_q-t0_q),
   operation index and receipt/cursor binding, plus independent native
   φ0/φ1 in [0,1). End heading is exact integer modulo; zero turn is hold, never
   a fabricated pivot. Phase is [0,1]. Use all nonzero integer microdegree turns
   in (-180,180], all 360-million headings, both signs and +180 tie. Duration is
   every admitted positive integer duration in Q; `duration_q/Q` is dimensionless
   substep share, not the source clip's 12 seconds or real wall time.
   Boundary kinematics below are also mandatory: these pivot fields and native
   phases alone do not determine neighboring move speed or native phase rate.
3. Physical supplies actual immutable placement/scale and a bounded terrain
   patch covering the **whole swept skin**, including height/normal interpolation,
   LOD discrepancy, valid spatial domain and uncertainty. Its domain is inherited
   from accepted reachable land/placement, not a hand-picked flat subset.
4. Profile supplies fixed material patches, native stance/airborne intervals,
   measured sole offsets, actual royal joint/bend limits, interpolation cells,
   contact control coefficients and their proof bounds. R1 supplies the measured
   inputs; R2b below produces the coefficient resource consumed by R2a. These are authored
   measurements/coefficients, not hardcoded cavalry dimensions or enlarged joint
   limits. Old probe PI limits, identity offsets, two phase pairs, 15-degree
   steps and 0.08/12 transition fractions are only finite diagnostic recipes.
5. Prepare checks endpoints against physical bounds before constructing any
   middle motion. It chooses the profile cell and contact schedule, evaluates
   native entry/exit and the full authored reference, then supplies those actual
   values to the existing kernel. Sample uses the same prepared coefficients
   at requested u; no iterative state from the preceding rendered frame.
6. Independent certificate evaluation deforms every vertex of both authored
   reference and final output, then measures physical errors/envelope. Only
   after accepted CERT and POLICY does the separate consumer apply local poses
   to the admitted figure. Simulation origin/yaw, seat, scale, cost and RNG are
   untouched; observed hostile current-pose data never grants future operations.

### Boundary kinematics and derivative authority

Use one unwrapped substep coordinate `s = substep_index + time_q/Q` across
adjacent slices. For a pivot starting at s0, `D = duration_q/Q` and
`u=(s-s0)/D`. Derivatives refer to the continuous extension of the committed
piecewise interpolation, not finite differences of the integer cursor or rendered
frames. The existing shared clock maps wall time to s. Pause, 1x/4x and FPS do
not change these derivative inputs or divide by a zero wall-clock rate.

`boundary_kinematics` is a copied, versioned transient input with `entry` and
`exit` records plus receipt/cursor, adjacent-operation digest, native phase-law
digest and placement/terrain digest. Each boundary record contains **both** the
adjacent-MARCH side and the pivot-inside side:

- `model_to_world` H and `model_to_world_ds` H_s: full homogeneous affine value
  and one-sided derivative, including fixed ordinary scale, actual origin,
  seat/orientation and committed yaw. H_s has bottom row zero. Translation
  derivative is built-world units per s; angular rates are radians per s.
- `phase_rate` r = dφ/ds and `phase_side` (left/right branch at a key or seam)
  on the adjacent native side; the source supplies the corresponding exact
  native affine value and one-sided derivative dM/dφ. Phases use an unwrapped
  local lift at the seam before native lookup. The pivot-inside pose derivative
  is an output constraint derived below, not another invented native phase rate.
- Exact copied adjacent op kind, interval, endpoints and yaw, or an explicit
  authoritative hold/endpoint-only boundary classification. Missing neighbors
  are not silently zero-rate holds. Endpoint-only load display does not claim
  a motion transition or authorize rewind.

The consumer derives these values from admitted neighboring operations and the
same approved native phase law used by playback, never hidden future orders or
the camera. In simulation coordinates an op's origin derivative is
`Q*(b-a)/(t1_q-t0_q)`; yaw derivative is
`Q*turn_udeg/(t1_q-t0_q) * π/180_000_000`, followed by the existing pack-to-world
axis convention. The physical transform derivative includes the actual seat/
terrain response. Recompute/validate those relationships and C0 transforms;
reject missing, nonfinite, stale or inconsistent rates and branch selections.
All identities/values are bound into prepared data and certificate/profile domain.
They are never written into simulation state as a second timing authority.

For native hoof affine `M(φ)=G_hoof(φ)*sole_offset`, the adjacent world contact
and its derivative are

`C = H M`, `C_s = H_s M + H M_φ r`.

This chain rule includes origin, yaw, seat and animation terms. At entry use the
preceding op's left limit; at exit use the following op's right limit. Derivatives
on the pivot side generally differ for the actor carrier H, even when its value
is continuous. Matching that adjacent contact derivative on the pivot side
requires the hoof-local global derivative

`M_u = D * H_pivot^-1 * (C_s_adjacent - H_s_pivot M)`.

This is a feasibility constraint on the permitted limb/reference derivatives,
not permission to change H or native endpoint values. Apply the same product
rule through parent/local affines and full weighted skin; a matching rigid hoof
frame alone does not prove that a mixed-weight sole patch has matching velocity.

The kernel's contact segments use its fixed START frame. Let S be the fixed
model-to-world start frame (including scale); then supply
`C_START=S^-1 C` and `dC_START/du=D*S^-1 C_s`. S is constant: do not differentiate
an animated frame or replace the start frame at each sample. The kernel's turn
Y(u) must satisfy `H_pivot(u)=S Y(u)` in that certified placement domain; validate
this against actual seating. If a changing seat/tilt makes that factorization
false, the fixed-START kernel cannot represent a world-fixed stance as declared:
reject with the actual carrier mismatch and retain it as an unmet prerequisite,
not a transform to omit. Kernel full-affine derivatives obey its existing
orientation/stretch conventions and phase units; the adapter must convert the
matrices above accordingly, including the factor D.

**C1 scope:** internal contact-curve joins promise C1 in u. At each MARCH↔pivot
boundary require exact C0 native pose/skin and explicitly test the one-sided
world material-contact derivative using the inputs above. A C1 contact claim
requires equality of those derivatives; otherwise retain the precise defect,
never zero the input or label a moving patch planted. The engine root remains
its committed piecewise-linear XZ/yaw and need not be C1 at stop/pivot boundaries.
This document promises no universal C1 for that root or all non-contact mesh
vertices. A contact solver may compensate only through its permitted limb/
reference derivatives; if those constraints cannot satisfy a required join,
return FAIL/UNRESOLVED and preserve original physical/visual acceptance. No root
smoothing, retiming or hidden transition outside the committed pivot is allowed.

**Explicit R2 prerequisite:** accepted BodyMotion provides op timing/geometry,
but neither a bare pivot request nor the old `gait_rate` function supplies this
complete native phase-law and two-sided seated-transform contract. R1 may capture
native derivatives; it cannot invent neighboring motion. Before R2a/R2b claim
executable MARCH boundary matching, the dispatcher must bind an approved admitted
phase-law/kinematic derivation with its full reachable rate/placement domain.
If that requires a caller or timing implementation, register its literal files
separately before editing; none is authorized here. Synthetic supplied kinematics
can test the pure component, but cannot clear this production prerequisite.

How the profile is constructed is part of this contract, not a caller omission:

- Partition native phase at every imported key, loop seam and authored support
  change; partition angle at wrap/+180 and every schedule change. Include both
  one-sided limits. Use the actual native phase torus, not one pair of endpoints.
- For each cell, author a four-hoof step sequence with nonoverlapping per-hoof
  stance/swing intervals. Stance uses fixed material terrain anchors. Swing
  position uses piecewise cubic Hermite curves through a terrain-clearing lift
  waypoint. Sole orientation uses SO(3) exponential-coordinate Hermite and
  positive stretch interpolation; never coefficient-lerp through a singular
  180-degree basis. Whole-affine value and phase derivatives agree at joins.
- Endpoint sole transforms/derivatives use native FK and the two-sided chain
  rule above, including neighboring origin/seat/yaw and phase rates. A planted
  stance has zero world derivative; if incoming native motion does not match,
  a finite swing/contact-transfer interval is necessary. Calling that interval
  stance or setting its derivative to zero does not fix the discontinuity.
  C0 exact endpoint equality is mandatory; prove C1 only in the scope above,
  with the specified one-sided branch at native nonsmooth keys.
- Choose step count, knots, lift and reference rotations jointly by constrained
  minimization: first minimize the maximum physical material-point error; among
  feasible results minimize squared change from the native/reference rotations.
  Constraints are the kernel's unchanged anatomical/affine limits, fixed root,
  exact endpoints, contact intervals, full-skin R and no introduced skin defects.
  Candidate search may call the existing kernel; its finite success is not proof.
  Use a fixed variable order/seed and deterministic tie order in offline fitting.
  Do not encode any of these parameters as new runtime tuning constants.
- Store a piecewise coefficient map over the **parameter cell**, not a finite
  pose table with nearest-phase lookup. Adjacent cells agree on values and any
  promised derivatives. At endpoints return the supplied exact native affines;
  prove interior limits reach those same affines (an endpoint branch alone can
  hide a jump). Duration changes derivative units by 1/duration; it does not
  normalize all turns to a 12-second clip or create extra waiting time.

The fitting procedure is executable but is not a theorem that a feasible profile
exists. Bounded search or certification exhaustion returns UNRESOLVED with the
uncovered cell; a witnessed violation returns FAIL. Neither may set all_turns.
A converged solution must carry the following domain proof. If satisfying these
constraints requires changing the kernel's allowed locals/origins/limits, stop
with that exact counterexample; this document does not authorize that change.

## 4. Continuous acceptance, arithmetic controls and stopping rules

Finite native/dense checks are independent adversarial tests. Continuous coverage
uses outward-rounded interval enclosures of imported interpolation, the profile,
FK, raw-weight LBS and terrain on **all** cells in
`(heading,turn,duration_q,φ0,φ1,u,boundary_kinematics,admitted placement/terrain)`.
Include all reachable neighboring move/hold rates, native phase rates/branches
and one-sided carrier derivatives under the approved phase law; identical endpoint
poses do not collapse different derivative contexts into one cache/profile cell.
Discrete integer axes may be bounded in blocks; continuous phases include every
real point and one-sided seam. Unbounded or unspecified terrain/scale inputs
prevent a universal certificate; record the inherited admissible domain explicitly.

For each parameter coordinate j, propagate affine product bounds. For
`G=AB`, `t=a+A b`, use
`||∂jG|| ≤ ||∂jA||||B||+||A||||∂jB||` and
`||∂jt|| ≤ ||∂ja||+||∂jA||||b||+||A||||∂jb||`.
For skin point v sum the actual nonnegative packed weights times
`||∂jG_k||||B_k^-1[v,1]||` in homogeneous form. Do not divide by weight sum.
Terrain derivative bounds add the true surface gradient and placement error.
For cell center c and half-widths r_j, a certified Lipschitz bound gives
`error(z) ≤ error(c)+Σ L_j r_j+η`; a directly enclosed interval is also valid.
Bound squared radius about the committed origin against R² using actual scale.
Split cells where the bound is too loose; a high upper bound alone is unresolved,
not a witnessed failure. Include all mesh vertices and the established CF01
body/weapon definition; keep full-equipment diagnostic results as well.

For the iterative kernel, a numerical residual/iteration cap alone is inadequate:
either certify a unique continuous solution branch by interval Jacobian/contraction
bounds with joint-limit margins and bound the actual returned result, or enclose
the actual finite algorithm and every branch taken across the cell. Singularities,
changing active constraints, antipodal rotations and step-count changes need
explicit subdivision/join proof. Positive determinant and finite singular-value
bounds are required throughout. No universal convergence is assumed.

Accept only if every required cell is covered, all error upper bounds fit an
independently justified E, the full envelope fits real R, native endpoints are
exact, and required native visual/performance checks pass. An inconclusive cell,
native discontinuity, missing stance provenance, unknown error allowance or lost
process receipt remains separately named. A successful report-writing process
can still report FAIL/UNRESOLVED; process exit and motion verdict are separate.

Mandatory hand-computed and negative controls for the future implementation:

- Flat raw/native .73 arithmetic above, plus terrain .73; all remain included.
  Verify the same model error at scale 1 and scale 2 (world distance doubles).
  Translate/rotate both ground and actor together: error unchanged; move only
  the actor: error changes. No ground fitted after observing the posed hoof.
- Fixed-bake witness: subtract `[.30663679988527087,2.1429267468144504,-1.0967962579645545]`
  from `[.4339753766858621,2.4051723976923536,.3996451637692787]` and take norm:
  `1.5245736529360432`. A prospective exact-native endpoint must instead give
  exact equal locals and native skin agreement at the original precision.
- Radius arithmetic: `749-748.8595829969472=.1404170030528` simulation metres
  sampled margin; `789.9554707346122-749=40.9554707346122` upper-bound excess.
  Classify these as sample-within / bound-inconclusive, never escape/PASS.
- Synthetic stance points at (0,0,0) and (.001,-.002,0), ground y=0 and anchor
  (0,0,0), give slip 1 mm, penetration 2 mm, max error 2 mm. With exact arithmetic
  E=1999 µm fails and E=2000 µm passes only this synthetic point; no royal policy.
- For a cell radius .1, center error .001 and proven derivative bound .02,
  upper error is .003 before η; a .0025 budget is inconclusive until refinement,
  not an observed .003 error. Test outward rounding near every threshold.
- Same native scalar pose `p(φ)=φ`, φ=.25, D=.1, fixed carrier: adjacent phase
  rates r=1 and r=2 require `dp/du=.1` and `.2` respectively. If the neighboring
  origin additionally moves at 3 model metres per s, total contact derivatives
  are `.4` and `.5` per u. The stationary pivot must supply those contact
  derivatives through permitted locals, not continue translating its root.
  Different rates must produce distinct prepared identity/constraints; omitting
  either adjacent record must reject, not return the same cached trajectory.
- Planar chain-rule control in standard XY coordinates: M=(1,0), neighboring
  translation rate (3,0), native rate 0 and neighboring angular rate 0; pivot
  angular rate 2 radians per unit s, D=.1, H=identity at the boundary. Required local
  `M_u=.1*((3,0)-(0,2))=(.3,-.2)`; adding the prescribed pivot carrier term
  `(0,.2)` gives world contact derivative `(.3,0)`. The actor angular-rate
  jump remains. With constant START basis `2*R90`, world derivative `(0,4)`
  converts to START derivative `(.2,0)` per u, not `(.4,0)` or `(0,.4)`.
- Both signs, ±1 microdegree, near 180/+180, heading 76.000012→256.000012,
  350→10 and reverse, duration 1 and Q and original finite duration cases,
  φ0/φ1 independently at keys/off-keys/.73/seam. Never replace a request by
  nearest cache entry; mutated input/digest, wrong units/binds/weights, zero
  duration, invalid phases, missing/inconsistent two-sided kinematics or phase-law
  identity, unsupported moving carrier, broken C1, singular basis and terrain holes reject
  atomically. Repeated sampling in arbitrary order must be identical.

## 5. Exact future steps, ownership and conditional source change

These are proposed boundaries only. This document starts no session or product
change. The sole dispatcher must reconcile the live registry and existing PRs,
then register each once with its own fixed pair, exact scope and acceptance.
All depend on this document's accepted merge; none depends on failed CERT being
accepted. No new worker takes the original CERT's four files.

**R1 — Native/physical input resource**, after this doc and accepted royal clip.
Proposed exact owned paths:

```text
scripts/map3d/map3d_royal_locomotion_source.gd
scripts/map3d/map3d_royal_locomotion_source.gd.uid
tests/map3d/test_royal_locomotion_source.gd
tests/map3d/test_royal_locomotion_source.gd.uid
assets/3D/units/royal/royal_locomotion_source.tres
```

The source script is a typed Resource for measured immutable calibration plus
native-resource extraction, not another state/clock authority. The `.tres`
contains actual named anatomical landmarks, material patches, sole frames and
their provenance; it must not duplicate all native animation keys or include a
guessed policy. Author resources through the editor as required. Acceptance:
exact native keys/interpolation/geometry/binds, detached validated source input,
actual independently supplied terrain/seat measurements, .73 raw/native/terrain
distinction, original adverse values, uncertainty, all-mode penetration and the
finite-E decision table in §2. Its tests include corrupted/stale data and the
hand cases. It may deliver UNRESOLVED contact disposition honestly; that is a
usable input component, **not an accepted contact prerequisite for activation**.
No new general-purpose research report or second certifier is required.

**R2a — Royal parameter evaluator**, after R1's component acceptance, the explicit
boundary-kinematic/phase-law prerequisite in §3 and a documented physically
justified endpoint budget/domain decision. Exact paths:

```text
scripts/map3d/map3d_royal_locomotion.gd
scripts/map3d/map3d_royal_locomotion.gd.uid
tests/map3d/test_royal_locomotion.gd
tests/map3d/test_royal_locomotion.gd.uid
```

Implement §3 prepare/sample using R1 and the accepted kernel; expose the full
parameter input, profile-cell schema and uncovered-cell diagnostics. This script
is also the typed Resource for a profile (static evaluator methods do not mutate
that resource); the new `.tres` below binds the measured source and certified cells.
No runtime hookup, bake rewrite or source/seat change. Prepared operation data
is transient, not another saved authority. Missing coefficients reject, never
default to the fixed bake. Component acceptance includes endpoint equality,
limits, original precision, synthetic profile-bound tests and all malformed-input
cases. This evaluator component alone is **not** the promised total provider.

**R2b — Coupled profile construction**, after R2a and the same resolved endpoint
budget/domain and boundary-kinematic decisions. Proposed exact owned paths:

```text
tools/units3d/royal_install/locomotion_profile.gd
tools/units3d/royal_install/locomotion_profile.gd.uid
tests/map3d/test_royal_locomotion_profile.gd
tests/map3d/test_royal_locomotion_profile.gd.uid
assets/3D/units/royal/royal_locomotion_profile.tres
```

Implement the fixed-order constrained fit and subdivision in §3–4, calling the
accepted native adapter/evaluator/kernel, with no duplicate IK implementation.
The installed profile stores coefficients, measured inputs and proof-domain
identity, not sampled replacements for native endpoints. Tests exercise the
hand bounds, joins and failed/unresolved cells. Author the resource through the
required editor workflow. Acceptance is the **whole** original parameter domain,
with reviewable construction bounds and no omitted cell; independently rerun
adversarial samples through R2a. A search timeout or a subset is not this step's
acceptance. Preserve counterexamples and stop if the conjunction cannot be
certified; do not dispatch additional unspecified solver research or relax E.
R2a plus an accepted R2b is the proposed total provider input to original CERT;
CERT still independently verifies it and performs its original window gates.

**Original CERT resumes** with its original owner and unchanged four paths only
after accepted required inputs/provider are available:

```text
tools/units3d/certify_royal_locomotion.py
docs/reviews/cluster-formations/evidence/locomotion/royal/source.json
docs/reviews/cluster-formations/evidence/locomotion/royal/pivot-contacts.json
docs/reviews/cluster-formations/evidence/locomotion/royal/pivot-envelope.json
```

It independently audits actual provider output over the full original domain,
including the untouched counterexamples; then actual-window motion/performance
and unique Review/current-HEAD CI. Only accepted CERT → separate royal POLICY
→ all-arm CONSUMER/activation as in CF04c. No policy/source.json write by R1/R2,
no circular requirement that CERT pass before its input component can be built.

**Conditional correction, not an authorized shortcut:** if endpoint lower bound
L exceeds justified E (or actual physical/visual requirements reject that endpoint),
R2a/R2b cannot cure it. Preserving native endpoints, seat and source then has no
solution for that stated E/domain. A separately authorized source amendment
would need to explicitly replace the protected MARCH-endpoint baseline while
retaining originals and all other requirements. The smallest candidate source
scope is exactly `tools/units3d/royal_install/install.py`, new
`tools/units3d/royal_install/march_contact.py`,
`assets/3D/units/royal/royal.glb`, and
`assets/3D/units/royal/royal.glb.import`; stage on a copy of the retained 20k blend
under that object's model_wip. It must produce a newly approved native source,
not an invisible correction falsely called the old native endpoint. This changes
an original preservation clause and therefore is **not dispatchable from this
doc alone**. No numerical evidence currently proves this is the sole remedy.

A scene/root/seat alternative would touch `scenes/models/units/royal.tscn` or
`scripts/map3d/map3d_unit_rig.gd` and would alter protected placement, potentially
all arms. It is not selected: no constant-seat feasibility proof has been supplied.
Do not edit those files or the cavalry kernel under the source/provider scopes.
Any such amendment needs its exact independent necessity, affected contract
clauses, tests and ownership recorded before dispatch. Raising R, shrinking
scale, changing ground, hiding the rider/gear or excluding .73 is never a remedy.

## 6. Preserved acceptance and document verification

Retain original old-five animation/accessor/BIN preservation, actual native
skin/binds/rest/gear, all phases/headings/durations, ordinary reference scale,
actual R, terrain seat, positive affine/joint rules, exact endpoints, unchanged
EPS/precision, source-native comparison and all original failed variants. This
document adds no source-equality waiver, guessed contact_um/turn_q, enlarged
numerical epsilon, test/timeout exception or supported-subset completion.

All twelve [original design §9 goals](../../superpowers/specs/2026-10-25-cluster-formations-design.md#9-实施验收清单尚未执行)
remain required in full:

1. Ten-person display/count changes and conserved personnel with fixed footprint.
2. Full-radius clearance, yielding, opposing/three-way/narrow/turn/reload cases.
3. Exact eligibility and missing/extra/zero-fit/uncontrollable cases for all eight formations.
4. Independent speeds, assembly/slowest formed speed and immediate local budgets.
5. Actual delivery, partial arrivals, stale-version protection and accompanying king.
6. Vulnerable assembly and reinforcement without penalizing a stable old line.
7. Physical reform/expansion, partial selection and exactly one membership/action.
8. All eight normal/blocked/member-loss cases, real flanking and valid artillery.
9. Physical melee/ranged contact, range/occlusion and explained nonduplicated bonuses.
10. Save/input/speed/camera/offscreen determinism, no double costs, old-save personnel.
11. Reproducible equal-input formation-versus-none and countered outcomes.
12. Actual unique 3D-map windows, full/reduced strengths and performance acceptance.

The retained 55 failed / 6 risky-pending baseline is not turned green by this
contract. Gameplay-baseline reconciliation has its own bounded results; neither
it nor this doc completes P4. Future visual-review uses before/two variants,
native full-window/3x hoof crops, continuous move/pivot transitions, near/far,
actual advancing receipt clock, pause/1x/4x and differing FPS, with the unique
Review as independent critic. Preserve existing bench tier/size/budgets,
mean/median/p95 and still/pan; frozen-share clips are not clock/FPS acceptance.

This one-document PR runs the repository's Python hook/selector/runner/timeout
checks, shell/config/guide checks, whitespace, exact-scope/source-hash/link and
hand-arithmetic checks. No unrelated GUT, Godot or Blender run is needed or
claimed. Required current-HEAD harness/aggregate CI and unique independent Review
must pass; missing/failed/cancelled/timed-out or improperly skipped required
checks are not success. Review merges the document only. This step claims no
visual PASS, motion PASS, policy support, consumer activation or P4 completion.
