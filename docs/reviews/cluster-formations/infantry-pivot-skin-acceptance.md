# Infantry pivot skin diagnostic applicability and physical disposition

> **Superseded in part (2026-11-10):** the owner rulings in `owner-rulings-2026-11-10.md` win where this document differs (contact bounds, skin diagnostic, certification method, Gram predicate, ownership).

Step `LOCO-INFANTRY-SKIN-ACCEPTANCE`, 2026-11-02. Sole dispatcher:
`01a17398-42c1-7583-8d3f-7b15e877586c`; implementation:
`01a19930-a43c-7420-9403-335b15424f4a`. Unique Review is assigned by that
dispatcher before PR handoff and recorded in the PR/checkpoint. Dependencies:
accepted #202 `CF04c-locomotion-contract`, #207 `LOCO-INFANTRY-TRANSITION`,
#223 `LOCO-INFANTRY-FEASIBILITY-CONTRACT`, #224 `LOCO-INFANTRY-METRICS`.
There is no dependency on unmerged #221 or on final CERT.

**Decision: adopt the proposed applicability and evidence procedure below.
No current flag receives physical PASS. Motion remains FAIL/PENDING.**
Authority is the user's full-P4 instruction, quoted in the dispatch as
“我批准你的所有建议，不要问我，完成所有实施”, applied to this exact proposal
by the dispatcher's initial bounded assignment and explicit Start. It authorizes
this procedure and actual measurement/correction work through separately registered
steps; it supplies no missing physical evidence, contact budget or certificate.
The original #221 pair supplied frozen facts only and is not a third participant.

## Binding applicability decision

Keep evaluating and reporting the strict absolute diagnostic on **every**
source, authored-reference and mapped frame:

`length > 4 * native_entry_length AND length > .03 m`.

The denominator is that same case's actual native ENTRY edge length. Bind-space,
mesh-coordinate and same-phase source lengths cannot replace it. Keep all
20,880 vertices, four raw packed influences per vertex, 69 named inverse binds
and 33,427 sorted unique edges. No weight normalization, edge/vertex filtering,
phase omission or subtraction of native failures is permitted. The CF01 sword
body mask is an envelope measure only; it cannot filter this skin diagnostic.

The numeric gate and every absolute adverse observation remain binding evidence.
Source equality alone never exempts an edge or produces physical PASS. An
inherited source flag requires individual adjudication against the original
physical geometry/contact/envelope and actual-window outcomes. It remains
adverse until those requirements are met and independently reviewed. A record
labelled only “baseline”, “inherited” or “case by case” cannot clear it.

The diagnostic is a hazard signal: its entry-relative ratio alone does not prove
physical penetration, loss of contact or safe skin. Original design §9/§10,
[CF04c](cf04c-locomotion-contract.md) and
[the transition contract](../../../scripts/map3d/guide/infantry_pivot.md)
contain no pre-existing universal zero-absolute-flags requirement at all protected
native endpoints. This applicability decision does not delete or lower the
numeric gate, treat native motion as automatically safe, or waive the original
physical outcomes. The absolute result and physical disposition must remain
separate fields; a later physical adjudication cannot rewrite a flagged result
as a numeric pass. Where actual defects remain, motion fails.

The [accepted feasibility record](infantry-pivot-feasibility-contract.md) and
[metric contract](infantry-pivot-metric-contract.md) remain unchanged. Preserve:

- 471 mapped edge/phase flags, 45 introduced relative to same-phase source,
  and one crossing beyond both source and authored reference.
- The complete scan's 652 source, 563 reference and 471 mapped absolute flags;
  103 reference and 45 mapped introduced flags; one mapping-only crossing.
  Source/reference flags in frames with no mapped flag must still be included.
- All five frozen cases and their full frame sets, old-five curves/BIN/import,
  skins/binds/rest/gear, native endpoints and uncontrolled locals, original
  reach failures, full arbitrary phases/turns/durations, actor root/Y/seat,
  scale, R, ground and existing radius. No helper, metric, geometry, raw weights,
  CSV, runner, selector, test or runtime change is authorized by this document.

