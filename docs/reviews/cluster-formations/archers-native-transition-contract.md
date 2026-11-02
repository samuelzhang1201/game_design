# Archer native transition conditions and bounded amendment proposal

Date: 2026-11-02. Step: `LOCO-ARCHERS-TRANSITION-CONDITIONS`.
Implementation: `01a19ccb-e7ea-7e61-b378-b21a6e389f35`; sole Review:
`01a19ccc-327c-7801-81c6-42477c0a65da`; dispatcher:
`01a17398-42c1-7583-8d3f-7b15e877586c`.
Base: `2407bf6df47958def45f10f97ff7a69c76d1d447`.
Scope is this document alone. It changes no protected requirement or implementation.

**Disposition: the current conjunction is excluded, not ready for B.** Exact
native MARCH endpoints cannot coexist with the existing rest-length/split rule
through every endpoint and its neighbourhood. Section 2 proves that obstruction
and section 3 proposes one narrowly specified change for explicit disposition.
Section 4 separates physical quantities and identifies exactly why the retained
evidence cannot yet authorize contact allowances or a complete support surface.
Section 5 specifies a testable continuous-input/proof protocol. None of these
sections is a certificate. D1 has an exclusion proof and an unapproved proposal;
D2 has no justified admissible contact budget. Therefore this document must not
be accepted as a completed prerequisite, merged as B-ready, or used to start B/C.
A review of the proof/proposal does not supply the missing physical authority.

## 1. Frozen inputs and preservation boundary

Accepted dependencies: #202, #203, #205, #216, #220 and #233. Consume #233's
accepted native input; do not re-review A or wake its ended responsible pair.
Original CERT #231 remains failed, at
`74ed2893ef4af4f2543c8a2e3299074a5407e396`, and is an evidence input, not a merge
dependency. Its four files, sixteen witnesses and immutable acceptance survive.

The originating proposal is `.superpowers/loco-cert-archers/prerequisite-proposal.md`
in `/Users/samuelzhang/.codex/worktrees/cluster-loco-cert-archers/game_design`,
SHA256 `1fdca7f5355db8ebf0078041dc1c125567ca1897b010716f2cccd4ddd37537e1`.
Other retained evidence in that directory:

| Input | SHA256 |
|---|---|
| `accepted-A-inputs.json` | `013a8ed79f2e640b7275cbebabd79453663e9e21dcb63ba41b56a7d1edb42bba` |
| `accepted-A-segment-conditions.json` | `ffb802a8445006db32145b4f0ef480b1183441dcfd25917c54303a7c0a594104` |
| original CERT `native.json` | `e70eb095008dbd3179119d652cb874884b4e0cbc2a1fb3af7ad4a865114184bc` |

A's separate `.superpowers/archers-native-boundary/native.json` in
`/Users/samuelzhang/.codex/worktrees/cluster-archers-native-boundary/game_design`
has SHA256 `e9a12f4ebb27814d7d3977bad037cfaae4335452d46182ff9b29ffe9433b1e71`.
Its eight MARCH phases and four pivot endpoints are finite input observations.
They do not constitute a continuous provider. The accepted input manifest binds
A's original Review decomposition; this document does not reproduce that review.

The following paths are relative to the original CERT checkout, read-only here:

| Frozen file | SHA256 |
|---|---|
| `docs/reviews/cluster-formations/evidence/locomotion/archers/source.json` | `c480a4145ca0d43f31e7a296249aaa36692f2452245bf1e41c5b9a8fc57e43da` |
| `docs/reviews/cluster-formations/evidence/locomotion/archers/pivot-contacts.json` | `106e961629752978eadddb7a9b384c59d249b27181d98ed2e80ab14bad8cf533` |
| `docs/reviews/cluster-formations/evidence/locomotion/archers/pivot-envelope.json` | `f535f33773b5b3eb863a5fcab2a4a7e0bc44edea726aa2fbaf56f77d05105d91` |
| `tools/units3d/certify_archers_locomotion.py` | `e403d7226ac050dcabf4d3758f9583be2305a80fd7ecb13e9ed8edd611bb97ac` |

