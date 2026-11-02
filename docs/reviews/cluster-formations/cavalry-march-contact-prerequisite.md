# Cavalry native MARCH contact prerequisite

Date: 2026-11-02. Step: `LOCO-CAVALRY-MARCH-CONTACT-CONTRACT`.
Baseline: `43d75e7e7aa3838411b458f364174ff919b591b3`.
Dispatcher: `01a17398-42c1-7583-8d3f-7b15e877586c`; implementation:
`01a19c48-40c8-7163-a3b3-37966b7112cc`; sole document Review is bound in
the PR/checkpoint. Astra/high is used for the native skin/phase compatibility
decision. This PR owns only this document. Its dependencies are accepted
CF04c-locomotion-contract, LOCO-TIME and LOCO-CLIP-CAVALRY.

## Decision and limit of the result

The proposed first implementation is **native-pose distance calibration**:
derive one monotone, periodic distance-to-phase map from all actual native
sole patches, keep native MARCH locals unchanged, and reconstruct pivot limbs
through the existing constrained provider with a full skinned-surface check.
Do not replace stride 5.9 with 2.4, fix a single hoof, normalize skin weights,
or add an unproved MARCH deformation. The method below is executable and has
an explicit reject result; this document does **not** assert it will pass.

The known witness rules out the retained 5.9 relation at the finite error
limits derived below. Even an optimally chosen scalar distance cannot remove
its lateral/vertical motion. There is no approved `contact_um` at this HEAD,
so neither an unconditional finite-tolerance impossibility theorem nor a PASS
can be inferred. The first numerical deliverable must return a verified
distance map with a residual bound, or a concrete incompatibility witness.
It cannot return an unqualified request for more research.

If the verified irreducible residual is physically unacceptable, the required
change is **rendered MARCH/transition endpoint geometry**, not frequency alone.
Changing the immutable asset or allowing corrected endpoints requires the
separate, conditional scope below. No endpoint exception is granted here.
Keep current R, ordinary scale, seat, complete support set, all phases and
the original twelve P4 gates in either branch.

## Frozen adverse input, independently checked arithmetic

Read-only observations from the original CERT owner are
`cluster-loco-cert-cavalry/game_design/.superpowers/loco-cert-cavalry/` under
`/Users/samuelzhang/.codex/worktrees/`:

| File | SHA256 |
| --- | --- |
| `blocked-contact-report.md` | `82e1ebb02dfce8784ddbf4ee2c0267fe06e202d5b323f800d22315ff0941e469` |
| `march-contact-witness.json` | `00ea96475bf9887176479b7867bb6e2ac5a903a915c0d55bff50743b3b903583` |

These are failed observations, not a dependency on unmerged CERT code.
No code from that worktree is imported or executed by this document step.
Accepted C is installed in [cavalry.glb](../../../assets/3D/units/cavalry/cavalry.glb),
SHA256 `bb82ae98905f336d9d36aadb09df54e97d0f5e52d0bb43152a998fdaadb803ed`.
Its retained source directory is the accepted clip worktree's
`assets/3D/units/cavalry/model_wip/loco_clip/`. Relevant immutable inputs:

| Relative source path | SHA256 |
| --- | --- |
| `cavalry_rig_work.blend` | `254de0fd87286f654bcf50917a8db004e9f7413a4c416903c4e00c10961fc700` |
| `body-response-c.blend` | `01b7340791391919ea84f766db2f8d727e95e8b8e8f1c183ac7512193befd38d` |
| `candidate-body-response-native216/godot-imported-native-v3.json` | `30d69f07b6d76d155b7af33f40e62b7a32c774fd413fa76fcdfeb05d67d82308` |
| `candidate-body-response-native216/godot-imported-geometry-v3.json` | `4960509ddaae535d5deabdf687976dbba5a93f64ecc8674541efbac8d45a19bd` |

The native capture identifies Godot 4.7.2, build
`ed1daf0bf001b61586d9930840f2f1394092c079`. It contains 53 bones,
21,175 vertices, 57,141 triangle indices, native Skin binds and animation
tracks. MARCH length is `0.5333333611488342` seconds. Source
[actions.py](../../../tools/units3d/cavalry_rig/actions.py) defines contact
onsets LH=0, RH=.26, LF=.27, RF=.45, with duty .31; these anatomical phase
labels must be checked against the native sole, not treated as contact proof.

For native surface 0 vertex 16496, reconstruct directly from the captured
native globals and inverse binds, keeping weights `.981994330883026` on
HindHoof.L and `.0179903861135244` on HindCannon.L. At phases .137 and .25,
both inside declared LH support, the skeleton-local difference is
`(-.0011397506840092053, .0017556620058260322, -.2747639795024976)` m.
At pack heading 90 degrees the installed half-turn and heading half-turn
cancel, so travel is +Z. Independent arithmetic in this document step used
the two accepted native captures, not the CERT probe implementation:

| Relation over phase difference .113 | Forward travel (model m) | XZ displacement (model m) |
| --- | ---: | ---: |
| Retained 5.9 | .6667 | .3919376776925641 |
| Nominal source 2.4 | .2712 | .0037417885450576 |
| Best scalar for this vertex alone | .2747639795024976 | .0011397506840092 |

The last row still has XYZ displacement `.0020931747897394` m and is **not**
a whole-hoof/whole-cycle solution. Its equivalent local secant stride is
`2.431539641615024`, also not an approved constant stride. Under retained 5.9,
the original 79-vertex low-sole patch ranges from .3900470722 to .3959411534 m
XZ slip. At ordinary scale `k=20.497308702059588`, the single-vertex retained
slip is 8.0336675716 world m. A root Y adjustment cannot remove it.

### Finite-error obstruction, including arbitrary endpoints

Let `n_v(p)` be the **native skinned vertex**, `e` the actual translation
direction in the fixed model-ground frame, and `d` forward travel between
phases a,b. With fixed heading, its horizontal endpoint displacement is

`D_v(d) = ||P_XZ (n_v(b) - n_v(a) + d e)||`.

If contact error E means maximum displacement from the actual planted point
at entry, these two endpoints require `E >= D_v(d)`. If it instead means
distance to a freely chosen fixed anchor, triangle inequality requires
`E >= D_v(d)/2`; do not conflate those metrics. The future report records both,
and neither redefines the inherited certificate's metric. Thus retained 5.9
requires at least 391937.6777 model micrometres of entry drift, or 195968.8389
micrometres of free-anchor radius. These are lower bounds, not policy proposals.

For arbitrary nonnegative scalar d in this witness, minimizing the quadratic
gives `d=.2747639795024976` and an XZ floor 1139.7507 micrometres (free-anchor
floor 569.8753). No scalar phase law removes that floor. Native Y varies too;
fixed seat cannot erase the 1755.6620 micrometre difference. These are finite
necessary conditions, not a claim that E must be zero or is already known.

Choose a MARCH interval whose entry/exit are exactly a=.137,b=.25 and which
retains this native support. Any interior limb correction that is zero at
both endpoints leaves this endpoint inequality unchanged. Returning to native
pose via a short blend, making the blend arbitrarily fast, or relabelling that
support as swing does not repair the condition. This distinguishes immutable
asset bytes from immutable rendered endpoints. A provider may depend on the
whole operation; this argument still applies to its two fixed endpoints.

Changing d is a real alternative and is evaluated below. At a fixed committed
d, entry phase, exit phase and full-turn count cannot all be independent:
`d = F(z_exit) - F(z_entry)` must hold. An independently requested incompatible
MARCH tuple rejects; it is not retimed by altering the engine path. This does
not restrict arbitrary **pivot** entry/exit phases: they remain independent
inputs at zero body translation and require their own complete reconstruction.

## Concrete distance-map construction

Use model metres, native float values and the installed scene transforms.
Let unwrapped phase z be real, `p=z-floor(z)`, and
`F(z)=floor(z)*S+f(p)`, with `f(0)=0`, `f(1)=S>0`. f is continuous piecewise
linear with strictly positive slopes. Its knots include every imported track
key phase, all four support onsets/liftoffs, and the seam; refine dyadically
where the continuous bound demands it. Store rational knot/value coefficients
and outward error intervals. The imported animation remains native at p.

For every anatomically identified sole patch H, support interval I and vertex
v, constrain the entire **translated native surface**
`x_v(z)=n_v(frac(z)) + e F(z)`, relative to its touchdown anchor. Include
intervals crossing the seam using unwrapped phases. Compute the maximum XZ
entry drift, pairwise diameter, Y penetration/hover relative to the actual
unchanged seat/ground, triangle normals and patch shape/separation. All four
hooves and their full contact triangles participate; the 79 points remain a
regression patch, never the new definition of the entire support surface.

The finite fitting problem has unknown knot values and S. At each constraint
pair a,b the expression `f(b)-f(a)+dot(e,delta_native)` is affine in them;
the transverse component is fixed. For a trial horizontal diameter bound E,
the allowed scalar difference is the closed interval
`[-dot(e,delta_native)-sqrt(E^2-lateral^2),
  -dot(e,delta_native)+sqrt(E^2-lateral^2)]` when `E>=abs(lateral)`;