The 45 introduced mapped flags, including the one mapping-only crossing, remain
mapper blockers. They cannot be accepted by source attribution or the inherited
flag procedure. Both authored references and final helper output require audit;
eliminating a reference defect alone cannot establish a clean final solve.

## Exact endpoint witness and its limited meaning

At +90°, native entry phase .137 and exit .823, edge 23264 joins vertices
13493/13494. Frozen lengths in native model metres are:

- Native entry: `.012666906066611604` (12.666906 mm).
- Native exit: `.05493455191032237` (54.934552 mm).
- Authored exit: `.054934551910322295`; mapped exit: `.054934541618954204`.
- Four-times boundary: `.050667624266446416`, also below the native exit;
  the exit exceeds `.03 m` as well.

Thus `4 * 12.666906 mm < 54.934552 mm`: this immutable endpoint is absolutely
flagged. Preserving this endpoint and requiring zero absolute flags at every
endpoint cannot both hold for this finite predicate. This is a conditional
predicate fact, not a proof about zero contact, an unspecified `contact_um`, or
the feasibility of the original finite-error physical contract. No source or
endpoint amendment is selected here.

The same vertices' captured mesh-coordinate distance is
`.052114500886000656 m` (52.114501 mm). Opening a folded entry configuration
can explain the ratio; that distance cannot replace the entry baseline, prove
safe topology/contact, or remove the flag. The endpoint's physical disposition
is **PENDING**, with adverse numeric evidence retained.

At −2°, u=.21, edge 6154 has entry/native/reference/mapped lengths approximately
7.941776/13.229979/37.178051/32.106760 mm. At u=.8775, edge 7315 has reference
49.483659 mm and mapped 49.590702 mm against a 49.492315 mm boundary. The latter
crosses only after the solve. These introduced failures remain **FAIL**;
neither source preservation nor the endpoint observation resolves them.

## Required per-flag disposition record

Future measurement/correction evidence must provide a reproducible record for
the union of **all** source/reference/mapped flagged edge/phase pairs, including
source-only and reference-only pairs. Preserve each pair's identity even when
records share a linked capture or proof. A summary count or one representative
crop cannot stand for unexamined pairs. Each record must contain:

1. **Identity and frozen inputs:** case, signed microdegree turn, duration,
   exact operation phase and native request ID, edge index, vertex IDs, variant
   membership, native entry phase/length, same-phase native/reference/mapped
   lengths and both strict comparisons. Link source/GLB/import/scene/gear,
   hierarchy/binds/mesh/raw-weight, placement and report hashes. Distinguish
   historical GLB identities; do not claim their different hashes match.
2. **Attribution without clearance:** source/reference/mapped absolute booleans,
   introduced booleans and mapping-only membership. Include affected vertices'
   raw influences and deformed positions. Retain original failed rows and
   prior candidates when later input or mapping changes; link the replacement
   measurement and the precise change rather than overwriting history.
3. **Actual material geometry:** identify the flagged skirt/crotch/boot or other
   material region, its incident triangles and nearby surfaces/gear/body parts.
   Record deformed geometry and intersection/separation findings with method,
   coordinate frame, units and conservative uncertainty. Inspect both the
   region and adjacent surfaces through entry, flagged phase, neighbours, exit
   and any intervening extremum. A long edge alone proves neither a tear nor
   absence of folding, inversion, self-intersection or interpenetration.
4. **Independent contact provenance:** identify unchanged actual scene/terrain
   placement, fixed physical ground origin/normal and their capture provenance;
   authored fixed sole/toe material patches, stance intervals and planted
   anchors; interval entry and both outgoing/incoming exits. Label any human
   source/material annotation honestly. Supply source/reference/mapped signed
   separation, penetration, hover and tangent slip, whole-mesh penetration,
   uncertainty and any independently authorized finite budget using #224's
   units/conversions. No animated-minimum plane, per-frame vertex reselection,
   mapped-output-fitted anchor or fabricated zero uncertainty is admissible.
   A fixed planar sample covers only its proven physical domain; nonplanar
   terrain remains an explicit obligation. Missing provenance or budget stays
   PENDING; `WITHIN_FINITE_SAMPLES` does not certify continuous contact.