The original source payload is
`af83f6e16a873d1fe1a864293fda669ec0bb11a2717c40e2d126d8dabfd1dc9a`.
The installed body is
`02356e6fe312a3da89a94f265ee8a62b8067dd9e1915f717accae7f40de90243`;
the original six-clip source is
`7484f4977058fed353c12d5507837257992e97bc52283487d61c7886e6481b9b`.
All 35 model/import/scene/gear/importer resource fingerprints remain bound to the
retained source manifest. A's added diagnostic software is a different package;
do not replace the original manifest with A's hash or call them identical packages.
No source, weight, bind, rest, material, scene or installed curve is altered here.

## 2. D1: exact obstruction, including the one-sided limit

Use complete parent-relative local affine transforms, not Skeleton pose deltas.
Let `N_b(phi)` be the actual native MARCH local of bone b, `G_b(phi)` its native
FK global, and `R_b` the native rest global. Distances below are **native skeleton
metres**, not model/world/simulation metres. For anatomical span a->b and split c:

```text
L0 = |R_b.origin - R_a.origin|
f  = dot(R_c.origin-R_a.origin, R_b.origin-R_a.origin) / L0^2
rL(phi) = |G_b(phi).origin-G_a(phi).origin| - L0
rS(phi) = |G_c(phi).origin - ((1-f)G_a(phi).origin+f G_b(phi).origin)|
```

`Map3DArcherPivot._geometry` requires `abs(rL) <= EPS` and `rS <= EPS`, with
`EPS=0.00001` native m for these comparisons. It covers both legs' thigh, shin
and foot-to-toe spans, and thigh/shin split points. `_solve` rebuilds anatomical
joint locations from rest lengths/fractions, then checks geometry before and
after reconstructing locals. `sample` also solves both supplied endpoints.
Supplying native foot/toe frames does not preserve every raw leg or skin point.
`NativeSource.calibrated` and the current eight-step `contact_plan` use corrected
foot goals; they are not raw MARCH. A did not change these semantics.

Frozen A-derived rows give these direct violations (mm shown for readability):

| MARCH phase / span | rL, native mm | rS, native mm | Current geometry disposition |
|---|---:|---:|---|
| 0.81 / left shin | -0.7676046516182922 | 0.715589172376835 | both excluded |
| 0.137 / left shin | -0.264628157236102 | 0.39749615043685037 | both excluded |
| 0.0285714310346818 / right thigh | -0.00028518816980183104 | 0.9031608399485996 | split excluded |
| 0.0285704310346818 / right thigh | -0.00023448401564873933 | 0.9032146887941191 | left neighbour split excluded |
| 0.0285724310346818 / right thigh | -0.00033536943921941287 | 0.9031042016183308 | right neighbour split excluded |

The split tolerance here is 0.01 mm. This is not a request to enlarge it.
Let d be the largest displacement of the relevant joint origins from raw native.
The reverse triangle inequality gives `abs(delta length) <= 2d`. With `0<f<1`,
the change of the split residual norm is at most
`d_c+(1-f)d_a+f*d_b <= 2d`. Thus at phase 0.81, any pose satisfying the existing
rules must move at least one relevant joint by at least **0.3788023258091461 mm**
from the length condition, and at least **0.3527945861884175 mm** from the split
condition. These are separate necessary lower bounds, not additive, not skin
displacement bounds, and not approved allowances. They are comfortably separated
from zero on the represented frozen input; full floating-point enclosure is a
later certification obligation, not inferred from printed decimal precision.

The rest-feasible set is closed because these residuals are continuous functions
of joint origins. A continuous candidate whose entire punctured neighbourhood is
in that set must have its endpoint in the set too. The raw endpoint above is
outside it. Consequently an exact endpoint special case plus the old interior
solve cannot fix C0 continuity. Passing only phase 0, omitting 0.81, snapping to a
key, normalizing skin weights or changing the baseline does not answer this proof.
Even the near-key samples above retain the split violation.

Local affine compatibility is an additional condition, not resolved by these
length calculations. `_same_affine` compares columns of `B^T B` to the authored
local basis. A rigid global correction under an anisotropic parent need not
preserve that local Gram matrix. A two-bone positional solve plus a later basis
repair is not a proof that both constraints coexist. All named bones, complete
FK, leg origins, split vectors, local Gram matrices and actual equipped skin must
be checked together. No blanket shear/scale/rotation permission follows.

