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

## Legacy224 physical measurement input (unchanged)

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

## Versioned raw observation contract (A; implementation pending)

Step `LOCO-INFANTRY-PHYSICAL-INPUT-CONTRACT`, implementation
`01a19bd9-7ce0-7ca1-a857-5b14507aee7b`, sole dispatcher as above; its unique
Review is recorded in the PR/checkpoint before handoff. A owns only this document
and [skin acceptance](infantry-pivot-skin-acceptance.md). Its prerequisites are
accepted CF04c/#223/#224/#225, never unmerged capture, #221 or future CERT.
The following is an external interface for later B/C, not an implemented CLI.

The immutable motivation is the original capture owner's **2026-11-02 Astra
boundary decision** in `cluster-infantry-contact-capture/game_design/HANDOVER.md`,
SHA256 `40cc4a7fa1a7c8b411b6a35bdce5e5437c7f0c48028c91d76b05411f6dd05743`.
It records a maximum relative Gram residual `1.0525859445735615e-7` at (2,2),
above the unchanged `1e-10` predicate. Legacy224 must still reject that original
matrix with `placement differs from original uniform scale`. Preserve every raw
component and the original reported scale; no orthogonalization, polar fit,
alternate scale getter, rounded export or threshold increase is a repair.
The recorded material-survey plane residual is `1.3536629676818848` world m in
native float32 and `1.3536624390927234` recomputed in double; the separate
17-point footprint survey gives `9.524883270263672` m. These are failed finite
observations with different arithmetic/coverage, not error bounds, terrain
coverage or executable dependencies. No unmerged capture code/data is imported.

### Dispatch, schema and separate states

Keep `--contact-input`, `validate_contact_input`, legacy reports and errors
unchanged. Add an explicit, mutually exclusive `--raw-observation PATH`; never
retry rejected legacy input in raw mode. Its discriminator is exactly
`schema: "infantry-pivot-raw-observation/v1"`. Unknown versions/modes reject.
B supports only `surface_mode: "fixed_plane"`; C adds `"native_queries"`.
Neither mode changes deformation, native phase selection or the absolute edge
scan. Every observation report retains all legacy adverse skin results.

| Report field | Values and meaning |
|---|---|
| `schema_status` | `VALID` means structurally valid, byte-bound input; `REJECTED` means no consumable physical report. Explicit null uncertainty is valid missing evidence, not zero. |
| `measurement_status` | `GENERATED` for all requested finite values; `PARTIAL` for explicit unavailable surface rows; `PENDING_RESPONSES` for a query manifest alone. None means physical acceptance. |
| `placement_uniformity` | `PREDICATE_SATISFIED`/`FAIL` for the original strict Gram predicate only, with all nine residuals, scale, threshold and worst indices. Raw mode never emits uniform-placement `PASS`, even for an exact synthetic matrix. The recorded matrix is `FAIL` in every report; no harmless-rounding claim follows. |
| `coverage` | Separate expected/received/valid/uncovered counts and identities for vertices, anchors, active and outgoing patches; `COMPLETE_FINITE`/`UNCOVERED`. Continuous domain and rendered surface each remain `PENDING` absent independent proof. |
| `uncertainty_status` | `BOUNDED` only with justified conservative bounds for every contributing input; otherwise `UNKNOWN`, with null upper bounds and explicit missing terms. |
| `budget_status` | Missing authorized E: `PENDING`. E supplied but placement FAIL: `INELIGIBLE_PLACEMENT`. Missing coverage/uncertainty: `PENDING`. Only otherwise compare the outward model bound: `WITHIN_FINITE_SAMPLES` or `FAIL`. Swing: `SWING_NO_STANCE_VERDICT`. Never `PASS`. |
| `motion_acceptance` | `FAIL/PENDING`, retaining introduced failures and every missing original obligation. No v1 observation report can certify motion. |

These fields coexist: `schema_status=VALID`, `measurement_status=GENERATED` and
`placement_uniformity=FAIL` is a useful adverse result, not a clearance. List
**all** blockers even when missing E determines the budget status. Exit 0 means
a completed report/manifest, not any acceptance. Malformed/integrity failures
exit nonzero; incomplete outputs are never published as complete evidence.

Required v1 header (additional fields require a documented schema revision;
reject duplicate JSON keys, nonfinite numeric values and conflicting IDs):

