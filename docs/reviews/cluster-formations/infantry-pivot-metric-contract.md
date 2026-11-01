# Infantry pivot metric adapter

`LOCO-INFANTRY-METRICS`, implementation `01a198dd-e9d0-7df2-852a-5eea882e2ce6`,
dispatcher `01a17398-42c1-7583-8d3f-7b15e877586c`; unique Review `01a198e8-c627-7092-b559-b935496d8a5e`
registered by that dispatcher for this PR. Scope is exactly this file,
`tools/units3d/soldier_arp/pivot_metrics.py` and `test_pivot_metrics.py`.
Dependencies are accepted `CF04c-locomotion-contract`, `LOCO-INFANTRY-TRANSITION`,
`LOCO-ARCHERS-PIVOT-IMPORT`, `LOCO-INFANTRY-FEASIBILITY-CONTRACT` (#202/207/216/223).
#223 accepts documentary evidence, not motion. There is no dependency on #221.

This measures the approved [CF04c contact obligations](cf04c-locomotion-contract.md)
and extends the [accepted frozen reproduction](infantry-pivot-feasibility-contract.md).
It selects no `contact_um`, changes no source/placement/helper/threshold and creates
no certificate, policy, solver or supported-motion claim. Report generation can
exit 0 with `reproduction: MATCH` while `motion_acceptance` remains `FAIL/PENDING`.
All original P4 acceptance and clip → CERT → POLICY → CONSUMER ordering remain.
The original #221 pair has no implementation or review role in this PR.

## Exact frozen native inputs

The entire committed accepted223 `tests/fixtures/infantry_pivot_feasibility.json`
bytes must hash to `e1f2a783bff16aa3371823d5844c195634ac7ae0d9be21fd0692a9e1aceb10c5`.
This is the content merged at `1bb806ae1db93ccb581b4bed1766a734975dbc30`.
The adapter imports the accepted223 replay, retaining all nine independent embedded
source digests, original manifest, corruption/size/byte checks, exact hexadecimal
native phase IDs and all arithmetic/attribution assertions. It does not copy or
edit that replay or consume live #221 files. Frozen source/native geometry identities
are distinguished in that contract; different historical GLB hashes are not equated.

Every source, authored-reference and mapped frame deforms all 20,880 vertices using
all four captured packed influences and all 69 named inverse binds:

`XYZ(sum_k weight_vk * global_bone_k * inverse_bind_k * [vertex,1])`.

No normalization occurs even when packed sums are below 1. The native source uses
actual Godot sampled globals. References and mapped globals compose all declared
parent-relative locals through the frozen hierarchy. There is no interpolated or
nearest native lookup. Each of all 1,300 captured frames in each variant scans all
33,427 sorted unique edges. Per-variant whole-mesh binary-double SHA256 digests bind
the complete evaluated geometry. This finite coverage is not the full continuous
turn/phase/duration domain and is not a fresh Godot sampling run.

The strict gate remains `length > 4 * native_entry_length AND length > .03 m`.
Per-frame source/reference/mapped absolute flags and worst extension are separate
from introduced flags. Native absolute failures are adverse, never subtracted away
or waived. All 471 mapped pairs, 45 introduced pairs and one mapping-only crossing
must still reproduce. Source endpoint edge 23264 remains red:
`.05493455191032237 > 4 * .012666906066611604` and `> .03 m`.
No mapper remedy or finite-contact infeasibility follows from reproducing that flag.

The frozen whole-domain scan reports 652 source, 563 reference and 471 mapped
absolute edge/phase flags; 103 reference and 45 mapped flags are introduced
relative to same-phase source, with one mapping-only crossing. These totals also
include frames where mapped skin has no failure; no baseline failure is hidden
by limiting comparison to the mapped failing set.

## Physical measurement input

By default physical contact is **PENDING**: the fixture has no independent physical
Terrain3D ground/placement and authored material stance provenance. Animated boot
minima and rigid helper markers cannot supply those missing facts. No ground plane
is fitted to entry, exit or each animation frame.

An optional `--contact-input PATH` is an immutable external JSON measurement input,
read once and hashed verbatim into the report. Its fields are:

- `provenance`: nonempty `source` and 64-digit lowercase `sha256`, identifying the
  independent placement/terrain/material-interval evidence. This records supplied
  provenance, not authentication of its truth or a grant of policy authority.
- `placement`: finite positive affine 4×4 model-to-world matrix, row-major, acting
  on column vectors. `original_scale` is its unchanged uniform positive basis scale
  in world coordinate units per native model metre. Translation/rotation/scale are
  supplied from physical placement, never tuned to animation errors. Shear,
  reflections and a mismatch to original uniform scale reject.
- `world_unit_m`: metres per world coordinate unit. World distances multiply by it;
  model micrometres divide world coordinate distances by `original_scale`, then
  multiply by 1e6. Thus physical scale is `original_scale * world_unit_m` metres
  per native model metre; changing coordinate units must change scale consistently.
- `numeric_error_model_m`: nonnegative externally justified conservative capture,
  LBS, placement and terrain uncertainty in native model metres. Zero is appropriate
  only for exact synthetic input. The input's provenance must justify this bound;
  absent/unknown numeric uncertainty must not be represented by an invented zero.
- `cases`: one row per frozen case in the same order, with exact `turn_udeg`, a
  fixed physical `ground` (`origin`, `normal`, both world coordinates), and
  `patches`. This adapter measures a fixed planar ground sample for each case,
  not arbitrary changing terrain. A source heightmap/frame record must establish
  that the plane is the actual relevant physical sample; otherwise leave PENDING.
- Each patch has a unique `id`, `kind` (`stance`, `toe`, `swing`), finite `start/end`
  operation phases with `0 <= start < end <= 1`, fixed native material `vertices`
  and corresponding independently supplied planted world `anchors`. Endpoints
  must be captured phases. Vertex IDs are unique and valid. Intervals sharing
  material vertices cannot overlap. Changing vertex selection per frame, choosing
  the lowest vertex anew or fitting anchors from animated observations is forbidden.
  The provenance must state which sole/toe and stance obligation applies. Swing
  samples are measured explicitly and receive no stance-budget verdict.
- Optional `budget`: integer nonnegative `contact_um`, nonempty `authority` and
  `source_sha256`. These must reference an external authorized finite bound. Merely
  supplying strings does not authenticate authority. Absence yields PENDING; no
  rounded-up/fitted tolerance or fixture test value becomes an infantry policy.

At a shared interval boundary, the next interval supplies the active patch; at
phase 1 the final interval includes the endpoint. `exit_patches` separately
measures the outgoing interval at its exact exit; no prior stance exit is hidden.
Gaps in authored interval coverage are explicitly listed as missing evidence. Intervals describe material
identity, not permission to omit vertices from deformation, edge or penetration
scans. All deformed geometry is projected onto the supplied ground normal for
whole-mesh minimum/maximum separation and worst penetration. Reporting these plane
measurements does not prove actual terrain coverage outside that plane/patch.

For a unit world normal `n`, physical position `p`, supplied ground origin `g` and
fixed planted world anchor `a`:

- Signed separation is `dot(p-g,n)`; penetration is `max(0,-separation)` and hover
  is `max(0,separation)`.
- Tangent stance slip is `length((p-a)-n*dot(p-a,n))`. It is displacement from the
  same material anchor, not accumulated path length or a newly selected foot point.
- The finite point error is `max(abs(separation), slip)` in model micrometres.
  Signed separation and slip differences versus source are reported alongside
  each absolute source/reference/mapped measurement, never in place of absolutes.
- A common transformed plane uses inverse-transpose normals and normalization.
  Moving both point and plane rigidly preserves model error; a common positive
  scale doubles world distance at scale 2 and converts back to the original model
  error. Moving only the point against unchanged physical ground changes error.

A 256-ULP outward arithmetic guard based on coordinate magnitude covers the small
fixed contact dot/subtract/norm calculation in double precision. A separate
placement arithmetic guard uses absolute matrix-product magnitudes before
cancellation (64 ULP per coordinate, multiplied by 4 for vector projections); the externally
justified capture/terrain uncertainty is added separately. Budget comparison uses
`ceil(measured_model_um + numeric_guard_model_um)` with no epsilon relaxation.
`WITHIN_FINITE_SAMPLES` is only an upper-bound comparison for measured patch points,
never motion PASS, ground certification or continuous coverage. Input provenance,
uncertainty and domain proofs still require independent review.

## Residuals, rejection and honest missing evidence

Reports keep each combined helper capture's failures and sample count separately.
All 1,300 accepted combined frames remain in every scan. This adapter does not rerun
or repair the helper. Earlier direct-reference rejection per-sample reasons/traces
are not bundled in accepted223; that channel is explicitly PENDING, not zero
rejections and not grounds to exclude a phase. Documentary prior rejection evidence
remains adverse; no full-domain helper acceptance is claimed.

At each endpoint the report measures full-skin distance and bone-global component
residuals against the actual native phase. At entry and exit it also reports the
adjacent finite displacement and source-relative velocity secant residual over the
captured operation duration, in metres per normalized simulation substep
(`duration_q / 1e6`, dimensionless), never metres per wall-clock second. These are
finite one-sided differences, not a proof of
matching MARCH derivatives or stance continuity. External MARCH derivative data,
full-domain interpolation/skinning bounds, yaw silhouette/envelope, actual physical
terrain/stance provenance, authority budget and real-window near/far/pause/1x/4x/FPS
acceptance remain explicitly open. No numeric report replaces the original visual
pass or claims the locked-window evidence has been obtained.

## Reproduction commands

```sh
python3 tools/units3d/soldier_arp/test_pivot_metrics.py
python3 tools/run_with_timeout.py 2100 python3 tools/units3d/soldier_arp/test_pivot_metrics.py --full
python3 tools/units3d/soldier_arp/pivot_metrics.py
```

The small tests hand-compute two-vertex LBS with a .5 packed-weight sum, independent
source/reference/mapped transforms, strict 4×/.03 boundaries, 3mm slip and 2mm
penetration, common rigid/scale-2/unit transforms, inverse-transpose normals,
fixed-anchor/boundary semantics, missing authority, malformed evidence/matrices,
corrupted fixture and unchanged inputs. `--full` runs the whole frozen adapter
in two fresh processes, compares exact output bytes and verifies unchanged fixture
bytes, writing the reviewable report only to ignored `.superpowers/`.
The actual diff selector and all required current-HEAD CI remain binding; no
runner/selector/gate change or routine local full GUT is part of this step.