## 3. Proposed protected-clause disposition: native intrinsic shape transport

**Proposal P1, not effective:** retain the actual raw MARCH boundary and replace
only the rest-length/rest-collinearity requirement for a separately identified
native-transition family by *no additional intrinsic deformation relative to its
bound native reference*. Keep the existing strict-rest solver and its tests as
their current contract. Do not silently reinterpret `sample` or change EPS.
This is a real geometry-rule amendment, not a calibration or a new baseline for
old evidence. It requires explicit human disposition before product registration.

The proposed replacement is precise enough to falsify:

1. Keep the existing author reference-phase law
   `phi(s)=(entry+((exit-entry) mod 1)*s) mod 1`, with exact entry/exit at s=0/1.
   Equal entry/exit means a held reference, not an invented full gait cycle.
   This names an author reference curve only; it neither chooses the incoming
   phase nor advances a gameplay clock. In a new native family, evaluate N(phi)
   directly, never `calibrated(phi)`. The existing internal root weight-shift
   law is not amended by P1; its authority and compatibility must be retained
   separately, with no actor-root, seat or external placement correction.
2. For each anatomical triple (a,c,b), demand one proper rigid transform Q at
   that s mapping its three **raw native origins** to the three candidate origins.
   Shared hip/knee/ankle positions must agree between adjacent segments. Therefore
   native span length, fractional location and perpendicular split residual are
   carried together. Bind the same Q to the following named global affine bases,
   for each side l/r (all names carry that side suffix):

   | Segment origins a,c,b (or a,b) | Bases bound to this segment's Q |
   |---|---|
   | thigh_twist, thigh_stretch, leg_stretch | thigh_twist and thigh_stretch |
   | leg_stretch, leg_twist, foot | leg_stretch and leg_twist |
   | foot, toes_01 | foot and toes_01 |

   Write native/candidate global origins as p/p' and complete global basis
   matrices as A/B. With `Q(p)=U*p+q`, require `B_k=U*A_k` for **all three raw
   basis columns** of each listed bone k, as well as the origin equations.
   The terminal joint's basis belongs to the next segment where listed; its
   origin is shared. Specifically `U=B_a*A_a^-1`, `q=p'_a-U*p_a`, `U^T U=I`
   and `det(U)=+1`. This uniquely defines Q without extracting/normalizing a
   rotation or replacing scale/shear in A/B. It transports the split relative
   to the actual oriented affine triad, rather than matching distances alone.
   For example, a=(0,0,0), b=(1,0,0), c=(.5,.001,0) to c'=(.5,-.001,0) with
   unchanged identity bases is rejected: the bases force U=I, whereas the
   origins would require a half-turn about ab. A proper origin-only rotation
   `diag(1,-1,-1)` and equal local Gram matrices do not satisfy this predicate.
   This example isolates the predicate; it is not a full-rig feasibility case.

   Collinear split origins and the two-point foot/toe span use the same full
   basis equations; do not infer a frame from a cross product of origins or
   leave twist free. Require positive anatomical span length and finite,
   positive-determinant invertible bases. Missing/singular bases, zero-length
   spans or an inverse that cannot be conservatively bounded reject the cell;
   they do not select an arbitrary orientation or remove that cell from required
   coverage. Q acts in native skeleton coordinates. At entry/exit U=I and q=0
   after factoring out external placement/yaw, with the same one-sided limits.
3. Require candidate local `B_b^T B_b = N_b(phi)^T N_b(phi)` for every modified
   bone, plus the existing positive determinant and joint-limit conditions.
   Retain all other locals according to the explicitly bound author reference
   and retained root law. The equations are simultaneous constraints: failure
   to satisfy them is rejection, never permission to relax Gram or move the root.
4. Require exact full native local boundary values and their C0 one-sided limits;
   raw named binds and all skin weights remain byte-preserved. This gives zero
   mathematical material seam at the boundary. Numerical implementation error
   must have its own conservative bound, not be relabelled physical deformation.
   Prove the same limit for arbitrary entry/exit, including the phase wrap.