otherwise it is infeasible. Entry-drift constraints use a=touchdown.
Intersect constraints from every vertex/support pair plus monotonic knot
order. Solve rational linear feasibility: conservative inner square-root
intervals prove candidate satisfaction, while only an infeasible **outer**
relaxation can prove impossibility. Failure of an inner approximation proves
nothing. A floating optimizer may propose coefficients but is never the proof.
A Farkas certificate for the outer relaxation only rules out that particular
knot family/E; a concrete endpoint floor such as the above rules out **all**
scalar maps for that E. Do not promote failure of a fit to global impossibility.

Minimize the attained contact bound, then squared departure from native
planted-foot forward motion; resolve remaining equal fits lexicographically
by knot values. No coefficient is taken directly from 2.4 or 5.9. During
all-airborne intervals contact alone leaves travel underdetermined: choose
the monotone minimum squared change of slope with the same lexicographic tie
rule. These are offline calibration choices, not new engine movement rules.
There is no need to prove a global optimum to accept a candidate: a verified
physical upper bound is sufficient. Failure to prove either side is UNKNOWN,
with the unresolved parameter box recorded, never a certificate or permission
to narrow support. A bounded build stops on its declared work limit.

After each candidate fit, prove continuous bounds as below. Add violating
interior witnesses/refine knots and repeat within that work limit. Emit exact
coefficients, achieved lower/upper bounds and unclosed boxes. Do **not** set
`contact_um=ceil(achieved_error)` to manufacture success. Numerical residual,
import discrepancy and physical tolerance are separate reported quantities.
The later sole certification pair must establish acceptable physical error,
normal/ground behavior and real-window results before any policy row exists.

Hand-computed sampler fixtures use a synthetic f with knots (0,0),(.5,1),
(1,3), never a production gait. From z0=.25, distance 1.5 gives z=.75;
distance 3 gives z=1.25. From z0=.75, distance 1 gives exactly z=1, phase 0.
At p=.5 the next slope is 4, so the inverse derivative is .25. A requested
.25 -> .75 native pair with distance .5 rejects because it requires 1.5.
For a finite incompatibility test, two support vertices with longitudinal
differences -.2 and -.3 and zero lateral difference need d in [.18,.22]
and [.28,.32] respectively for E=.02; their empty intersection rejects.
These fixtures test finite E, inversion and simultaneous support, not just D=0.

The universal native-only test is strong: for any phase z0 and nonnegative
committed model distance ell, `z=F^-1(F(z0)+ell)` exists uniquely. Every native
phase is reachable; repeated cycles, tiny moves and mid-stance starts are
covered. Calibration is one per installed arm input, not chosen per body,
camera, speed, receipt, or whichever foot gives the smallest error.

## Strict presentation seams and data flow

These are proposed new APIs, not names available at this HEAD. Their raw
Variant boundaries reject nonfinite/malformed values, unexpected keys,
nonpositive slopes, bad hashes and out-of-domain values atomically. Failure
returns `{ok:false, diagnostics, ...empty outputs}` and never publishes a
partial pose. The pure seams own no clock, Game/state lookup, filesystem I/O,
AnimationPlayer, random stream or mutation of passed inputs.

```text
Map3DCavalryMarchPhase.sample(atlas, phase_origin, distance_model_m)
  -> {ok, unwrapped_phase, native_phase, derivative, diagnostics}
Map3DCavalryContact.sample(native_input, operation, contact_plan)
  -> {ok, locals, surface_bounds, diagnostics}
```

`atlas` has exactly `{version:1, input_sha256:String, clip_seconds:float,
knots:Array}`. Each knot
has exactly `{phase_num:int, phase_den:int, distance_num:int, distance_den:int}`;
denominators are positive, rationals reduced, all integers exactly representable
in JSON. The first knot is (0,0), the last is (1,S), with strict phase and
distance order. The offline report's `metric_bounds` names separate outward intervals for
`entry_drift_m, diameter_m, penetration_m, hover_m, normal_rad, envelope_m`;
these are measured/certified metadata, never accepted policy values.
`phase_origin` is exactly `{cycle:int, phase:float}`, with nonnegative cycle
and phase in [0,1); keep loop count separate to avoid losing phase precision
in large unwrapped floating values. The returned `unwrapped_phase` uses that
same pair. This is the preserved presentation origin at move start; distance
is cumulative from that origin, computed from the admitted receipt's actual
fractional XZ path divided by the unchanged ordinary k. Never integrate
per-frame delta. Inversion uses a binary search in the positive-slope knot
table and one affine solve, with explicit seam ownership and bounded rounding.
Remove whole strides before the residual solve; check integer cycle overflow
and the declared maximum admitted travel. Test numerical error at that maximum,
not just one loop. Unclosed rounding bounds reject rather than wrap silently.
Return `derivative=1/f'(p)` on the selected half-open segment; at its right
boundary choose the next segment. Exact final pose is sampled explicitly.