| Field | Required contents |
|---|---|
| `provenance` | Nonempty source, lowercase SHA256 of an immutable evidence payload, plus capture tool/version, engine/Terrain3D build and capture frame/time IDs. Hashes bind bytes, not truth or authority. Synthetic inputs say `synthetic`; real capture cannot use that label. |
| `inputs` | Accepted223 fixture digest above; all nine source digests and native mesh/raw-weight/bind/hierarchy/phase identities; installed model/import/scene/gear and placement/terrain manifests with bytes/digests and provenance of any historical identity correspondence. No equality by filename. |
| `placement` | Original affine row-major 4×4 matrix acting on column vectors, original positive reported scale and `world_unit_m`; original scalar precision and bit patterns for all components/scale, plus the unmodified construction-input record or explicit unavailable reason. Numeric values must decode exactly from those bits. Finite positive determinant required, including on raw mode; singular, reflected, non-affine or nonfinite inputs reject. |
| `frame` | Units and common coordinate frame, up direction and terrain height-query chart (native world XZ, +Y up), terrain transform and their hashes. Convert all outputs to world metres; never silently exchange model/world units or charts. |
| `cases` | Exact accepted case order, turn, duration, entry/exit native hexadecimal IDs and operation phase IDs. Fixed material patch IDs/kinds/vertices, intervals and independently authored world anchors follow legacy boundary/no-overlap rules. Keep authorship/source evidence and per-obligation gaps, not just union coverage of unrelated patches. |
| `surfaces` | Immutable typed surface records described below; fixed-plane mode also supplies actual physical origin/normal and proof of its limited planar domain. Synthetic planar fixtures carry no native-capture claim. |
| `uncertainty` | Per-contributor conservative position/height/normal/query-coordinate/anchor bounds, units, derivation and evidence digest; each unknown is null with reason. Zero requires an exact synthetic justification. Native rounding alone is not the entire capture/terrain error. |
| `budget` | Null, or legacy integer `contact_um`, authority and source digest with the independently authorized bound. No fitted/rounded-up test budget becomes policy. |

Wire envelope keys are `schema`, `kind`, `header`, `chunks`, `footer`; kind is
`observation`, `requests` or `responses`. The observation header contains
`surface_mode` and the fields above. Requests/responses headers contain
`observation_header_sha256`, `fixture_sha256`, `surface_manifest_sha256`; response
headers additionally contain `request_stream_sha256`. Hash the exact compact,
sorted-key UTF-8 header bytes, with no LF. Observation provenance payloads must
not include a back-reference to their enclosing file digest. Observation chunks
are empty; requests/responses carry the streams below. A fixed-plane observation
needs no response stream. Final capture may store the observation in
`contact-input.json` and the responses plus independent provenance payloads in
`contact-provenance.json`; the provenance payload is separately byte-bound so
the response's header link creates no hash cycle. Such payloads are a named
`header.evidence` dictionary of base64 bytes/digests, not arbitrary extra keys.
`header.evidence` is permitted for every envelope, empty when no payload is
embedded; external payload references require exact bytes available to validation.
No missing real evidence is repaired by generating a synthetic payload.

Store raw floating-point bits as fixed-width lowercase hexadecimal IEEE-754
words (8 digits binary32, 16 binary64, most-significant byte first); preserve
signed zero. Scalars used in arithmetic decode from these words. Native NaN/
hole observations are stored as raw words with a typed unavailable status, never
as a JSON NaN number or a usable finite height. Header/payload hashes exclude no
input bytes: hash each referenced payload and the whole input verbatim; avoid
self-referential hashes by putting the final input digest in the report.

For matrix basis B and original scale s, compute the **same** legacy sums and
comparisons `abs(sum_k B[k,r]*B[k,c] - delta_rc*s*s) <= 1e-10*s*s`.
Passing a schema or positive determinant is not passing this predicate. Apply
the original raw matrix directly to deformed points, including its translation,
without normalizing raw skin weights. If uniformity fails, publish world metre
measurements and optionally `nominal_scale_model_um = world_m/(s*world_unit_m)*1e6`,
explicitly noncertifying. These nominal numbers cannot enter a model budget
comparison or claim uniform-scale invariance. An independent original-construction
and rounding proof may explain the failure later; v1 neither supplies that proof
nor uses it to erase FAIL or substitute an ideal matrix.