P1's rationale is to avoid adding stretch to a source that already has intrinsic
affine/interpolation residuals. It does **not** declare those residuals physically
acceptable or guarantee a contact solve: parent-affine compatibility, joint limits,
surface contact and fixed R can still make the simultaneous system infeasible.
The source-vs-rest residuals must remain reported alongside the new residuals.
Their observed maxima are not chosen thresholds. The phase-0.81 counterexample
would cease to disprove *this explicitly different equation*, but continues to
disprove the old one; neither evidence nor old acceptance is rewritten.

Affected clauses if P1 is approved: the strict rest-anatomy comments and
`_geometry`/`_solve` assumptions in `scripts/map3d/map3d_archer_pivot.gd`, and
calibration/endpoint authoring in `tools/units3d/archer_arp/pivot.py`, require a
separate native-family path and explicit tests in `tests/map3d/test_archer_pivot.gd`.
The original contract in those paths remains effective until such a registered
change passes its own acceptance. This document cannot alter #231's immutable
acceptance, the original twelve P4 gates, `cf04c-locomotion-contract.md`, the six
old clips, rest/binds/weights, source bytes, actor root/seat, scale, R, committed
yaw/duration, or contact policy. No CSV change is part of P1.

If P1 is declined, the exact-raw plus original-rest conjunction remains excluded;
stop this repair route. Editing raw MARCH, retargeting its rest/weights, reducing
the phase/angle domain or allowing a boundary pop are different changes and are
not fallback permissions. If P1 is approved, D2 still must be resolved before B.

## 4. D2: physical objects, metrics, units and the missing authority

Let x(v,s) be the actual equipped material position in model metres: complete FK,
named Skin bind transforms and every raw weight, followed by the full skeleton
ancestor affine transform. No sum-to-one normalization. A rendered triangle's
material point is its fixed barycentric combination of its three **skinned
vertices**; do not substitute interpolated weights followed by skinning. This
definition covers its continuous area, including edges, seams and every surface.
Keep mesh/surface/triangle/vertex identities and degenerate-triangle disposition.

For comparison on ordinary terrain, compose the copied actual placement H(s),
including its root, yaw, seat and scale. Do not refit H to the shoes. Report world
metres and model metres separately; convert scalar distances by the actual uniform
scale only when proved uniform. General affine transforms require directional
or singular-value bounds. Native skeleton distances are separately labelled;
the frozen 421.437687637757 simulation-metres/model-metre conversion is not a
universal contact unit and cannot be used to change R or reference scale.

A physical support declaration must bind a finite list of anatomical outsole
triangles with positive area, a fixed material chart, a stance interval with
one-sided endpoints, and an anchor a(v) on the **actual** terrain for every material
point v. Its outward surface normal n(v) and supporting surface/cell identities
are fixed for that stance. Adjacent stance charts may change only at declared
handoffs; retain both limits. Moving anchors, reselecting lowest vertices, choosing
only passing triangles, or calling a whole swing a stance is invalid. At least
one declared support must cover each required grounded interval. Complete shoe
collision coverage includes non-support and swing surfaces too.

For a planar witness n is the fixed unit up-vector and the plane is model y=0.
For nonplanar terrain, use the copied native surface, orientation and a bound over
the whole projected triangle neighbourhood; a tangent plane is not the terrain.
Let h(v,s) be signed world-metre separation from that bound surface, and
P(v)=I-n(v)n(v)^T. Convert reported model-metre errors using the rule above.
The following are distinct suprema over **all** admissible operations and s, and
over every material point of the indicated surfaces, not sampled maxima:

| Quantity | Definition / domain | Units | Allowed-bound authority |
|---|---|---|---|
| Normal clearance | `sup max(0,h)` on the declared stance patch | model m, plus world m | no positive allowance established |
| Penetration | `sup max(0,-h)` on the complete collision shoe, including swing | same | ideal nonpenetration is zero; no positive numerical/physical budget authorized |
| Tangential slip | `sup |P(v)(H(s)x(v,s)-a(v))|` on a fixed stance chart | world m, converted model m | no positive allowance established; separate from normal clearance |
| Material contact displacement | `sup |H(s)x(v,s)-a(v)|` on that chart | same | separate combined norm, not a replacement for its components |
| Full equipped seam | `sup_v |x_pivot(v,e)-x_native(v,phi_e)|` and both one-sided limits, e=0/1 | model m | mathematical C0 target zero; verified arithmetic enclosure separately |
| Bone span | `sup |length-L0|` on every named anatomical span | native m | original rest constraint unchanged; P1 would add a separately reported native-reference equality |
| Split placement | `sup |c-((1-f)a+fb)|`, plus transported vector under P1 | native m | original rest constraint unchanged; P1 requires rigid transport, not an increased distance allowance |
| Local Gram | `sup max_j |(B^T B-N^T N)_j|`, report rest residual too | dimensionless | zero mathematical added affine distortion; existing EPS is an arithmetic guard, not contact budget |
| Patch area / normal | triangle area and oriented normal over stance | model m² / radians or unit vector | nondegenerate positive area and consistent orientation required; no guessed minimum area or tilt tolerance |