5. **Envelope and continuity:** link conservative full-yaw, whole-deformed-mesh
   bounds against the unchanged radius and actual neighbouring-body clearance;
   continuous parameter/phase/interval coverage, margins and independent adverse
   checks. Include native-to-pivot-to-native full-skin endpoint residuals and
   neighbouring contact/geometry continuity. Finite secants or zero errors in
   1,300 samples do not prove derivative matching or the continuous domain.
6. **Actual equipped native-window evidence:** immutable capture IDs/hashes,
   exact model/scene/terrain/placement/operation settings and matching phases.
   Show source and mapped motion continuously, with flagged-region and native
   sole/toe crops plus full equipped silhouette and near/far views. Include
   pause/1x/4x and FPS evidence with the visual-review variants/crops and the
   step's unique independent Review. Identify any occlusion or missing view
   as missing evidence. A static favourable frame, skeleton markers, headless
   report or browser diagram cannot substitute for the actual Godot window.
7. **Decision and accountability:** separate immutable numeric `FLAGGED` results
   from physical `PENDING`, `FAIL` or a future evidence-backed `ACCEPTED`
   disposition; name the physical requirement, observations, linked evidence,
   uncovered domain, corrective action if needed, implementation and unique
   Review, decision date and reviewed input/commit hashes. No current row is
   adjudicated ACCEPTED by this document. Record a precise unresolved condition
   whenever required evidence or authority is missing.

## Conditions for leaving FAIL/PENDING

All inherited absolute flags currently remain **PENDING physical disposition**
and adverse; introduced mapping defects remain **FAIL**. Other absent ground,
stance, uncertainty, budget, continuous envelope/contact and window evidence
remains **PENDING**. These statuses do not turn the overall motion result green.

An inherited flag can receive a future physical ACCEPTED disposition only when
its complete record establishes the original physical requirements throughout
the affected continuous domain: no prohibited physical/visible defect or
interpenetration, certified contact within an independently authorized bound,
unchanged-radius envelope/clearance, native transition continuity and matching
actual-window acceptance. The unique Review must independently assess those
claims and their limits. The numeric flag remains visible. If evidence shows a
physical defect or an exceeded authorized bound, record FAIL and the exact
correction needed; if any proof, capture, authority or domain is absent, retain
PENDING. A procedural merge alone satisfies none of these conditions.

The introduced 45 and mapping-only one require an actual feasible author-mapping
correction and full final-helper skin validation, with all newly introduced
failures addressed under unchanged inputs/gates. Source/reference/mapped totals
for each new candidate must be reported alongside frozen failures, without
excluding phases or hiding source flags. A finite clean candidate still needs
continuous reach/contact/envelope and window acceptance. No mapper is installed
or accepted here. If constraints conflict, return the exact witness and clauses
to the dispatcher; do not silently change a source, helper, endpoint or tolerance.

## Executable follow-up boundary, not implementation

The frozen proposal's real-capture goal is:

> supply the independent physical input that accepted224 is missing, and a replayable capture linking its fixed plane/placement/material stance data to unchanged actual source/scene/terrain.

Its six proposed capture paths are `tools/units3d/soldier_arp/pivot_contact_capture.gd`
and `.gd.uid`, `tests/map3d/test_infantry_pivot_contact_capture.gd` and `.gd.uid`,
plus `docs/reviews/cluster-formations/evidence/locomotion/infantry/contact-input.json`
and `contact-provenance.json`. The proposal requires actual independent ground,
unchanged placement, fixed annotated material stance and justified uncertainty;
run #224 without a budget as PENDING. It explicitly says:

> If an existing adapter cannot expose those inputs without runtime edits, return an exact seam dependency before adding a seventh path.