### Native query protocol and surface semantics (C)

Existing consumer boundary is `main -> evaluate -> validate_contact_input /
physical_metrics`. B adds explicit raw dispatch beside that boundary; C reuses
`load_frozen`, `deform` and `frozen.Skin.points` read-only to generate requests.
Caller flow is: external raw header → adapter-generated query manifest → native
oracle evaluating the unchanged independent terrain → hash-bound responses →
adapter report. C exposes `--raw-observation HEADER --query-output PATH` for
manifest generation and `--raw-observation INPUT --query-responses PATH` for
evaluation. Native mode without responses only generates requests; no sampling
or query from Python's reconstruction of Terrain3D interpolation is allowed.
The later original capture tool is the oracle, never a Python import/dependency.
Header, manifest and responses carry the same header/fixture/surface digests;
final capture evidence embeds/binds them in its existing two JSON paths.

Each logical request contains a monotonic ordinal; case/turn/duration; operation
phase hex, exact source native request ID; variant (`source`, `reference`,
`mapped`); vertex ID or fixed-anchor ID and role (`vertex`, `anchor`); full raw
placed position binary64 words; intended XZ and actual native query XZ words;
surface ID/hash and query method/version. Native binary32 XZ conversion is
round-to-nearest/ties-to-even, recorded with its exact displacement; reject
overflow. Request order is case, captured phase, source/reference/mapped,
ascending vertex ID, then anchors in case/patch/vertex order. An anchor request
binds its interval endpoints and material identity, not a moving phase-derived
position. Active/outgoing uses reference these immutable request IDs, including
both intervals at a shared boundary and the phase-1 exit.

Responses echo the ordinal and all identity/coordinate/surface fields exactly,
plus query status, raw height/normal bits, used height/normal, their respective
surface IDs/methods, capture context and uncertainty record references. Validate
against the regenerated requests and hashes, not merely a supplied digest string.
Missing, extra, reordered, wrong-phase, wrong-coordinate, wrong-terrain or
duplicate-conflicting responses reject complete evaluation. A present response
explicitly saying `HOLE`/`UNAVAILABLE` is retained as uncovered adverse evidence;
no finite-contact comparison may cover it. Truncation is not an unavailable row.

Request row keys are `ordinal`, `case_index`, `turn_udeg`, `duration_q`,
`phase_hex`, `source_phase_id`, `variant`, `vertex_id`, `anchor_id`, `role`,
`interval_hex`, `position_f64`, `intended_xz_f64`, `query_xz_f32`, `surface_id`,
`surface_sha256`, `method`, `method_version`. Integer IDs are nonnegative except
signed turn; hexadecimal phase strings retain the accepted native format.
Vertex rows have null anchor/interval, anchor rows have null phase/source/variant
and identify their patch/vertex with both interval endpoint hex strings.
Vectors are fixed-length arrays of the raw words defined above. Responses contain
`request` (the entire matching row), `status` (`OK`, `HOLE`, `UNAVAILABLE`),
`raw_height`, `raw_normal`, `used_height`, `used_normal`, `height_surface_id`,
`normal_surface_id`, `height_method`, `normal_method`, `capture_id`,
`uncertainty_id`, `reason`. Raw/used scalar records carry `precision` and `bits`;
normal records carry three words. Unavailable fields are null with a nonempty
reason; nonfinite raw bits remain in raw fields. Used finite values must match
the declared selection rule. Uncertainty records use a bound value or null,
unit, derivation, evidence digest and unknown reason for every contributor.

Surface records distinguish `terrain_raw`, `sea_clamped`, `height_override` and
`rendered_lod`, with original data/resource hashes, terrain transform, region/LOD
and method parameters, sea level/override identity as applicable. Bind the actual
bytes of supplied evidence and verify producer-side resource hashes before and
after the capture; a string identifier alone is insufficient. Record raw results
separately from the selection rule and used results. `Map3DContext.height_at`
may return an override, sea for missing/NaN terrain, or max(raw height, sea).
That result and `terrain.data.get_normal` do not automatically define one surface.
A sea-clamped branch needs a normal for that declared branch, plus its switch
boundary/uncertainty; an override needs its own height/normal provenance. A raw
hole remains recorded even if runtime seating used sea. Such fallback is not
proof of a valid rendered contact surface. Mixed or unproved height/normal pairs
are uncovered; do not borrow a favourable plane normal. Rendered LOD discrepancy,
triangle interiors and swept/continuous coverage require separate evidence.