The already accepted [BodyMotion sampler](../../../scripts/engine/body_motion.gd)
is the sole XZ/yaw/time authority. Flow is admitted copied v2 ops and explicit
receipt/time_q -> existing pure operation sample -> cumulative travelled
distance -> phase sampler -> **native MARCH track evaluation** -> contact
verifier/output locals. Y uses the ordinary scene/terrain seat. No gait clamp,
easing, added waiting, different path length or root correction may change
this candidate's phase-distance relation. Existing ordinary/v1 `gait_rate`
and their call sites remain unchanged; only a later v2 consumer opts in.
Quantized yaw need not be exactly tangent: use the actual displacement vector
and yaw in verification, including their accepted 0.5-microdegree deviation.

For a pivot, the phase sampler does not invent travel. `operation` supplies
the unchanged signed turn, duration, normalized op phase and independently
arbitrary entry/exit native phases. `native_input` contains the exact full
affine locals at current/entry/exit, actual native geometry/Skin, immutable
rest/limits and bind digest. `contact_plan` contains measured sole frames,
all patch vertex/triangle ids, native support state at each boundary and the
complete stance/swing partition in the operation's fixed start-ground frame.
It does not infer support by seeing which vertices happened to pass a test.
The existing rest/authored_pose/operation/contacts dictionaries retain exactly
the schemas validated by Map3DCavalryPivot; do not translate them into reduced
TRS endpoints. `native_input` has exactly `{input_sha256, rest, authored_pose,
surface}`; surface has `{vertices, triangles, bone_names, joints, weights,
inverse_binds, mesh_to_skeleton}`. `contact_plan` has exactly
`{contacts, patches, boundary_support, material_supports, frame_context,
provenance}`. Contacts retain the existing `offset` and `segments` per hoof;
`patches` maps hoof -> native vertex/triangle ids, and `boundary_support`
gives entry/exit phase plus source support/airborne labels for all four hooves.
Arrays must agree in length, named binds and index domain with the hashed
capture. The adapter passes only the existing four arguments to the provider,
then uses these additional arrays to verify its actual skin.

### Material anchors and stateless boundary verification

`material_supports` maps each hoof to its ordered support records intersecting
this operation. A record has exactly `{support_id, start, end, birth,
anchors_world}`. start/end are normalized phases of that intersection; the
source support episode, not each operation, determines the identity. Carry-in
support starts at 0 here but retains its earlier **birth**. Shared boundaries
use the next interval, except the exact final sample. A genuine lift ends the
episode; the next actual touchdown creates a new id. Neither a receipt/owner
change nor a render refresh creates a touchdown.