Zero seam follows algebraically from equal complete transforms, unchanged skin
data and equal placement. Zero added Gram distortion follows from a proper local
rotation. These are structural equalities, not invented perceptual tolerances.
They do not supply a ground-contact E. In particular `contact_um` in #202 is a
future ground-contact policy row, not an allowance for full-body seams or bones.
No archer `contact_um`/`turn_q` is installed in the frozen source. Missing fields
must reject certification, never mean zero, infinity or an inferred default.

### Retained measurement patches and what they cannot establish

The old CERT retains these diagnostic triangles on body surface 0. They remain
fixed measurement objects; they are **not** promoted to complete load-bearing
outsoles or sufficient support-area declarations:

| Side | Triangle / vertices | Rest area, model m² |
|---|---|---:|
| left | 80753 / 25967,49673,25970 | 0.00010571228856475105 |
| right | 13891 / 17151,31276,17148 | 0.00015227095922581654 |

At raw phase 0 the right vertices have heights approximately 1.9025783,
0.5848076 and 1.1780216 mm. The corresponding pivot has approximately
1.5108973, 0.1931422 and 0.7863463 mm. The left points are 32..41 mm high and
are in swing under the existing initial right-support schedule; those heights
are not a left-stance hover failure. Whole-cycle swing diagnostics stay diagnostic.

For the right triangle, the raw height range is about **1.31777068 mm**. Even a
free vertical translation (which is forbidden here) cannot make every point lie
on the plane: if penetration is forbidden, maximum clearance is at least that
range; if symmetric signed error were allowed, its minimum is half that range.
With the actual fixed placement, the current max clearance is instead at least
1.9025783 mm. These statements use linearity of height over a triangle. They
are necessary lower bounds for *this proposed patch and plane*, not reasons to
approve 1.903 mm, move the seat or select a different patch until it passes.

In the old first right stance `[0,0.125]`, sampled slip reaches
`0.000041579192319794695` model m. The accepted A decomposition's boundary
tangent displacement is only about `6.664e-8` model m in its Godot measurement,
while the selected right-point displacement is mainly normal, about
`0.00039167..0.00039170` m. Boundary tangent displacement therefore does not
bound stance slip, and a fixed foot/toe frame does not prove every weighted shoe
material point fixed. These observations retain their original arithmetic and
sampling limitations; none supplies a full-domain upper bound.

**Concrete D2 disposition:** decline to assign a positive contact allowance or
certify these two triangles as the physical support surface. The existing inputs
contain no independently accepted anatomical coverage/area judgement, compliant
sole/ground thickness model, or real-window tolerance calibration that would
justify one. Numeric maxima, helper EPS and synthetic examples cannot supply that
authority. Nor can an anatomical judgement alone set a slip or penetration limit.
The missing decision must bind (a) the exact complete material surface and its
positive-area support charts, (b) the ordinary native terrain/placement domain,
(c) separate maximum clearance/penetration/slip and combined-error budgets with
physical or faithful native-window evidence, and (d) their uncertainty budget.
This is an unmet prerequisite, not a list of PENDING fields that B may fill later.
No new diagnostic step or source modification is dispatched by this document.

For one already-defined norm with allowed error E, a common approximate boundary
needs `J<=2E`; if the raw side is fixed, it needs `J<=E`. These follow by the
triangle inequality. Neither implication reverses: ground contact, area, joint
limits, affine compatibility and the entire interval can still fail. E is not
selected from J, and a body J cannot be used in a sole-normal inequality.

## 5. D3: continuous native input and verifiable proof obligations