For each finite vertex p, native queries supply height h and a valid upward unit
normal n of the **same declared surface**. Let `q=(p.x,h,p.z)` in its query chart:
vertical clearance `v=p.y-h`; local-normal separation `d=dot(p-q,n)`; report both
with penetration/hover `max(0,-value)` / `max(0,value)`. Neither is a global nearest
surface distance. Keep the vertical sign even when the normal is missing; zero,
nonfinite or downward normals cannot make penetration favourable. Normalize only
a valid measured surface normal, retaining its raw bits and propagated error;
never normalize the placement or weights. At a nondifferentiable ridge report
the method's one-sided normal/ambiguity; an unbounded ambiguity is uncovered.

For each independently prescribed planted anchor a, query its normal n_a once
on its frozen surface. Stance slip is `||(p-a)-n_a*dot(p-a,n_a)||`. Keep a and n_a
fixed over that material interval, including its outgoing exit; a new ground
query under p cannot move a, select another material vertex or change n_a.
Retain absolute source/reference/mapped values and whole-mesh extrema/worst IDs,
then source-relative differences. Queries evaluate a pre-existing surface at
animated XZ; they never choose height from animated boot Y.

### Uncertainty and finite comparisons

All bounds below are in world metres except unit-normal errors (dimensionless).
Require conservative bounds on position `e_p`, fixed anchor `e_a`, sampled height
and normalized normals. L_h/L_n require a proof for the actual frozen method and
its declared target/domain. A real-coordinate surface target needs bounds over
the entire real neighbourhood. A finite quantized-API target may instead use the
conditional native-domain proof below; its lattice constant is **not** a
Lipschitz constant of the real-coordinate surface or of its stepwise extension.
Surveys or a maximum observed residual are not bounds. Holes, switches or ridges
without the required bounds leave that contribution unknown. Anchor queries use
their own independent bounds.
Let `e_q` bound the full ground-point uncertainty, including XZ and height terms,
and `e_n`, `e_na` bound normalized n and n_a. Conservative propagated bounds are:

- `e_v = e_p_y + e_h` for vertical clearance.
- `e_d = e_p + e_q + (||p-q|| + e_p + e_q)*e_n` for normal separation.
- `e_slip = e_p + e_a + (2*e_na + e_na*e_na)*(||p-a|| + e_p + e_a)`.

Add the existing 256-ULP contact guard and absolute-product 64-ULP placement
guard (×4 for vector projections), converted to world metres, and outward
arithmetic bounds for query conversion, normalization and these new calculations.
Avoid cancellation-based error estimates; guards do not replace physical bounds.
Propagate intervals for signed values and extrema, keeping measured adverse signs
visible even if uncertainty straddles zero. Any unknown contributor gives a null
upper bound, never zero. For strict-uniform, fully covered finite stance points
with known uncertainty and independently authorized E only, use
`ceil(max(abs(d)+e_d, slip+e_slip)/(s*world_unit_m)*1e6 + arithmetic_guard_um)`
against E. Fixed-plane reduction uses the same legacy total guard; additional
native uncertainty terms must not be dropped to obtain identical verdicts.
Vertical and local-normal comparisons remain separately named; v1's model error
uses the legacy normal-separation definition, not a new vertical budget.
Whole-mesh penetration remains adverse even outside stance patches.

#### Quantized native target and both endpoint conversions

For finite native measurement only, the target at a real XZ coordinate x may be
the observation `F(Q(x))`: Q is the actual componentwise nearest/ties-to-even
binary32 API conversion, and F is the frozen native method on its native inputs,
including the declared raw/sea/override selection. Define D as the **entire real
uncertainty domain**, including every required vertex, phase, operation, placement
and independently fixed anchor neighbourhood. This interpretation changes none
of that coverage. Let Lambda contain all of `Q(D)` and every nominal query; bind
the coordinate chart, units, method, binary, resources and selection in the proof.
Nonfinite conversions, holes and invalid or ambiguous normalized normals remain
adverse/unavailable; they are not removed to obtain a smaller admissible domain.
Every normal-offset lookup and every region/cell/sea/override branch needed by F
must be covered, even when its stencil extends outside the top-level query box.