The separate correction proposal names only
`tools/units3d/soldier_arp/pivot_mapping.py` and `test_pivot_mapping.py` and states:

> Evaluate both authored reference AND final helper pose on full native LBS.

Its existing boundary requires joint both-leg mapping, removal of introduced
failures, continuous domain construction/bounds and retained inherited flags;
it permits no source/old-five/endpoint/uncontrolled/contact-height/ground/scale/R
or threshold change. These quotations identify the already proposed work;
this document designs no successor algorithm and starts none of those paths.
The sole dispatcher must reconcile dependencies and literal ownership before
starting either bounded step with its own fixed implementation/Review pair.
Original #221 and accepted #223/#224 owners are not additional participants.

Acceptance of this document permits actual measurement/correction work under
those registrations. It does not make contact or motion an accepted dependency.
Capture/construction evidence feeds the original clip step, then independent
`LOCO-CERT-INFANTRY`, then POLICY/CONSUMER. Final CERT is not a prerequisite for
these measurements or #221's candidate construction: no #221 → CERT → #221
cycle. Final certification remains independent and cannot be replaced by this
document, a report-reproduction merge or finite candidate measurements.

All twelve original [design §9 acceptance goals](../../superpowers/specs/2026-10-25-cluster-formations-design.md#9-实施验收清单尚未执行)
remain required in full, as enumerated in #223; no supported subset completes
P4. This includes actual 3D-map/window/FPS acceptance and all original simulation,
formation, contact, clearance, command, battle and save/determinism outcomes.

## Raw observation interface and the active capture boundary

`LOCO-INFANTRY-PHYSICAL-INPUT-CONTRACT` (A), implementation
`01a19bd9-7ce0-7ca1-a857-5b14507aee7b`, owns this addition and the
[versioned external interface](infantry-pivot-metric-contract.md#versioned-raw-observation-contract-a-implementation-pending).
Its sole dispatcher is `01a17398-42c1-7583-8d3f-7b15e877586c`; unique Review is
recorded before handoff. Prerequisites are accepted CF04c/#223/#224/#225.
This is a documentary interface decision, not completion of the active capture.

The original capture owner's frozen **2026-11-02 Astra boundary decision**,
`cluster-infantry-contact-capture/game_design/HANDOVER.md`, SHA256
`40cc4a7fa1a7c8b411b6a35bdce5e5437c7f0c48028c91d76b05411f6dd05743`,
supplies failure facts and an interface proposal only. A imports no unmerged
capture/#221 code, artifacts or source changes. Its strict placement witness
`1.0525859445735615e-7 > 1e-10` remains FAIL. An invertible positive raw matrix
can yield actual world observations without satisfying uniform placement;
legacy224 still rejects it. No fitted matrix, alternate scale, benign-rounding
assumption, raised threshold or nominal-scale model budget PASS is authorized.

The compatibility decision is additive: #224's legacy physical path and #225's
physical acceptance requirements remain binding. A v1 adverse report can be
linked in a per-flag record as measurement evidence, **never as a replacement
disposition**. Item 4's fixed origin/normal describes the proven planar sample;
its explicit nonplanar obligation is represented in v1 by a frozen independent
surface and actual per-coordinate native queries. Fixed material vertices,
authored intervals, independently planted anchors and each anchor's normal stay
fixed; the query under a moving vertex does not move the physical anchor.
Do not apply a fixed plane beyond its proven domain or relabel holes, sea-clamp,
override or queried-height/rendered-LOD differences as covered terrain.

| Original active-capture requirement | What an interface report can supply; what remains required |
|---|---|
| Actual unchanged source/scene/terrain/placement and native identity | Byte-bound raw inputs and strict predicate outcomes. The original capture owner still proves actual installed identity, original placement and native capture provenance; synthetic fixtures do not supply it. |
| Fixed annotated sole/toe patches, intervals and anchors | The schema carries all identities and outgoing/incoming boundaries. Candidate vertex lists or two footfall phases do not establish authored full stance intervals; missing annotations cannot pass capture. |
| Justified capture/material/terrain uncertainty | Explicit bound terms and outward propagation. Null is honest missing evidence; neither observed survey maxima nor float32/double disagreement supplies a conservative bound. |
| Actual-input adapter result, compatible224 measurement | Versioned results preserve the legacy gate and units, plus distinct raw-world/nonplanar fields. A generated adverse report can satisfy only the result-generation component. An exit-0 replay without real inputs or an empty PENDING shell still fails capture acceptance. |
| Actual planar coverage and explicit nonplanar/continuous obligations | Full finite query enumeration and typed coverage defects are recorded. Sparse rest probes, finite vertices or queries alone cannot prove rendered geometry, triangle interiors or continuous swept coverage. |
| Actual equipped native-window stance/flagged variants, crops and unique Review | Still required in the original capture pair. No report, document merge, synthetic test or headless render substitutes for these checks. |

Thus A does not rewrite the active capture's immutable registered acceptance,
dependencies, owners or failed evidence. The entire original six-file task still
needs real independent evidence and its own verification/Review, not merely
VALID/GENERATED statuses. Missing E continues to be PENDING as originally allowed;
missing material annotation, uncertainty or window evidence is not completion.
Any future claim that capture must now pass despite one of those missing facts,
or that its matrix must be declared uniform to satisfy “compatible224”, is an
exact acceptance conflict: return the clause and witness to the dispatcher before
changing a gate. This interface grants no such interpretation or waiver.

All per-flag items 1–7 and Conditions for leaving FAIL/PENDING remain in full.
The 652/563/471 absolute flags, 103/45 introduced flags, one mapping-only crossing,
all 20,880 vertices/four raw weights/69 binds/33,427 edges and strict 4× AND .03 m
predicate remain. Actual defect evidence is FAIL; missing physical proofs remain
PENDING. A finite budget upper comparison is at most WITHIN_FINITE_SAMPLES,
eligible only under the separately stated gates; no raw report yields physical
ACCEPTED or complete motion PASS. Inherited flags still need the original
continuous geometry/contact/envelope/native-window adjudication. Introduced
defects still need actual mapping correction and full final-helper validation.

The [literal B/C paths and serial checks](infantry-pivot-metric-contract.md#serial-implementation-boundaries-after-a)
are bounded Python follow-ups, not launched here. After their accepted merges,
the same original capture owner may resume its six files with new-input checks;
the dispatcher records readiness through the supported workflow without replacing
immutable acceptance. The native oracle round trip is data flow, not an A/B/C
dependency on unmerged capture/#221 or future CERT. Final clip → independent
CERT → POLICY → CONSUMER and all twelve original P4 outcomes remain unchanged.

## Evidence provenance and verification scope

The read-only proposal is original #221's ignored
`assets/3D/units/infantry/model_wip/loco_clip/awaiting-prerequisite-resolution.md`
in the `cluster-loco-clip-infantry` worktree, SHA256
`f7323b6cf0de932fe7f1876e61d63c37d55c1cdcbb7feaa841e3c128436ec4e6`.
Its sibling `edge-provenance-review.md` fact-checks the frozen observations and
proposed boundaries, granting no disposition. The earliest retained diagnostic
executable identified there is `transition207/skin_audit.py`, SHA256
`11fb95f5d4a0855566a7314d8c76cc9397de0b3473d6c20d7d4851bf985e5e78`;
this does not establish all historical origins. The executable frozen inputs
remain the accepted #223 fixture, SHA256
`e1f2a783bff16aa3371823d5844c195634ac7ae0d9be21fd0692a9e1aceb10c5`,
and accepted #224 reports/contracts. No live unmerged implementation is consumed.

This one-file procedure change needs documentation/link/scope checks and the
existing Python/hook/config/guide checks. All required CI must pass on the
actual PR HEAD; missing, failed, cancelled, timed-out or improperly skipped
required checks cannot count as success. Unchanged frozen replay evidence may
be reused with its hashes. No routine Godot/full GUT or new replay is needed
to record this decision, and none would supply the missing physical acceptance.