The binding input must be the **imported native** Animation resource and actual
AnimationPlayer/Skeleton evaluation, not just the GLB sampler or A's snapshots.
The installed MARCH is 1.1666666269302368 s with 89 tracks; the two 2 s pivot
clips are reference exports, not universal phase/duration coverage. The exact-key
`tools/units3d/archer_arp/pivot_import.gd` replaces the pivot pair, not MARCH.
An exporter/GLB interpolation evaluator alone does not establish native agreement.

A future provider must bind one immutable receipt containing: engine version/build
and executable identity; import settings and importer source hashes; source blend,
body/gear GLBs and their imported resource digests; the full scene graph ancestry;
complete named rest/parents and Skin binds; actual raw vertex/index/influence
arrays for all four equipped meshes; enabled native tracks, paths, types, key
times/values, interpolation/loop modes, transition/easing data and playback/mixer
state. Missing tracks retain their true rest/pose state, never an identity guess.
Hash the canonical payload with a nonrecursive digest rule, including ordered
arrays and exact float bits. Reject stale, nonfinite, duplicated, incomplete or
inconsistent input atomically without partially replacing a previously bound source.

It must provide both exact native queries and a conservative continuous enclosure
for every subinterval, with the complete local-affine/FK/LBS chain described above.
Queries reset and evaluate the pinned native state consistently; independently
compare raw locals, globals and equipped material positions, not only joint goals.
Enumerate native key boundaries, loop seams, interpolation branches and every
noncontinuous mode. Do not fit a curve through eight poses, resample as a nearest
key, orthogonalize the observations, normalize weights or invent derivatives.
Any mismatch beyond a derived arithmetic enclosure blocks the provider.

The required domain is the product of integer yaw in `[0,360000000)`, all legal
signed shortest nonzero microdegree turns (including the canonical +180-degree
tie), normalized operation phase s in `[0,1]`, entry and exit native phases in
`[0,1)` including both wrap limits, and every positive duration admitted by the
committed operation protocol. Zero-turn MARCH/hold compatibility is tested
separately and must not create a zero-duration pivot. Include the complete
ordinary placement/terrain/scale domain from the actual caller, both signs,
near-zero turns, all contact handoffs, and all material surfaces. Partial
certification remains explicitly partial; it cannot remove a required case.

`duration_q=t1_q-t0_q` is dimensionless committed time. Do not reinterpret it as
seconds or derive a 2-second minimum from the reference export. Geometric contact
bounds can be independent of duration only if the candidate map is proved to be.
For velocity/acceleration criteria a lawful adjacent-operation phase/placement
rate is necessary. Distinguish candidate position x from world position y:
write the external affine placement as `H(t)=(A(t),h(t))`, and
`y(t)=A(t)*x(s(t),phi(t),eta(t))+h(t)`. On each differentiable cell:

```text
xdot = x_s*sdot + x_phi*phidot + sum_j x_eta_j*eta_j_dot
ydot = Adot*x + A*xdot + hdot
yddot = Addot*x + 2*Adot*xdot + A*xddot + hddot
```

Here `xddot` is the total second derivative, retaining mixed partials and the
rates/accelerations of every independent admitted input eta. Parameters fixed
within one operation have zero rate; nonzero rates must come from their actual
authority. Use one-sided derivatives at key/support/wrap boundaries and verify
any required kinematic matching there. Only for a pure adjacent native reference
`x=N(phi)` with no independent s/eta dependence does the shape term reduce to
`N_phi*phidot`. A held native reference does not freeze the pivot/contact map.

Hand case from the retained author law: entry=exit makes phidot=0, but with
turn=pi/2 the internal root displacement is
`dy_root(s)=-0.01*sin(pi/4)*sin(pi*s)^2` native m. At s=1/4 its derivative is
`-0.01*sin(pi/4)*pi=-0.02221441469079183` native m per unit s. It contributes
this value times sdot to the native root velocity even though phidot=0. Ordinary
placement converts that contribution to world units; it does not erase it.
This is an existing-law arithmetic control, not new permission to change the root.

Pause/1x/4x and frame partitions change sampling, not the bound identity or phase
authority. No wall clock, hidden phase reset, second timer or duration clamp is
introduced. Absent a lower duration/rate authority, no finite universal speed/
acceleration budget can be claimed from a nonconstant candidate trajectory.