A proved output diameter R and positive lower bound delta on the distance between
**any distinct** native coordinates in Lambda imply `L = R/delta`: equal native
coordinates give equal outputs by frozen-method determinism; unequal coordinates
have output distance at most R and input distance at least delta. This requires
range and separation proofs for the whole domain, with outward arithmetic.
For height, R and delta are in world metres and L_h is dimensionless; for valid
normalized normals R is dimensionless and L_n has units 1/m. Normal diameter 2
is usable only after validity, normalization and all required branches are
proved. Stored RF extrema, adjacent-pair quotients or sampled native extrema do
not bound the full method's output arithmetic or normal stencils. If such proof
is unavailable, the corresponding contributor remains null/UNKNOWN.

For intended coordinate p and any true x in its full neighbourhood, let
`||x-p|| <= e_p`, `q=Q(p)`, `q_x=Q(x)`, measured `r=||q-p||`, and prove uniformly
`||Q(x)-x|| <= eta` over that neighbourhood. All norms here are XZ Euclidean norms
in world metres (convert both axes with `world_unit_m`, not per-axis maxima).
Then `||q_x-q|| <= e_p + r + eta`. This bounds the quantized target over **all
real x**, without asserting continuity. The adapter's existing radius is
`rho = e_p + r + query_coordinate + arithmetic_guards`, rounded outward.
`query_coordinate` must include eta plus every other applicable query-coordinate
error, with derivation/evidence and no omitted or double-counted contributor.
Nominal rounding r alone does not include the unknown endpoint's conversion.
Use `height_error = e_h_capture + L_h*rho` and
`normal_error = e_n_capture + L_n*rho + normalization_guard` in the existing
propagation. Position/anchor bounds also retain their full 3D obligations.

The declared surface rectangle is in coordinate units. The adapter conservatively
requires its outward-expanded p-centred box of radius `rho/world_unit_m` inside
that rectangle. Prove that Lambda contains q and every Q(x) in the full real
neighbourhood, including boundary rounding cells; independently prove the F
stencils there. A numeric field or a successful rectangle check cannot establish
those external facts. Anchors need their own e_a, nominal rounding, uniform eta,
native-domain and fixed-normal proof, throughout the interval and its outgoing
exit. A vertex proof cannot substitute for an anchor proof. Sea-switch normal
ambiguity and all existing UNKNOWN/null propagation remain in force.

For example, nearest rounding on a unit lattice with p=7/16 and x=9/16 gives
q=0, q_x=1. For native F(0)=0, F(1)=1 and L=1, omitting eta gives radius
`1/8 + 7/16 = 9/16 < 1`, which fails. Including the uniform eta=1/2 gives
17/16 and encloses the difference. This is a synthetic counterexample, not a
native certificate; the adapter regressions also exercise a binary32 cell crossing.

This target bounds an API observation only. Its discrepancy from rendered
triangles/LOD or physical planted contact is a separate obligation, never zero
by interpretation. No new E, physical PASS, source normalization, replacement
ground, accepted native stream, strict-Gram waiver or continuous-motion claim
follows. Capture retains the actual full-stencil range/arithmetic proofs,
position/anchor bounds, material annotation, native stream and visual acceptance;
all original P4 requirements remain.

### Complete coverage and bounded transport

The frozen workload is `20,880 * 1,300 * 3 = 81,432,000` vertex evaluations,
before anchors and outgoing-interval evaluations. Enumerate every logical request;
reuse an identical query result only for identical native coordinate bits, method
and frozen surface/hash, with every original identity retained. Never deduplicate
approximately, interpolate sparse samples, drop phases or subtract source flags.
All 33,427 edges in each frame still run regardless of query availability.

