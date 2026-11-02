# Royal boundary phase and two-sided kinematics

Step `ROYAL-BOUNDARY-PHASE-AUTHORITY`, 2026-11-02. Implementation
`01a19cc7-f721-7292-b8eb-a82b9983b85a`; unique Review
`01a19cc8-4061-7b41-a307-89834632160a`; sole dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`. Base:
`2407bf6df47958def45f10f97ff7a69c76d1d447`. This document is the only owned file.

## 1. Decision, authority and disposition

Specify an absolute, receipt-bound native reference phase and differentiate the
actual upright carrier on **both** sides of each boundary. Native reference
phase is not a promise of a planted hoof. A stationary actor is not necessarily
a stationary native material point. The selected phase law below is an explicit
technical design choice for the candidate, not a claim that legacy playback
already implements it or that its cadence passes physical/visual acceptance.

**R2 still waits for accepted implementations and the independent endpoint
budget/domain decision.** Ordinary seating can change height during a stationary
pivot, invalidating a fixed physical START assumption. Section 6 selects an
explicit carrier pullback into the unchanged kernel's numerical chart, with
separate physical support semantics and world residual bounds. It includes the
counterexample that makes this adapter necessary. Neither the coordinate
identity nor this document proves contact feasibility or selects an allowance.

The accepted inputs are [CF04c](cf04c-locomotion-contract.md), LOCO-TIME's
[BodyMotion](../../../scripts/engine/body_motion.gd) and
[body-march guide](../../../scripts/engine/guide/body_marches.md),
[royal feasibility](royal-native-contact-feasibility.md) (#228), and R1 (#235,
merge `164c772bf6601a4023c8eb84c8635dc5567f57be`). R1's
[native source](../../../scripts/map3d/map3d_royal_locomotion_source.gd) and
[calibration](../../../assets/3D/units/royal/royal_locomotion_source.tres) supply
values and provenance, not native derivatives or a support schedule. The
original CERT proposal is `r1_input_disposition.next_bounded_prerequisite_proposals[0]`
in its owner's checkpoint, SHA256
`f12ca94503f59861b42b7d9292148cd90035a9730fdcdb367cfd84e384f1f2d2`.

All twelve P4 gates, the complete phase torus, headings, turns and positive
durations survive. Native source/root/attachments, raw weights, seat rule,
ordinary scale, R, costs, simulation clock and error tolerances are unchanged.
No product code, source asset, CSV policy, original CERT file or acceptance
record is changed. The original four failed CERT files remain with
`01a19bf2-0bbc-7281-88dc-34b3648cf95d`; they are not dependencies to execute.

## 2. Concrete native phase law

### Coordinate and frozen inputs

Use Q = `BodyMotion.LOCOMOTION_Q`. A validated driver envelope supplies exactly
the admitted receipt's `abs_day`, `substep` and `time_q`; the shared driver alone
produces time_q. Let N be that transaction's validated `substep_count`, and T be
the frozen existing `time_day_seconds` value. N must agree with the admitted
march transaction and its bound `battle_substeps` configuration; neither may be
inferred from an animation or the number of operations. L is the **actual
detached native MARCH Animation.length** from R1, in native source seconds.
Require finite positive T and L and positive integer N. The law identity binds
their exact values, source identity and the fixed coordinate convention below.

Define the absolute coordinate

```text
S = N * abs_day + substep + time_q / Q
tau = T / N                         # reference native seconds per substep at 1x
rho = tau / L                      # native cycles per unit S
```

Using abs_day rather than a day-of-month prevents a monthly phase restart.
The additive epoch is zero at abs_day=0, substep=0; it is a coordinate convention,
not a saved clock. Products, rational reductions and modulo are checked before
conversion to floats. Do not form a huge binary floating-point S and lose its
fractional part. Treat the finite stored T and L bit patterns as exact rationals,
reduce the phase modulo one using checked integer arithmetic, and round only
the final native lookup argument. If the chosen arithmetic cannot represent an
input, reject with its range witness; do not silently narrow the accepted day
range. The implementation must cover the existing valid cursor range.

For a newly born identity, define a deterministic phase offset z. Encode
`["royal-reference-phase-v1", unit, slot]` as UTF-8 strings, each prefixed by its
unsigned 64-bit big-endian byte length; slot is canonical nonnegative decimal.
Take the first 53 bits of SHA256 in big-endian bit order as h; `z=h/2^53`.
Owner, battle, array index, home slot, receipt, camera, FPS and source filename
are absent. Source/configuration hashes belong in the law identity, not the
phase seed. SHA256 is not an RNG draw.

### Law and all operation branches

The selected reference is the authored native clip at one source second per
reference second, with an unwrapped lift and periodic native lookup:

```text
Phi(S) = z + rho * S
phi(S) = Phi(S) - floor(Phi(S))
```

For an operation starting at S0 with `D=(t1_q-t0_q)/Q`, evaluate
`Phi(u)=Phi(S0)+rho*D*u`, `u in [0,1]`. Do not shortest-arc interpolate the
two phase residues: the integral winding is part of the law. Native keys and
seams inside the interval are crossed even if phi0=phi1. The pivot provider
uses exact native values at these two endpoints; its interior is the authored
contact solution, not necessarily native MARCH at Phi(u).

| Admitted branch | Native reference rate dPhi/dS | Actor derivative |
|---|---:|---|
| move | rho | committed translation, constant yaw |
| pivot reference | rho | zero XZ translation, committed yaw rate |
| active hold reference | rho | zero XZ and yaw; native reference still advances |
| paused driver | same derivative with respect to S | S does not advance in wall time |
| endpoint-only load/display | no transition derivative claim | exact committed endpoint only |

An active hold in this law is explicitly a **continuing MARCH reference**, not
an asserted GARRISON pose or planted stance. Its native movement and penetration
must be included in contact/visual acceptance; they can fail it. Switching to
GARRISON, freezing phase on holds, using speed-proportional cadence, adding
jitter or substituting a footfall would be another phase law, with different
boundary inputs and a separate approved contract. None is an implicit fallback.
There is no claim that this choice repairs legacy stride mismatch. The existing
`Map3DUnitRig.gait_rate`, march lag, clip-chain and settling helpers are not
called by this law. In particular their wall-speed clamp cannot be composed
with this law at 4x and still claim the same derivatives.

This choice avoids a history-dependent gait accumulator or new saved phase
authority. Native length is not guessed from the fixed pivot bake: the installed
GLB's MARCH accessor maximum is about 0.5333333333 seconds, while R1's detached
native length remains the lookup authority. Neither this observation nor a
12-second pivot clip substitutes for L. The GLB has LINEAR and STEP source
samplers; the importer preserves the pivot pair specially, not the old MARCH
tracks. Therefore raw-GLB interpolation is not native derivative authority.

### Initial binding, continuation and load

The complete immutable identity is `(unit,slot,law_version,source_identity,
T_bits,N,L_bits,z_definition)`. The copied request additionally binds the
current and neighboring receipt/cursor/operation indices and placement identity.
Two contiguous receipts must describe the same S at their common boundary,
same identity and exact endpoint XZ/yaw. Recompute phase from the absolute
coordinate; never advance it by adding the previous frame's delta. Identity
transfer preserves z and the same child. Removing a slot does not renumber or
reuse surviving slots.

A brand-new candidate identity begins at its calculated native phase. Adopting
an already shown legacy figure is not permission to snap its pose: its existing
native pose/phase must equal the calculated boundary value or adoption returns
`initial_native_phase_mismatch`. There is no hidden transition or reset. This
candidate remains unavailable for that adoption until a separately authorized
transition exists. It does not make the old save invalid.

Pause holds the cursor and therefore every sampled value. At 4x the same S
produces the same pose as 1x; only the existing driver's rate of visiting S
changes. Arbitrary sample order, missed frames and near/far/offscreen changes
do not affect phase. At the day seam `(d,N-1,Q)` equals `(d+1,0,0)`.
On load, a matching explicit in-slice envelope reconstructs the same S and
phase without saved floats or a phase counter. Without that envelope show the
saved receipt's exact final pose at its Q, classified `endpoint_only`, and do
not replay it. Missing/stale law inputs do not justify guessing a phase.
Changing T, N, L or source while retaining a receipt rejects; no automatic
re-seeding or normalization is permitted.

### Domain, rather than a sampled phase atlas

For each frozen law identity the reachable native rate set is exactly `{rho}`;
it is not `{0,rho,4*rho}`. The latter two wall-clock transformations are not
derivatives in S. For multiple accepted frozen configurations retain the union
of their exact rho values and identities. Native interpolation branches are all
enabled native track cells, key sides, wrapped cells and seam sides traversed
by that rate, including repeated windings. A missing finite rate bound for a
claimed family prevents that family's certification.

Production requests must satisfy phi1 = frac(phi0+rho*D). This relationship
does **not** shrink the original provider/certificate domain. R2/CERT must
still cover independent `(phi0,phi1) in [0,1)^2`, all native branches and all
original durations/turns. Treat the independent pair as an over-approximation
for proof and explicit diagnostic controls, not a second production override.
Record `production_bound` versus `proof_domain_control`; a synthetic arbitrary
pair must never acquire a production receipt. Endpoint equality on that torus
is mandatory even for pairs not reached by this selected law.

## 3. Actual upright carrier and its derivatives

The placement authority is the upright path in
[Map3DBattleGroups.place](../../../scripts/map3d/map3d_battle_groups.gd), the
fractional conversion required by [CF04c render](cf04c-render-contract.md),
[Map3DUnits.footprint](../../../scripts/map3d/map3d_units.gd), and
[Map3DContext.height_at](../../../scripts/map3d/map3d_context.gd). The tilted
legacy `Map3DUnitRig.seat/plant` path is a separate domain. Do not substitute it.

For a copied op let `v_m=Q*(b-a)/(t1_q-t0_q)` for a move, zero otherwise.
Let `w_pack=Q*turn_udeg/(t1_q-t0_q)*pi/180000000` for a pivot, zero otherwise.
With `alpha=meta.m_per_px/ArmySystem.metres_per_pack_px(repo)`,

```text
O_xz = pack_origin + alpha * interpolated_xy_m
O_xz,S = alpha * v_m
theta = -pi/2 - heading_udeg*pi/180000000
theta_S = -w_pack
```

Do not round interpolated metre coordinates through `metres_to_pack(Vector2i)`.
The nonzero facing direction does not apply royal `stand_deg` as an extra yaw.
Keep an unwrapped theta locally when differentiating through the heading seam.

Let k, extent, height and ring count be the existing upright child values,
measured/derived with all authored ancestor transforms and the unchanged
ordinary reference scale. At base, footprint includes the center and two
elliptical rings (`share=1/2,1`); retain every configured ring sample. Define
unrotated scaled offsets a_j exactly as `footprint`, and its world-XZ rotation
`R2(theta)=[[cos(theta),sin(theta)],[-sin(theta),cos(theta)]]`:

```text
q_j = O_xz + R2(theta)*a_j
q_j,S = O_xz,S + theta_S*R2'(theta)*a_j
y = max_j height_at(q_j) + height*k*seat_clear - sink
P = affine(k*R_y(theta), (O_x,y,O_z))
H = P*A
```

A is the frozen transform from the upright group root to the R1 model root.
Include the actual per-figure stature and every intervening authored transform;
do not apply scale twice when extracting A. R1's model_from_skeleton and true
binds then supply model-space geometry. A is not fitted to animated hooves.
Record A and the k/extent/height derivation in the placement identity. A changed
reference size, ancestry or source invalidates the input rather than rescaling
it into agreement. The actual R1-root carrier H, not merely P, enters the chain
rule. If A is not constant over an operation, include its true derivative and
declare the corresponding unsupported domain; never discard the extra term.

On a smooth height branch, `h_j,S = grad(height_at)(q_j) dot q_j,S`.
At a unique maximum, `y_S=h_j,S`. At a tie, evaluate the active branches on
the requested side: the right derivative of the max is the maximum of their
right directional derivatives; the left derivative is the minimum of their
left derivatives (all derivatives use increasing S). Do not average normals
or arbitrarily pick the first tied sample. Then

```text
P_S = [ k*theta_S*R_y'(theta) | (O_x,S, y_S, O_z,S) ]
      [           0         |             0       ]
H_S = P_S*A                 # A constant; homogeneous derivative bottom row zero
```

For a terrain cell boundary also retain the incoming/outgoing interpolation
branch. The actual native Terrain3D height method decides these branches; do
not assume bilinear, triangle-diagonal or filtered sampling from a screenshot.
`height_at`'s sea clamp is `max(raw_height,sea_y)`: differentiate the selected
branch, including both one-sided branches at equality. Its NaN/no-terrain sea
fallback is visible behavior, **not evidence of valid flat land**. A hole,
missing native data or unproved height override makes the corresponding
kinematics/physical coverage unavailable. A native capture must distinguish raw
height, sea clamp and `height_fn` override and bind their bytes/method/version.

The required domain is every terrain location swept by every admitted royal
body operation under the accepted measured-circle land/bounds validation, every
allowed heading/turn and ordinary placement input, not a flat or lowland subset.
It includes all footprint-sample curves and the entire swept skin/triangles.
The placement derivative needs all sample curves; physical certification also
needs intervening terrain and rendered-surface/LOD discrepancy. The latter is
not silently zero because the height sampler has a derivative. Retain native
rounding and branch uncertainty separately from physical E.

## 4. Native jets and the complete copied boundary

The native derivative component must return, for an exact requested phase and
one-sided branch, native value plus a proved derivative of the underlying
interpolation extension and a native arithmetic enclosure. A float32 sampler
is not literally a differentiable staircase. Finite differences of rendered
frames or a raw GLB curve are not that extension/proof. Bind the exact Godot
build, native import bytes/receipt, R1 digest, track enable/interpolation/loop
flags, key times/values/transitions, local baseline TRS, ancestry and Skin binds.

Differentiate the native position/scale/quaternion interpolation actually
selected by those flags, including quaternion sign/shortest-path and small-angle
branches. The component must establish equivalence for every actual branch;
an unimplemented interpolation kind or ambiguous branch returns uncovered.
Convert native-time derivatives by multiplying by L to obtain d/dphi. For
constant/disabled tracks retain their actual baseline and zero derivative.
STEP cells have zero derivative inside and separate values on each key side;
a discontinuity is not assigned a finite crossing derivative. At a loop seam
keep `1-` and `0+` separate even though lookup phase is in [0,1). Reject a C0/C1
claim when their corresponding values/derivatives do not satisfy it.

For each skeleton-space local affine L_i and parent global G_p, compute
`G_i=G_p*L_i`, `G_i,phi=G_p,phi*L_i+G_p*L_i,phi`. For a measured sole frame
O_i and fixed F=`model_from_skeleton`, set `M_i=F*G_i*O_i` and
`M_i,phi=F*G_i,phi*O_i`. For material points follow R1's actual order:
`p_skel=XYZ(sum_k w_k*G_k*B_k^-1*[v,1])`, then
`p_model=F*[p_skel,1]`; its derivative uses F's basis on the weighted position
derivative. Keep the actual four packed weights and true inverse binds without
normalizing. F's translation is added once after the weighted sum, not once
per influence. A rigid hoof jet does not replace the mixed-skin material jet.

A copied `boundary_kinematics` packet has a closed versioned schema:

| Record | Required content |
|---|---|
| identity | unit/slot; current receipt/cursor/op index; law/source/placement/terrain identities; canonical full-packet digest |
| entry | preceding op's left limit **and** pivot's right limit |
| exit | pivot's left limit **and** following op's right limit |
| each side | exact admitted op/cursor/receipt/index or explicit endpoint-only classification; S and duration; H and H_S; native phase/lift/winding and source branch; native affine/skin values and derivatives/enclosures |
| neighboring binding | copied operation bytes, admission proof identity, continuity with current op, source of each side; no hidden future orders |
| domain | exact parameter cell, active terrain/seat/native branches, arithmetic uncertainty, covered/unavailable reasons |

For the pivot-inside side, the native reference jet is not the solved limb jet:
the required latter is computed below. A missing neighbor is never invented as
a hold. At a cross-receipt boundary require the actual adjacent admitted copy;
if the following receipt is not yet available, the outgoing transition is
`UNAVAILABLE_NEIGHBOR`, not certified by prediction. An endpoint-only packet
may display a value; it cannot prepare a boundary-matched motion or authorize
rewind. Observed hostile current poses cannot supply future operations through
this API. Standalone evidence uses the same copied admission boundary.

For each boundary and sole frame, with `a` the adjacent side and `p` pivot:

```text
C_a   = H_a * M_a
C_a,S = H_a,S*M_a + H_a*M_a,phi*rho
M_p,u = D * inverse(H_p) * (C_a,S - H_p,S*M_p)
```

Require C0 values first: identical world carrier/native endpoints at the
boundary, as well as exact native local/skin endpoint agreement at original
precision. Inverse derivatives are not omitted: the last equation already
contains the effect of the changing inverse through the subtraction term.
Perform the analogous product rule on each actual material point:
`x_S=H_S*[p_model,1]+H*[p_model,phi*rho,0]`. H's translation is added once,
even when the raw packed weights do not sum to one. Never normalize those
weights or apply carrier translation once per influence.
The root remains its committed piecewise motion. Required contact C1 is a
constraint on permitted local derivatives, not permission to smooth the root,
change seat, bend other bones or insert time outside the pivot.

For a fixed START frame S_f, the world curve converts as
`C_START=inverse(S_f)*C`, `C_START,u=D*inverse(S_f)*C_S`. S_f is constant.
Those coordinates are valid inputs to the existing kernel only when its
carrier factorization and endpoint checks actually hold. Otherwise use the
explicit carrier pullback of section 6; never omit the changing transform.

## 5. Executable validation and arithmetic cases

The future builder performs this sequence on detached data and publishes once:

1. Validate closed schemas, exact integer ranges, nonzero durations, full
   operation partitions, receipt hashes, admission and `(unit,slot)` ownership.
2. Validate unchanged source/import/native identity, frozen law/configuration,
   placement and terrain provenance. Recompute phase/winding from S; reject
   stale or caller-invented values rather than accepting a plausible rate.
3. Select all native and terrain one-sided branches. Recompute both sides'
   H/H_S and native/material jets. Validate C0 at entry and exit independently.
4. Form the chain-rule constraints, preserve branch uncertainty, and validate
   the kernel representation/pullback over the entire pivot. Endpoint checks
   alone do not establish a constant carrier inside it or bound a chart fit.
5. Only then return a copied prepared-boundary packet with its digest/domain.
   Any missing, stale, nonfinite, singular, discontinuous, inconsistent or
   unrepresentable input returns empty prepared data and a named witness.
   It does not publish a partial pose, overwrite a prior packet or change RNG,
   state, cursor or AnimationPlayer. Arithmetic success is not contact PASS.

Mandatory hand cases, to be transcribed into the registered components' tests:

| Case | Exact expectation |
|---|---|
| phase control T=8, N=10, L=8/15 | tau=4/5 and rho=3/2; these are arithmetic controls, not substituted native length |
| z=.1, S=2 then 2.25 in that control | phase .1 then .475; D=.25, advance .375 |
| seam z=.9, S=0, D=.2, rho=1.5 | phase .9 to .2, crossing 1 at u=1/3; advance .3, not -.7 |
| same control D=2/3 | one complete winding; equal phase residues do not mean a frozen reference |
| scalar native M(phi)=phi, phi=.25, D=.1, fixed H | r=1 and 2 diagnostic controls require M_u=.1 and .2; neither control changes production rho |
| preceding scalar translation rate 3 with those rates | M_u=.4 and .5 on a stationary pivot |
| standard XY control M=(1,0), adjacent translation (3,0), adjacent angular/native rates 0, pivot angular rate 2, D=.1 | M_u=(.3,-.2); pivot carrier adds (0,.2), leaving world derivative (.3,0) per u |
| fixed START basis 2*R90, world C_S=(0,4), D=.1 | START derivative (.2,0), retaining scale and D |
| footprint tie of f1=2S and f2=-S at S=0 | max has left derivative -1 and right derivative 2; averaging .5 is wrong |
| terrain h=.1x, sample X speed 3, no rotation, fixed clearance | seat y_S=.3; omitting it breaks the chain rule |

Also require both turn signs, +/-1 microdegree, near/+180 tie,
76.000012 to 256.000012 degrees, 350 to 10 and reverse, duration 1 and Q,
all source keys/off-keys/.73/seams, receipt/day crossings and arbitrary sample
order. Compare pause/1x/4x at identical driver envelopes, JSON-restored admitted
inputs, owner transfers, skipped frames and repeated endpoint-only rebinds.
At duration=1 quantum, retain the true Q-scaled angular/linear derivatives;
large rates are not clamped to convenient finite test values.

Mutation controls separately change each op field, each neighbor, one receipt,
source/import identity, law T/N/L/seed, branch/side, scale/A, seat sample, terrain
method/hole/sea override and derivative. Every mismatch must reject atomically.
Include stale cache reuse with identical phi but different carrier/rate/branch,
unknown next receipt, malformed absent-row admission, unobserved hostile future
data, invalid initial phase and STEP/seam jumps. Retain native rounding bounds
near all comparisons; EPS is not a physical budget.

## 6. Variable carrier: obstruction and selected pullback

The accepted kernel's contract and implementation are explicit:
[Map3DCavalryPivot.sample](../../../scripts/map3d/map3d_cavalry_pivot.gd) forms
only a yaw `turn` about a fixed axis. It checks the contact endpoint against
`turn_end * native_exit * sole_offset` and reconstructs with that yaw. It has
no translated seating carrier input. Royal feasibility section 3 therefore
requires `H_pivot(u)=S_f*Y(u)` over the certified domain.

For a centered model frame, the ordinary upright rule gives

```text
H(u) = Translation(O_x, y(theta(u)), O_z) * k*R_y(theta(u))
```

If S_f is the actual entry carrier, `S_f*Y(u)` has constant translation. Thus
the required equality implies `y(theta(u))=y(theta(0))` for every u. That does
not follow from upright placement; its max of rotated footprint heights
generally changes. A nonconstant authored root-to-model A can add another
obstruction, not cancel this one by permission.

A direct code-rule witness uses the current ring count 8, k=1, footprint
half-extents (1,2), center at (0,0), terrain `h(x,z)=.1*x`, sea below the patch,
and unchanged constant clearance c. These are a hand control of the actual
placement formula, **not a claimed native royal terrain measurement**:

```text
theta=0:       y = c + .1
theta=pi/4:    y = c + .15      # full-ring point at t=pi/4 wins
theta=pi/2:    y = c + .2
```

At theta=pi/4 the winning point has `x=1.5`; its x derivative with respect to
theta is .5, hence `y_S=.05*theta_S`. The fixed-START kernel instead has zero
carrier translation derivative and an exit height lower by .1 world metre for
this turn. No choice of phase law or contact coefficient makes those two
carrier identities equal while retaining exact native endpoints. Supplying
adjusted endpoint contacts makes the unchanged kernel's native-endpoint check
fail; suppressing the adjustment makes the world contact different. Neither
is a permitted repair.

The obstruction is structural in the actual source rule, not dependent on
these convenient extents: for a finite ellipse ring with any nonzero extent,
its support function on a nonzero planar slope varies with yaw in general.
Even equal half-extents with a finite ring do not give the continuous circle's
constant support between sample directions. The required domain has no rule
restricting all royal pivots to constant-height footprint samples. A universal
fixed-START claim therefore needs an actual all-reachable-domain constancy
proof; accepted land-circle admission and the finite legacy tilted witness
provide no such proof. This document does not label a synthetic slope as an
observed failure of a particular installed map cell.

**Disposition of the unadapted route:** preserve `CARRIER_NOT_FIXED_START` with H, S_f*Y, their
derivatives, the active seat samples/terrain cell and exact input hashes. If an
actual cell gives a nonzero residual beyond its outward arithmetic enclosure,
that cell is a representation FAIL. An unproved actual cell is UNRESOLVED.
Neither is removed from the required domain or converted to contact PASS.

This proves failure of the **declared fixed-world-START representation**, not
that the numerical limb solver cannot be reused. This contract selects a
carrier pullback outside the kernel. This is the precise technical amendment
to royal feasibility section 3's fixed-START caller precondition; all physical
stance, native endpoint, root/seat/scale and acceptance requirements remain.

Keep kernel FK in its original native skeleton chart; do not bake a placement
into its root local. With F=R1's fixed model_from_skeleton, let `H_k=H*F` be
the actual world carrier of that chart. Use the kernel's existing relative turn
Y and actual native skeleton-space sole M_k. For physical world contact C:

```text
K = Y * inverse(H_k) * C
K_u = Y_u*inverse(H_k)*C
    + Y*inverse(H_k)*(C_u - H_k,u*inverse(H_k)*C)
```

K is in the kernel's numerical chart, not a fixed physical world frame. At
native endpoints it is exactly `Y*M_k`, satisfying the native endpoint identity.
After reconstruction, world contact is `H_k*inverse(Y)*K`. A world-fixed stance
generally gives nonconstant K. Its physical support classification remains
stance; calling it swing would be a false exemption.

Do **not** fit K into the legacy constant-stance/Hermite-segment input. It need
not be cubic or C1 when the seat's max switches branches. For the scalar
control `H_k=Translation_y(max(2u,-u))`, Y=identity and constant world C,
`K_y=-max(2u,-u)` has left derivative +1 and right derivative -2 at zero.
The legacy segment validator requires equal numerical derivatives at a join;
passing a smoothed K would cease to reconstruct the required constant world C.
This is a second exact interface conflict, even though the physical curve is C1.

The selected adapter therefore evaluates the **physical** contact trajectory C
and its two-sided derivative first, and computes K/K_u exactly at the requested
u. It reuses the existing kernel's validation, FK and `_Math._solve` routines
for those instantaneous full-affine targets; it does not call the legacy
segment interpolator on K or change that interpolator's contract. No second IK
algorithm, nearest-pose atlas or mutable iteration history is introduced.

The adapter's public pure sample boundary takes the same immutable rest,
authored native/reference locals and exact operation, plus a prepared copied
carrier/physical-trajectory packet. It validates packet/source/operation
identity, full physical segment partition/C0/C1/support classifications and
all carrier branch identities before deriving all four targets. Reuse the
existing rest, operation and pose validators without widening their domains;
reconstruct in the existing fixed hoof/chain order. Apply the original allowed
18 limb/hoof basis restriction, original local origins/stretch/shear, anatomical
limits, unchanged non-limb pass-through, attachment and full target residual
checks. At u=0/1, require the supplied exact native full locals and return those
locals only when the target is compatible; never repair the endpoint. Failure
returns empty locals atomically. The legacy `Map3DCavalryPivot.sample` API and
its tests remain unchanged.

Physical C1 stays a world-space profile constraint, including seat-branch cuts.
The adapter exposes both numerical one-sided jets there; its reconstructed
world derivatives must agree with C_u, not with each other before the pullback.
The profile/CERT must bound the actual finite reconstruction branch and whole
skin, not assume solving four frames proves that material contact derivatives
match. Unknown native arithmetic, a singular carrier, joint-limit failure or a
solver branch without a continuity bound remains FAIL/UNRESOLVED. No physical
error is waived because the coordinate identity is exact in real arithmetic.

The adapter's separate implementation must be registered before editing. This
technical caller amendment preserves committed XZ/yaw, ordinary seating, root
locals, permitted limb bases, native endpoints, attachment/stretch/shear rules,
R/E and all twelve gates. It does not authorize moving the actor, replacing
seating, changing terrain or weakening an existing solver check. A demonstrated
need to change shared solver code requires an additional literal scope proposal.

## 7. Exact prerequisite boundaries and no activation cycle

These are proposed literal ownership sets, not dispatch or permission to edit.
The sole dispatcher reconciles active claims and registers each once. A listed
future path need not exist yet. Original R2a/R2b and CERT ownership remains as
specified in royal feasibility section 5; no files are silently appended there.

**PHASE — deterministic copied reference sampling**, after this contract:

```text
scripts/map3d/map3d_royal_reference_phase.gd
scripts/map3d/map3d_royal_reference_phase.gd.uid
tests/map3d/test_royal_reference_phase.gd
tests/map3d/test_royal_reference_phase.gd.uid
```

Implement section 2 as a pure callable over copied admitted inputs, with exact
modular phase arithmetic, complete valid cursor range, the hand cases and
malformed/replay/ownership tests. No live driver, save field or phase accumulator.

**JETS — native value/derivative authority**, after R1 and this contract:

```text
scripts/map3d/map3d_royal_native_jets.gd
scripts/map3d/map3d_royal_native_jets.gd.uid
tests/map3d/test_royal_native_jets.gd
tests/map3d/test_royal_native_jets.gd.uid
```

Consume R1's detached source without changing it. Implement all actual imported
MARCH branches, native-time/phase units, FK/material jets and outward native
equivalence bounds. Actual imported keys, off-keys, STEP and seam branches must
be checked; finite difference agreement alone is insufficient. Preserve R1's
exact value path and original precision. No resource/source/importer edit.

**CARRIER — upright terrain derivative authority**, after this contract:

```text
scripts/map3d/map3d_royal_upright_carrier.gd
scripts/map3d/map3d_royal_upright_carrier.gd.uid
tests/map3d/test_royal_upright_carrier.gd
tests/map3d/test_royal_upright_carrier.gd.uid
```

Provide a native terrain extraction boundary plus pure copied evaluation of
section 3. Bind actual get_height semantics/data, sea/override/hole distinctions,
ordinary child transforms and all reachable seat branches. Test against the
unchanged `Map3DBattleGroups.place` rule at real native inputs and retain the
entire required placement domain as covered or adverse/unavailable cells. This
component computes the real carrier; it does not make fixed-START true, choose
physical uncertainty or change placement. Numerical controls alone are not
native domain evidence.

**BOUNDARY — copied caller/kinematic assembly**, after PHASE, JETS and CARRIER:

```text
scripts/map3d/map3d_royal_boundary_input.gd
scripts/map3d/map3d_royal_boundary_input.gd.uid
tests/map3d/test_royal_boundary_input.gd
tests/map3d/test_royal_boundary_input.gd.uid
```

Implement the detached caller packet/chain rule/rejection procedure in sections
4–5 from actual accepted BodyMotion operations, R1 native source and actual
upright terrain/scale inputs. A standalone test/fixture calls this same public
builder before any runtime activation. It receives the admitted current and
neighbor projections, not a Game/state query; it cannot manufacture a missing
next receipt. Require native component receipts and full-domain identity in
addition to synthetic arithmetic tests. This makes the data interface callable
without depending on the eventual renderer/consumer or on CERT success.

**PULLBACK — explicit representation adapter**, after JETS and CARRIER and this
contract, before R2 may consume a variable-height carrier. Implement section 6
with unchanged protected source/seat/root/scale/R/error limits, separate physical
support and numerical targets, world residual bounds, exact native endpoint,
seat-kink derivative and complete reconstruction restriction tests. Exact paths:

```text
scripts/map3d/map3d_royal_carrier_pullback.gd
scripts/map3d/map3d_royal_carrier_pullback.gd.uid
tests/map3d/test_royal_carrier_pullback.gd
tests/map3d/test_royal_carrier_pullback.gd.uid
```

The adapter consumes the accepted carrier and reuses the validators/FK/solver in
`scripts/map3d/map3d_cavalry_pivot.gd` /
`scripts/map3d/map3d_cavalry_pivot_math.gd`; those shared files are not proposed
edits. If actual interpolation/endpoint/limb constraints require a kernel change,
retain the exact failing input and register that necessary literal scope first.
Do not reinterpret this document as permission to alter the shared kernel or
to reuse a running owner's claim.

The endpoint budget/domain decision remains a separate prerequisite after the
actual phase/kinematic authority is accepted. It supplies justified E/eta and
physical-domain verdicts; it cannot obtain E from a failure maximum. R2a waits
for that decision and the accepted callable components above, including the
pullback and its actual-domain rejection/proof behavior. R2b then follows R2a;
original CERT follows the
accepted provider; POLICY and the separately owned consumer remain downstream.
No edge requires consumer activation to create an input or requires CERT PASS
to build its prerequisites. This document starts none of those steps.

## 8. Acceptance of this document

Document review checks the concrete law, units, full copied boundary, actual
placement derivation, hand arithmetic, pullback, rejection semantics and exact
conditional dependencies. Passing documentation/CI checks does not mean the
production prerequisite is satisfied: the components and actual-domain bounds
must be implemented and accepted separately. If the chosen reference
cadence fails physical or visual acceptance, retain that failure; no alternative
law, hold exception or phase subset is silently substituted.

Run whitespace/link/path checks, the repository harness/selector/runner checks,
shell/config/guide checks and a documentation-only selection on the final bytes.
No Godot execution, native capture, visual review or new contact certification
is asserted by this PR. Freeze source-input hashes and arithmetic-check output
in the worktree-local checkpoint for the unique Review. Required current-HEAD
CI must pass before that Review may merge this document.