Partition the parameter domain at native key/loop seams, phase-law wrap, support
handoffs, solver branch/singularity boundaries and terrain cells. For each closed
cell enclose every arithmetic operation, inverse, square root, rotation branch,
FK product and weighted skin term with outward rounding. Bound denominators away
from zero; otherwise subdivide or reject with a witness. Bound interpolation error
between exported keys and the intended map as well as the native evaluator's
roundoff. A derivative/Lipschitz bound must be derived on its cell, not estimated
from samples. Uncovered cells, undecided signs and nonterminating refinements are
unproved, never silently removed or accepted by timeout.

For a planar surface, linear height and convex displacement norms on a rendered
triangle attain their maximum at a vertex for a fixed time; time still needs
continuous enclosure. For nonplanar terrain, vertex checks alone are insufficient.
Full equipped envelope uses actual radius/scale, not contact patches. Continuity
requires both boundary values and one-sided interval limits. Positive-area and
normal degeneracies need their own bounds. A proof receipt records every cell,
its source hashes, method, error components and coverage; the original CERT
owner checks it against installed C output rather than reusing an author claim.

Independent native adversarial checks must include all sixteen old witnesses,
the five geometry rows above, both sides of every retained key/support/wrap
boundary, random interior points from a recorded test seed, extrema suggested
by the interval proof, one-quantum durations, exact/near 180 and near-zero turns,
and nonplanar surface edges where applicable. Use a separately implemented native
evaluation/check route, not the author's same algebra twice. Dense agreement
can falsify but cannot replace continuous coverage or physical budget authority.

## 6. Every original boundary witness remains addressable

Indices below are the zero-based positions in original `pivot-contacts.json`'s
`boundary_counterexamples`. All have native MARCH phase 0 and surface 0. Units
are model m; the underlying raw coordinates, matrices and weights stay in #231.

| Witness | Pivot / phase | Mesh / vertex | Original maximum J |
|---:|---|---|---:|
| 0 | LEFT / 0 | archers / 35966 | 0.0008411830267833711 |
| 1 | LEFT / 0 | archers_bow / 4363 | 0.0000002323797229915028 |
| 2 | LEFT / 0 | archers_quiver / 9792 | 0.0000001798061734859519 |
| 3 | LEFT / 0 | archers_arrow / 6122 | 0.00000022990153296571223 |
| 4 | LEFT / 1 | archers / 35966 | 0.000841195334928635 |
| 5 | LEFT / 1 | archers_bow / 4363 | 0.0000002323797229915028 |
| 6 | LEFT / 1 | archers_quiver / 9792 | 0.0000001798061734859519 |
| 7 | LEFT / 1 | archers_arrow / 6122 | 0.00000022990153296571223 |
| 8 | RIGHT / 0 | archers / 35966 | 0.0008411830267833711 |
| 9 | RIGHT / 0 | archers_bow / 4363 | 0.0000002323797229915028 |
| 10 | RIGHT / 0 | archers_quiver / 9792 | 0.0000001798061734859519 |
| 11 | RIGHT / 0 | archers_arrow / 6122 | 0.00000022990153296571223 |
| 12 | RIGHT / 1 | archers / 35966 | 0.0008411762207713449 |
| 13 | RIGHT / 1 | archers_bow / 4363 | 0.0000002323797229915028 |
| 14 | RIGHT / 1 | archers_quiver / 9792 | 0.0000001798061734859519 |
| 15 | RIGHT / 1 | archers_arrow / 6122 | 0.00000022990153296571223 |

Rows 0/4/8/12 retain the failed material seam. Rows 1–3/5–7/9–11/13–15 remain
gear regressions, not independent evidence that submicrometre roundoff is a
permitted physical gap. All sixteen must replay against frozen old inputs and
be compared separately against any later candidate, with unchanged material IDs.
Right sole normal/tangent, first-stance slip and swing diagnostics remain separate
from this table. The geometry rows in section 2 are exclusions for the current
hard requirements and explicit tests for P1 if authorized, never discarded samples.

## 7. Conditional files, sequencing, acceptance and stop