Use a streamable JSON envelope with a header, ordered `chunks` and final counts/
digests. Each chunk is one line containing base64(zlib(UTF-8 JSONL rows)), bounded
to 4,096 rows, 16 MiB decompressed and 32 MiB encoded line. Split sooner at the
byte cap. Include chunk ordinal, first logical ordinal, row count, decoded byte
count and SHA256 (`chunk_index`, `first_ordinal`, `row_count`, `decoded_bytes`,
`sha256`, `data_base64`). Footer keys are `chunk_count`, `row_count`,
`decoded_bytes`, `stream_sha256`; empty streams use zero counts and SHA256 of
empty bytes. Reject excess decompression, trailing streams/bytes and invalid
rows. Emit header/chunks/footer on separate lines so a stdlib bounded reader
need not load the entire JSON or an entire base64 payload. The ordered stream
digest hashes concatenated uncompressed row bytes including LF; per-chunk and
whole-file digests bind transport too. Define row keys by the request/response
schema above, use sorted keys and compact JSON with LF, and validate exact bytes.
Every response stream binds the full request-stream digest. Verify each row against
regenerated requests; recomputing a digest does not excuse identity mismatches.

Generate/evaluate one frame and bounded chunk at a time, retaining incremental
counts, geometry hashes, extrema and patch/outgoing results. Exact dedup is
optional; without it memory remains bounded. A disk-backed index or ignored
temporary chunks may assist, but no new dependency or tracked evidence path is
authorized. Final compressed response evidence must be embedded in the capture's
existing `contact-input.json` / `contact-provenance.json`, with manifest either
embedded or exactly regenerable from bound inputs; alternatively, those same two
files may bind the immutable SHA256 of
`evidence/locomotion/infantry/contact-evidence-custody.json` and the exact response
file SHA256. This manifest names every byte-bound asset in the same repository's
`evidence-infantry-contact-12c6915d0f528651` Release. Explicit ordered parts bind
the compressed whole and exact decoded byte lengths/SHA256; download all listed
assets into a fresh flat cache and reject missing, extra, duplicate or changed
assets. The offline stdlib `tools/units3d/soldier_arp/pivot_contact_evidence.py`
restores into a new ignored cache with bounded zlib decoding, one strict EOF,
no trailing streams, and safe relative destinations. Historical absolute paths
in opaque evidence never become output destinations; evidence scripts are never
executed. Retain both original baseline JSONs, every nested payload, all native
part boundaries and receipt hashes, all context PNGs, and every source/log/failure
record. Hash checks and complete unmodified C `QueryStream` replay must cover all
original requests/native words/responses, counts and digests; custody is not a
replacement for regenerated geometry or physical acceptance. The original capture
owner alone adopts the accepted manifest reference in its two existing files.
Same-pair Review must first accept the frozen code, manifest and local assets
before implementation publishes those exact assets, then independently fetch and
replay every asset in a fresh unrelated cache. The historical full geometry run
remains failed at its unchanged 2,700-second deadline; strict Gram remains FAIL,
physical uncertainty UNKNOWN and E null. All row/envelope/identity/coverage,
uncertainty/budget, geometry and physical gates above remain required. Reports must distinguish
enumeration completeness from valid-surface completeness and continuous proof.
Interrupted/incomplete streams cannot pass. C must demonstrate bounded memory,
chunk corruption/limits/restart rejection and complete finite counts; if real
storage/runtime is infeasible, return the measured seam/cost rather than sampling,
raising timeouts or promising an unexecuted 81-million-query native run.

### Hand-computed acceptance controls

These are synthetic controls, not physical evidence or authorized E:

1. **Planar reduction.** With identity placement/units, `h=0`, `n=n_a=(0,1,0)`,
   `a=(0,0,0)`, `p=(.003,-.002,0)`: v=d=−.002 m, penetration .002 m,
   slip .003 m, model error 3,000 µm. On any proven plane, `dot(p-q,n)` equals
   legacy `dot(p-g,n)` because q and g lie on it, and the anchor normal is fixed.
   Common rigid transforms of points, plane **and measurement chart** preserve
   error; scale 2 doubles world distances and original s=2 recovers 3,000 µm.
   A coordinate-unit change also changes s and `world_unit_m` consistently.
   Holding the chart fixed through an arbitrary rotation may cease to be a height
   field: no old XZ transcript may be reused as that new surface's observations.