`birth` has exactly `{unit, slot, receipt, op_index, event_index, op_phase,
sample_kind, native_phases, world_frame_id, pose_to_world, locals,
sample_sha256}`. sample_kind is `march`, `pivot` or `hold`; native_phases has
exactly `{entry,exit}` (both equal the sampled phase for a MARCH birth;
otherwise the source packet's unchanged native endpoint phases). It
identifies the original touchdown, including one before this operation, and
retains the complete evaluated named bone locals at that event and the full
pose-space-to-world Transform3D. `sample_sha256` binds the actual event's
native evaluation/provider input packet, including mapping and phase inputs;
the capture/certification artifact retains that packet for independent replay.
For pivot births, these are the **solved** locals, not the authored pre-solve
pose. At native MARCH births, they are the exact evaluated native locals.
No current-entry pose is substituted for an earlier birth pose.

`anchors_world` is an ordered array of exactly `{vertex:int, position:Vector3}`
for **every** native vertex in that hoof's patch. With the actual native
inverse binds, mesh conversion and unnormalized weights, compute
`A_v^W = birth.pose_to_world * LBS_v(birth.locals)` once from that birth.
These are actual material positions, not rest points transformed by a rigid
hoof frame or points projected onto a fitted ground plane. The validator
recomputes them from the retained birth pose and checks their input digest;
only a proved floating representation bound is allowed in that comparison.
Missing/duplicate vertices, changed birth data, or a forged support id reject.
`support_id` is the canonical hash of `(unit,slot,hoof,receipt,op_index,
event_index,sample_sha256)` at birth; the complete immutable record is carried
across later operation/receipt boundaries until liftoff.

`frame_context` has exactly `{world_frame_id, op_to_world, pose_to_world,
ground_vertices_world, ground_triangles, ground_sha256, seat_rule_sha256}`.
The first transform G maps the operation's fixed start-ground model-metre
frame into the stable world frame, including unchanged ordinary scale k;
the second maps the **current evaluated pose space** into that same world,
including installed axis conversion, actual engine XZ/yaw and unchanged seat.
Thus current material position is `X_v^W = pose_to_world * LBS_v(locals)`.
Use `G.inverse()*A_v^W` when the provider-frame verifier needs an anchor.
Between operations i,j the conversion is `A_v^Gj = G_j.inverse()*G_i*A_v^Gi`;
never copy numerical local coordinates as though their frames were identical.
World anchors and birth world-frame id remain unchanged. A mismatched world
frame rejects; it is not a new material anchor.

Ground arrays contain the complete immutable native ground triangles covering
the contact/verification domain, in that stable world frame. Their digest binds
the actual terrain source, interpolation/tessellation and capture used by the
certificate. The continuous verifier must enclose any rendered-surface residual;
an arbitrary planar substitute or unexplained geometry mismatch rejects.
Evaluate penetration/hover and ground normals against these triangles and
the actual unchanged seat transform, separately from drift against A_v^W.
An anchor already above/below ground at touchdown does not zero its hover or
penetration metric. No skeletal-Y-equals-ground assumption is permitted.

`provenance` has exactly `{input_sha256, atlas_sha256, mapping_sha256,
descriptor_sha256}`. The descriptor digest binds the admitted identity,
receipt/operation sequence, native phase origin, contact event schedule,
frame_context ground/seat inputs and **carried-in support records**; the
static input digest agrees with native_input. Retain canonical payloads in
the evidence, not only hashes. The adapter rejects mismatches atomically.
Neither anchors nor these transient descriptors become saved simulation state.

Construction is a pure operation over that complete admitted descriptor,
immutable native evaluation data and explicit carried-in records. Enumerate
touchdown/liftoff events from the fixed contact schedule, then evaluate the
same MARCH phase/native sampler or existing four-argument pivot provider at
each exact touchdown, regardless of the requested display time. Compute all
new birth records/anchors there. The provider candidate solve does not consume
material anchors, so event evaluation does not recursively call the surface
verifier. Reject any event with a failed solve or invalid ground context.
For support already active at descriptor entry, copy its original record from
the preceding immutable descriptor; do not sample entry as a new touchdown.
The pure sample call then selects records by support interval and verifies the
current skin against those records without changing them.

Sequential playback, direct seeks and same-receipt rebind receive the same
self-contained contact plan, including carried-in birth poses/anchors and all
interior event records. They require neither prior frame execution nor a
mutable last-foot-position cache, historical state query or hidden reads.
Rebuilding a plan requires the explicit immutable entry records and descriptor
inputs; missing context rejects with `anchor_context_missing`, not a freshly
anchored entry pose. This is malformed-input handling, not a reduced phase
domain or a bypass for a valid receipt. The consumer must preserve this
transient payload across refresh/identity transfer and pass it on rebind.
A fresh load without the inherited in-slice presentation envelope retains the
existing committed-endpoint display rule; it does not certify/replay a missing
history. The future boundary tests must prove that every valid replay supplies
the complete context rather than relying on that failure path.

Hand-computed mixed-weight fixture (model k=1, identity binds, flat Y=0 ground;
synthetic, not a tolerance): a rest vertex `(0,0,0)` has hoof weight .75 and
cannon weight .25. At touchdown both matrices are identity, so A^W=(0,0,0).
Later the hoof matrix is unchanged but the cannon translates +.04 m in X;
LBS gives X^W=(.01,0,0), hence retained-anchor drift .01 m. Resetting at this
entry would report zero. An alternative history with cannon +.04 already at
touchdown has A^W=(.01,0,0) and zero drift at the **same current pose and hoof
frame**, demonstrating why the rigid frame cannot determine the anchor.
Now set the next operation frame G_j to translation +.10 m in X. The retained
anchor is -.10 in that frame and the current material point is -.09: the
drift remains .01 m. Sequential conversion and a direct seek/rebind using the
birth record must both return that value; reset would again return zero.
Test both histories, the cross-frame values and identical sequential/random
access results, plus rejection when the original birth record is omitted.

The adapter calls [Map3DCavalryPivot.sample](../../../scripts/map3d/map3d_cavalry_pivot.gd)
and uses its full affine FK, 18 permitted limb/hoof rotations, anatomical
connectivity and rotation/bend limits. Local origins/stretch/shear and every
non-limb local remain as supplied. Its zero-correction native endpoints remain
mandatory. A successful rigid sole-frame solve is only a **candidate**: skin
EVERY patch vertex with its real mixed weights and verify contact/surface
bounds before output. Reject a frame that passes the bone frame but fails
the skin. Runtime checks do not substitute for the offline universal bound.

Use [pivot.py parameter_inputs](../../../tools/units3d/cavalry_rig/pivot.py)
as the existing source mapping, not the fixed 4-second bake as a universal
answer. Its current 3/4-cycle mapping, airborne entry pieces and arbitrary
phase endpoints require validation: a stance label cannot excuse hover,
and a swing label cannot hide a planted native boundary. The contact planner
must retain inherited support until a real lift, land the required available
support before its release, and meet the actual exit support state. Duration
scales derivatives by 1/T; near-zero turns with short durations cannot be
certified by showing only a time-compressed 180-degree bake. If the mapping
fails, return the exact turn/phase/duration/skin witness; do not silently edit
that mapping, source or source-defined native support within the new adapter.

MARCH -> pivot -> MARCH and move -> hold preserve both exact endpoint locals
and the corresponding sole anchors across the boundary. Resetting anchors
each op conceals drift. Reconstruct the boundary from the preceding admitted
presentation descriptor; random access/rebind must produce the same result.
An active hold must acquire supported rest inside its committed time; freezing
an all-airborne native endpoint is not a successful hold. Validate the source
mapping's support acquisition and finite-duration limit, or return that exact
hold incompatibility. A paused frame is different from an advancing hold.
On load without the explicit in-slice envelope, keep the inherited committed
endpoint behavior; do not fabricate a rewind or a saved animation authority.
Observed hostiles get current pose only: these seams do not authorize future
ops, future phases or hidden stance reads. The v2 consumer retains the
original visibility/data-flow acceptance, including forbidden-read counters.

## Native provenance and continuous verification

Raw GLB/native agreement is a gate, not an allowance. The retained report
records full-mesh disagreement up to `.005474065954881313` model m, despite
the independent raw witness `.39193229260145496` m agreeing closely with
the native witness. Native weights differ by up to `1.5288591384887695e-5`
and sum to `.9999541863799097 .. 1.000000029802322`. Keep those exact weights.
Native track reconstruction versus captured positions was at most
`7.308338836331529e-7` m in the two poses; that is a measured sample residual,
not a continuous roundoff bound. Do not substitute one of these numbers for E.

The capture verifier must map raw triangle corners to native ones using
geometry, skin bone names and seam topology, retaining duplicate/seam
vertices and proving triangle coverage/orientation. A nearest-position match
alone is inadequate. Bind node/mesh/skeleton transforms, source alias names,
inverse binds, dropped/default track components, interpolation mode,
quaternion sign/short-arc behavior, loop seam and import compression settings.
Decompose raw/native disagreement into actual import operations and residual;
reproduce that decomposition against native capture across every track span.
Unexplained residual remains red. The native path is the rendering authority,
but raw provenance still has to account for how it became that path.

For MARCH, split at imported keys, f knots, touchdown/liftoff and seam. Use
outward-rounded interval evaluation of native TRS interpolation, hierarchical
affine multiplication and unnormalized LBS to enclose each triangle over each
span. For pivot, include the Cartesian domain of both native endpoint phases,
op phase, signed microdegree turn (including +180 tie), heading, legal
duration and terrain/seat inputs. Split around solver branch boundaries and
provide interval existence/residual bounds for the constrained solution;
finite successful iterations at sampled points do not prove such existence.
If a branch cannot be bounded, retain its box as UNKNOWN. Nonlinear skin
normals and degenerate/flipped triangles must be checked, not only centers.

Bound normalized-phase geometry separately from real-time velocity; multiply
derivative bounds by the actual admitted 1/T, never assume a 4-second policy.
Use finite integer operation limits from LOCO-TIME, record which bounds make
the parameter domain compact, and handle mathematical seams/one-sided limits.
For terrain include all slopes/heights the eventual consumer admits and the
actual root-seat rule; a flat-ground witness suffices to reject a universal
claim, while flat-ground success cannot certify all terrain.

For every output, enclose full horse/rider/equipment deformed geometry and
all yaw intermediates at ordinary k within unchanged R. Include equipment
according to the existing body/weapon distinction. Contact PASS without this
envelope is not usable. Never shrink R/model, fit the ground plane, alter seat
or increase deployment spacing to make the test pass.

Independent dense/adversarial checks must include .137/.25, all stance edges
from both sides, mixed-weight sole vertices, overlaps of multiple hoof
supports, phase wrap, very short moves, long repeated moves, arbitrary
entry/exit phase pairs, both signs, near-zero/180/wrap turns, and adjacent
op/receipt boundaries. Compare raw-native-track/native capture, full solver
skin and actual rendered mesh. Report the largest witnesses as well as proved
upper bounds; a loose upper bound by itself is not a counterexample.

The retained 5.9 case must remain a **negative regression** with its original
inputs. Tests must also reject a fake one-vertex patch, renormalized weights,
2.4-as-proof, bone-frame-only success, anchor reset and incompatible independent
MARCH endpoint tuple. New-map results are a separate run with a different
mapping digest, never an overwritten PASS for the old witness.

## Exact proposed subsequent steps and gates

Only the original dispatcher registers these, once, after reconciling live
claims. This is a proposed DAG, not dispatch or authorization to edit. Each
row is one independently checked PR and a fixed implementation/Review pair.
New `.gd.uid` files are explicitly owned with their scripts. No step acquires
the original CERT's four product paths.

| Step | Dependencies and literal owned paths | Bounded result |
| --- | --- | --- |
| `CAV-CONTACT-NATIVE` | This accepted document. `tools/units3d/cavalry_march_capture.gd`; `tools/units3d/cavalry_march_capture.gd.uid`; `tools/units3d/check_cavalry_march_capture.py`; `tools/units3d/test_cavalry_march_capture.py`; `docs/reviews/cluster-formations/evidence/locomotion/cavalry/march-native-contact.json` | Read-only current-scene capture, complete raw/native topology and interpolation accounting, frozen witness reproduction and full anatomical patch definition. Retain large immutable capture payloads in model_wip with hashes; the tracked manifest must identify reproducible generation and all required inputs. No asset/import edits. |
| `CAV-CONTACT-PHASE` | Accepted native capture. `tools/units3d/cavalry_march_phase.py`; `tools/units3d/test_cavalry_march_phase.py`; `docs/reviews/cluster-formations/evidence/locomotion/cavalry/march-phase.json` | Implement the stated rational fit/continuous verifier. Deliver a monotone native map plus verified residual/envelope bounds, or exact infeasible witnesses/unclosed boxes. No policy acceptance inferred from small samples. |
| `CAV-CONTACT-PHASE-RUNTIME` | Accepted verified candidate phase-map result. `scripts/map3d/map3d_cavalry_march_phase.gd`; `scripts/map3d/map3d_cavalry_march_phase.gd.uid`; `tests/map3d/test_cavalry_march_phase.gd`; `tests/map3d/test_cavalry_march_phase.gd.uid` | Pure injected-atlas sampler/inverse, endpoint/seam/large-distance/error tests and frame-partition invariance. No production consumer or table edit. |
| `CAV-CONTACT-SURFACE` | Accepted native capture and phase-map result; existing accepted cavalry pivot provider. `scripts/map3d/map3d_cavalry_contact.gd`; `scripts/map3d/map3d_cavalry_contact.gd.uid`; `tests/map3d/test_cavalry_contact.gd`; `tests/map3d/test_cavalry_contact.gd.uid`; `tools/units3d/check_cavalry_contact_domain.py`; `docs/reviews/cluster-formations/evidence/locomotion/cavalry/march-pivot-boundary.json` | The injected-input adapter and universal boundary/surface checks described above, including actual mixed skins and arbitrary phases. Reuse existing pivot provider; return incompatible cases. It cannot reauthor a failed mapping, claim full certification, or modify native endpoints. |

`document -> native -> phase -> {phase-runtime, surface}` is acyclic. The last
two have disjoint files and may run independently only after their required
acceptance. A verified candidate map is permission to test the isolated seams,
not physical contact acceptance; that still belongs to the later original
CERT pair with native windows. This avoids making the test adapter depend on
the final certificate that needs it. A failed/UNKNOWN prerequisite with no
verified candidate is not an accepted implementation
edge; retain its diagnostic result without starting its dependent success path.

Once these are accepted, the **existing original CERT pair**, not a new
reviewer, may resume only if its immutable registered acceptance permits this
explicit movement/phase provider. Dispatcher must verify that boundary first;
no append-files trick may change acceptance. The original failed 5.9 evidence,
all arbitrary native endpoints, current R/scale/seat and native-window/FPS
gates remain. If registered acceptance requires the old relation, report the
conflict; this document neither retires that step nor creates a replacement.

Only after full certification may the existing serial cavalry policy step
install its contact/turn rows. A separate `CAV-CONTACT-TABLE` may then own
`data/screens/map3d/cavalry_march_phase.csv`, `data/tables.csv`,
`scripts/engine/data_repository.gd`, `tests/engine/test_data_repository.gd`,
`tests/map3d/test_cavalry_march_phase.gd` and
`scripts/map3d/guide/cavalry_contact.md`: install the exact certified numeric
knots and input digest through the ordinary table loader, without runtime
fitting. CSV columns are exactly `knot,phase_num,phase_den,distance_num,
distance_den,input_sha256,clip_seconds`, ascending knot ordinals from zero;
metadata must agree across rows. Register `screens/map3d,cavalry_march_phase`
in the index and add an explicit repository member/loader using the existing
`_load_if_present` pattern: the index by itself does not load a new table.
The loader validates canonical integer text before constructing the atlas;
empty/missing data means no candidate support, never a corrupt legacy save.
The consumer passes copied data into the pure seam. Bounds stay in the
certificate, not an editable runtime contact allowance. Use SuiteData for
loader tests; no new per-test load_all calls. This step serializes with
phase-runtime on its test and any active DataRepository owner. The new guide is indexed
by the later consumer's already owned `scripts/map3d/CLAUDE.md`.
The existing separately registered v2 consumer then owns the actual callers:
`scripts/map3d/map3d_battle_groups.gd`, `scripts/map3d/map3d_layer_units.gd`,
`scripts/map3d/map3d_unit_rig.gd`, `scripts/map3d/CLAUDE.md`,
`tests/map3d/test_body_paths.gd`, `tests/map3d/test_body_paths.gd.uid`,
`tools/map3d/body_paths_fixture.gd`, `tools/map3d/body_paths_fixture.gd.uid`.
It additionally depends on the table and both adapters, all original arm
certificates/policies and all original ownership gates. No engine save/schema,
scene, source animation, footprint, asset install or activation edit is hidden
inside these scopes. Any extra necessary file requires prior registration.

### Necessary-change branch if immutable endpoints fail

Do not launch this branch from a mere failed fit or loose bound. It needs a
verified finite lower bound above independently acceptable physical error,
or a native surface/normal/reachability witness. If MARCH native geometry is
the cause, changing travel alone is inadequate: a proposed
`CAV-CONTACT-SOURCE-CONTRACT` owns only
`docs/reviews/cluster-formations/cavalry-contact-source-amendment.md` and must
authorize the exact alternative before any source PR starts. Its necessary
choice is either (a) reauthor the relevant MARCH skin/limb trajectory while
preserving named hierarchy and other clips, or (b) retain asset bytes but
allow corrected rendered MARCH endpoints and stitch the same corrections
through pivots. Both change the old native-endpoint requirement. Neither is
authorized by this document or by an enlarged E.

For (a), the proposed subsequent literal scope is
`tools/units3d/cavalry_rig/march_contact.py`,
`tools/units3d/cavalry_rig/install.py`,
`assets/3D/units/cavalry/cavalry.glb`,
`assets/3D/units/cavalry/cavalry.glb.import`; original source is retained and
work occurs on a copied blend. For (b), the amendment must register the exact
new correction provider and its corrected-endpoint contract before touching
existing `map3d_cavalry_pivot.gd`/`map3d_cavalry_pivot_math.gd` or their tests;
this document does not select or dispatch that larger redesign. If only the
pivot source mapping fails, propose a separate mapping PR owning
`tools/units3d/cavalry_rig/pivot.py` and
`tools/units3d/cavalry_rig/test_pivot_contacts.py`, with the failure's exact
schedule correction specified first. Every changed source/input invalidates
its capture/map/surface/certificate evidence. No historic pair is reopened,
no owner replaced, and no source change is smuggled into CERT.

## Acceptance of this document versus eventual acceptance

This document is reviewable on source bindings, the independent hand
calculation, finite-error reasoning, executable interfaces, conditional gates
and literal scopes. It does not certify the calibration's physical residual,
pivot mapping, full parameter domain, ordinary terrain, body envelope or live
performance. All original P4 acceptance and policy/consumer gates survive.

Future native acceptance uses real windows under the shared Godot lock and
visual-review with the same two owners: baseline plus at least two meaningful
variants, complete near/far runs, native window and 3x sole crops, pause/1x/4x,
different FPS partitions, offscreen/rebind, arbitrary MARCH-to-pivot-to-MARCH
phases, full/reduced strengths and mixed/opposing/L-detour paths. Check all
hooves, rider response, contact/hover/penetration, boundary pops and silhouette
through the entire clip. Compare identical advancing receipt clocks and
mean/median/p95 with ordinary baseline; fixed-share playback is insufficient.
Evidence binds input/atlas/scene/engine hashes, receipt, commands and pixels.
No headless 3D, finite sample count, unchanged source action or numeric circle
substitutes for these checks. This doc step launches no Godot or Blender.

Local document checks are the harness Python hook/selector/runner/timeout
tests, shell/config/guide checks, doc-only category selection, input-hash and
source-link checks, recomputation above and `git diff --check`. Required
current-HEAD CI and this document's sole independent Review precede merge.
No source code, tests, CSV, scene, art, policy, consumer or registry is edited
by this PR, and no child session or successor is started by its implementation.