Nothing below starts work. Only the existing dispatcher may register a later
bounded step after explicit P1 disposition **and substantive D2 resolution**.
Keep A accepted, original CERT failed and all existing owners. Do not dispatch
an overlapping B or revive A to implement this proposal.

The three original B candidate paths retain these responsibilities:

- `tools/units3d/archer_arp/pivot.py`: bind the continuous native provider, preserve
  raw/calibrated provenance separation, author the approved contact/mapping family.
- `scripts/map3d/map3d_archer_pivot.gd`: keep the old strict-rest API; integrate only
  the explicitly approved separate native-family entry, with atomic rejection.
- `tests/map3d/test_archer_pivot.gd`: original negatives plus new simultaneous
  geometry/Gram/boundary/neighbourhood/material/contact proof controls.

If P1 is approved, the proposed literal module boundary for the distinct pure
native-family solve is `scripts/map3d/map3d_archer_native_transition.gd` and
`scripts/map3d/map3d_archer_native_transition.gd.uid`. This avoids pretending a
near-500-line solver can absorb a second contract by deleting checks or raising
the cap. The continuous native input provider's proposed literal paths are
`tools/units3d/archer_arp/native_curve.gd` and
`tools/units3d/archer_arp/native_curve.gd.uid`: read-only native resource protocol
and query/export of the complete track/skin authority, not another standalone
certifier. Neither module is created here or included in current ownership.
Before B registration, its implementer must bound the analytic enclosure work
and list any additional literal file needed; these seven paths are a proposal,
not an assertion that an unimplemented full-domain solver fits one small PR.
If input-provider and mapping work need separate steps, the provider precedes
mapping; shared pivot/test files serialize. No overlapping or circular dispatch.
`map3d_archer_boundary_skeleton.gd` and its UID remain read-only reused measurements.

Conditional C owns only `assets/3D/units/archers/archers.glb`, after accepted B.
Reuse `export.py`'s `PIVOT_INPUT`/`PIVOT_RESULT` and the exact-key importer; preserve
the old six clips/BIN payload, named binds, rest, weights, gear and scene. C changes
only the authorized pivot curves and proves installed/native boundary and interval
agreement. If another file is actually required, register its literal path first.
A helper that is not connected to installed C output cannot resolve the old seam.

After accepted C, the **original CERT owner** recertifies the changed installed
inputs, keeping old hashes/witnesses as history. No separate certifier/third reviewer
is introduced. Policy, consumer and activation remain downstream. There is no edge
requiring failed #231 to merge before its repair prerequisites, and no automatic
successor creation. This document grants no root/seat/R/scale/source/time change.

B/C readiness requires all of: explicit protected-clause disposition; justified
D2 material/terrain/budget authority; verifiable D3 provider/proof obligations;
bounded exact ownership and accepted dependencies. A later B must actually prove
the equations/contact/full-domain bounds and independent native checks, not just
adopt their interfaces. Current status is **B=false, C=false, CERT=failed**.
P1 approval alone cannot flip these flags. If evidence cannot establish D2, stop
with this concrete proposal and missing authority; do not merge a PENDING contract
as an accepted implementation prerequisite or weaken the immutable acceptance.

All twelve spec §9 gates and #202's full contact/envelope/visual/performance gates
remain: counts and fixed footprint; complete sweeps/yield/turn/reload; formation
eligibility; independent budgets; actual delivery/version/king; vulnerable assembly;
real reorganization and unique membership; all eight normal/blocked/member-loss
cases; physical combat/ranged occlusion; save/clock/cost/personnel compatibility;
reproducible formation-vs-none/countered outcomes; actual 3D-map visuals/performance.
Native continuous near/far pause/1x/4x, different FPS, material-foot crops and sole
Review critique remain required. Static images, a headless numeric extraction,
circles, dense samples or a retimed film cannot replace them. Use the shared Godot
lock and visual-review if new visual evidence is needed; none is claimed here.

This single-document change is checked with frozen-input hash/number assertions,
whitespace and documentation-only selection, Python hook/selector/runner/timeout
self-checks, shell/config/guide checks and required current-HEAD CI. It runs no
Godot/Blender and does not claim new physical measurement or visual acceptance.
Its unique Review may independently assess this bounded exclusion/proposal and
return findings to the same implementation session. Passing document CI alone
does not satisfy D2 or authorize a B-ready merge.