2. **Nonplanar/fixed anchor.** Use `h(x)=0` for x≤0, `h(x)=x` for x>0, z-free.
   Anchor a=(−1,0,0), n_a=(0,1,0); p=(1,.9,0) yields v=−.1 m,
   d=−.1/√2≈−.0707106781 m with n=(−1,1,0)/√2, and slip=2 m.
   At p=(−.5,−.1,0), d=v=−.1 and slip=.5 m. Replacing the anchor by q at
   the first point would spuriously give slip≈.07071 m: reject that reselection.
   At x=0 the ridge has no unique normal; a hole gives no finite height.
   Retain the vertical result where valid, flag missing normal/height coverage.
   At a shared phase boundary evaluate outgoing old anchor and incoming new
   authored anchor separately; do not lose the old anchor's 2 m slip.
3. **Uncertainty.** In the flat control, take justified e_p=.0001 m,
   e_q=.0002 m, e_a=.0001 m, e_n=e_na=0. Then e_d=.0003 m,
   e_slip=.0002 m, error upper bound=max(.0023,.0032)=.0032 m.
   At s=unit=1 and a conservatively rounded arithmetic guard .01 µm,
   ceil(3200+.01)=3201: synthetic E=3200 fails, E=3201 is only
   `WITHIN_FINITE_SAMPLES`. Unknown height/normal bound or absent E is PENDING.
   Placement FAIL makes even a large supplied E ineligible, never within.
4. **Legacy negatives.** The recorded original matrix stays rejected by legacy
   and FAIL in raw mode. B must obtain its complete immutable raw words/scale
   from the original owner as frozen observation evidence, bind the digest and
   include a literal regression witness; the scalar residual alone cannot
   reconstruct it. Test computed Gram residuals immediately below/equal/above
   `1e-10*s*s` with exact comparison operands (and nearby representable matrices),
   not decimal-rounded assertions. Equality passes that predicate only. Known
   shear `[[1,.01,0],[0,1,0],[0,0,1]]` is measured raw but fails uniformity;
   a reflection, zero determinant, NaN, missing provenance or changed raw bit
   rejects. Wrong coordinate/phase/hash, missing or conflicting responses reject;
   sea height with a raw-terrain normal is uncovered, never a planar PASS.

## Serial implementation boundaries after A

Only the sole dispatcher may register/start these steps after actual prerequisite
acceptance. Each has its own worktree/PR/fixed owner pair. Both own exactly
`tools/units3d/soldier_arp/pivot_metrics.py` and
`tools/units3d/soldier_arp/test_pivot_metrics.py`, so they **cannot overlap**.

- **B `LOCO-INFANTRY-RAW-PLACEMENT-METRICS`:** after accepted A/#223/#224 and
  transitive prerequisites. Implement explicit raw placement/report dispatch with
  synthetic fixed-plane support only; preserve legacy API/CLI/errors/outputs.
  Retain exact raw inputs, strict FAIL and world observations; reject malformed
  transforms/provenance. Verify actual-matrix legacy rejection, threshold
  boundaries, shear/reflection, hand arithmetic, unchanged weights/fixture and
  absence of certifying nominal-scale comparisons. No terrain/capture/runtime code.
- **C `LOCO-INFANTRY-NONPLANAR-MEASUREMENT`:** only after B merges/releases the
  same paths, plus accepted A/#223/#224/#225. Implement request generation,
  bounded transcript validation and nonplanar/fixed-anchor metrics as specified.
  Verify planar reduction, two slopes/ridge/hole, outgoing boundaries, units/frame
  controls, typed surface mismatch, tampering/truncation/chunk limits, unknown
  uncertainty, absent E and retained placement FAIL. Test full finite enumeration
  and streaming; synthetic oracle tests do not certify native terrain correctness.

B and C each run targeted Python tests and the frozen full replay on final affected
inputs, retaining original per-variant whole-mesh digests, all 652/563/471 absolute
flags, 103/45 introduced flags and the one mapping-only crossing, fixture integrity
and current-HEAD required CI. No code/fixture/gate changes occur in A. Native
integration belongs to the original capture owner after C acceptance, under its
unchanged [capture acceptance boundary](infantry-pivot-skin-acceptance.md#raw-observation-interface-and-the-active-capture-boundary).
The data round trip is not a dependency cycle: accepted baseline → A → B → C →
resume capture → original clip/CERT/POLICY/CONSUMER order. No A/B/C depends on
unmerged capture/#221, consumes its WIP, starts a successor or claims visual PASS.

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
