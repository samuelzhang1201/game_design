# Infantry pivot feasibility contract and frozen counterexamples

Step: `LOCO-INFANTRY-FEASIBILITY-CONTRACT`, 2026-11-02. Implementation:
`01a198a5-f257-7593-bf83-38c72990c7d2`. Sole dispatcher:
`01a17398-42c1-7583-8d3f-7b15e877586c`. Unique Review: pending assignment by
dispatcher before PR handoff. Base: `3ab0f10d53dee5a473c54ea266f8142ef7cc943a`.
Accepted prerequisites: #202 CF04c locomotion contract, #207 infantry transition,
#216 archer pivot import. There is **no dependency on unmerged #221**.

**Verdict: the conditional zero-separation A–D conjunction below is infeasible;
the original finite-certified-error contact contract is not proved infeasible.
Motion acceptance FAIL; authority decision PENDING.** A counterexample/document
merge does not accept any motion dependency, certify a parameter domain or complete P4.
This step authorizes no change to A–D or existing acceptance. A coupled author
mapper is not dispatchable until feasibility and authority are resolved.

## Frozen scope and provenance

Only this document, `tools/units3d/soldier_arp/test_pivot_feasibility.py`, and
`tests/fixtures/infantry_pivot_feasibility.json` belong to this step. They change
no asset, model, animation, provider, helper, scene, table or runtime.

The read-only proposal is `assets/3D/units/infantry/model_wip/loco_clip/`'s
`prerequisite-proposal.md` in the original infantry worktree, SHA256
`c5f76a472c6933910672e7f0875ea59c8cd55ce4bd29aca4da211c46e6dc7c2f`.
Its manifest SHA256 is
`ff97d2c95b24c0830c3c52e6b06c0e1d796295c8f9aa4c51a52a38eb32ea3a67`.
All twelve manifest files matched their recorded hashes before fixture creation.
They are frozen observations, never imported unmerged product implementation.
Original #221 retains implementation `01a195f7-619e-7362-adaa-aca0a6ad10fc` and
unique Review `01a19882-1896-7103-9cc1-d894fa9ffc58`; neither participates as
a third owner/reviewer here.

The fixture is a lossless container: `sources[path]` records original byte count,
SHA256 and zlib-compressed base64 **original bytes**, without reserializing or
resampling their JSON. It bundles proposal, manifest, native MARCH capture,
combined inputs/results, attribution, contact report and both geometry captures.
The manifest also retains hashes for the other original execution/report files;
their contents are not needed by the replay and are not bundled. Decode with
stdlib `base64.b64decode(value, validate=True)` followed by `zlib.decompress`.
The script pins all nine bundled SHA256s independently of fixture metadata.
A changed/missing source, malformed container or invalid mesh fails closed.

Native MARCH capture hash:
`fa971d07a79dfed75d0ff55fbe3997c3268bc04c9b140f2530517f60ad4e3b60`.
It records Godot 4.7.2 actual AnimationPlayer samples, 1301 exact request IDs,
source GLB hash `67a2a932c4831d154f7bb24eca7c3f91d3a9b0b31e56843733fc6702e6a488b3`
and import hash `30053b147d2096e1a8e72b6927e7d1ec74ec8e3c7c894975991ac2b4af7a1341`.
The original actual-native query exited 0 with no reported errors. This step
reuses that frozen capture; it does not claim a new native execution.
Hex request IDs remain authoritative where Godot decimal JSON rounds one ulp;
lookup is exact, with no nearest phase, interpolation or raw GLB/Blender sampler.

Geometry baseline SHA256
`34bed95c453b4a12ae49b5baa507baa62f909d8ebdc5219f22249f8b7e8790cd`
and contact-provider capture SHA256
`acc6b827b9a1e6752aca91b3b8d3ebfa0c44b8d64803f7fa3c2f3a1b1efc1a94`
contain identical complete surface arrays and named binds. The baseline identifies
the earlier original GLB (`bb1d80b9…`), while the MARCH query identifies the
later source (`67a2a932…`); this is not a claim that these GLB hashes match.
Their unchanged native geometry/binds are compared in full before replay.
No current unmerged GLB or exporter is read by the reproducer.

## What is reproduced

For every vertex, use the captured four packed influences exactly:

`p_v = sum_k w_vk * (G_bone(v,k) * inverse_bind_k * [v,1])`, take XYZ.

There are 20,880 vertices, 83,520 weights/bone indices, 69 named binds and
46,971 triangle indices. No weight normalization, zero-weight influence removal,
vertex omission or bad-edge filtering occurs in LBS. Sorted unique undirected
triangle edges retain the attribution report's native order. The boot mask is
the original per-foot `foot + toes` majority-weight classification; its division
by weight sum selects vertices only, never changes deformation weights.

The replay deforms the **whole mesh on all 1300 mapped frames** from the original
five cases and evaluates every mesh edge. For each flagged frame it also deforms
the whole native same-phase and authored-reference mesh. Native entry/endpoints
use captured global matrices; mapped/reference globals are composed from the
original frozen local poses and their frozen `rest.bones` parent hierarchy.
The mapped pose is the original render-pose result, not a rerun of the helper,
a separately reconstructed source animation or an alternative author mapping.

The unchanged gate is strictly **length > 4 × native-entry length AND > .03 m**.
It reproduces all 471 edge/phase flags, their vertices, packed positive influence
records, positions, four lengths, ratios and native/reference flags. Totals:

- +90°: 8 pairs, at most 1 failing edge in a frame.
- −2°: 326 pairs, at most 3; 45 pairs fail where same-phase native does not.
- −1 microdegree: 137 pairs, at most 3; all also fail in same-phase native.
- The remaining +180° and +1 microdegree cases contribute no flagged pairs.
- Exactly one pair fails beyond **both** native and authored reference:
  −2°, u=.8775, edge 7315: entry .012373079 m, native .049183362 m,
  reference .049483659 m, mapped .049590702 m. The boundary is
  `4 × entry ≈ .049492316 m`; the mapped value alone crosses it.

At −2°, u=.21, edge 6154 joins vertices **2756 and 13448**. Replayed lengths
are approximately .007941776 / .013229979 / .037178051 / .032106760 m
(entry/native/reference/mapped). These are coupled skirt/crotch skin vertices
with left/right thigh_twist/thigh_stretch influences. Independent leg reference
composition creates the large excess before the final solve; the mapper-only
crossing above shows that not all new failures can be assigned to the source
or to reference construction alone. All source-derived failures remain visible.

The original report process exited 0 to **generate a failing report**. That exit
is not contact/skin PASS. Likewise this script's exit 0 means reproduction
MATCH only; its JSON explicitly says `motion_acceptance: FAIL` and
`authority_decision: PENDING`. `--self-check` evaluates no motion acceptance.
The 1e-10 replay comparison tolerance checks floating arithmetic identity; it
does not alter either edge gate or any original contact policy tolerance.

## Conditional zero-separation endpoint/physical ground contradiction

The accepted [CF04c contract](cf04c-locomotion-contract.md) defines
`body_locomotion_<arm>_contact_um` as maximum certified ground-contact error in
integer model micrometres; no arbitrary value is approved. Its per-arm evidence
requires stance sole/hoof world coordinates, normals, separation, slip,
penetration/hover, MARCH transitions and continuous contact/envelope bounds.
It does **not** establish D's strictly zero endpoint separation as an approved
universal P4 acceptance clause. D comes from the frozen prerequisite proposal.
The registered clip acceptance likewise supplies no such zero-error clause.

Here is the conditional conjunction whose incompatibility is demonstrated;
it must not replace that original finite-certified-error contract:

A. Preserve exact imported native MARCH entry and exit matrices, mesh, packed
weights and binds at the admitted phase pair. An endpoint label or anchor may
not substitute for the actual deformed boot surface.

B. Use one phase-independent placement `T(p)=s R p+t`, `s>0`, for the body.
It is the existing placement/seat orientation and ordinary scale, plus committed
yaw. There is no phase-dependent actor offset, height correction or scale.

C. Use one fixed physical plane, with the entry-frame +Y normal. Under common
placement its normal is `n=R*(0,1,0)` and its entry height is transformed with
that same T. A yaw leaves this normal unchanged. Ground/clearance may not be
redefined independently at exit or follow an animated contact marker.

D. **Conditional proposal assumption:** require zero deformed-boot separation
at both endpoints of that plane, rather than the original certified error bound.

Let h0 and h1 be the endpoint minima along entry +Y. Translation and the plane
offset cancel when subtracting their signed separations, leaving
`d1-d0 = s*(h1-h0)`. Thus D requires h1=h0. At .137 → .823:

`.010848789595012797 - .017208295843782147 = -.00635950624876935 m`.

At scale 1 that is −6.35950624876935 mm; at scale 2 it is
−12.71901249753870 mm. Choosing a different common clearance/translation cannot
make both zero. The other two non-seam pairs independently reproduce:

- −2° case: `.015196844203696224 - .013331374454381694`
  `= +.00186546974931453 m` (scale 2: +.00373093949862906 m).
- −1 microdegree case: `.010622999682407897 - (-.0010609559011084519)`
  `= +.01168395558351635 m` (scale 2: +.02336791116703270 m).

The two loop-seam cases retain opposite approximately .356059 micrometre
residuals. They are reported without turning a nonzero value into exact zero.
The first pair refutes this zero-error conjunction. Nonzero minima differences
alone do not refute an unspecified finite contact bound, nor establish which
stance/contact target applies. These samples prove neither feasibility nor
infeasibility of the original continuous finite-error contract and do not compel
MARCH/old-five source changes. No `contact_um` is selected, increased or waived.

This argument is covariant with the **same** rotated plane/body. It does not
claim that arbitrary new body tilt relative to an independently fixed normal
preserves the original Y minima. Such a tilt is outside frozen placement and
needs explicit authority; treating B as arbitrary free tilt would require a
different full-mesh projection proof. No such interpretation is assumed here.
Contact-anchor reparameterization changes neither deformed vertices nor plane.
The Mac lock/window issue is separate from this mathematical contradiction.

## Ownership, promises and pending authority decisions

`Map3DInfantryPivot` explicitly promises detached two-leg reconstruction, not
motion/contact certification. Its endpoint consistency, joint and control-frame
constraints do not promise a coupled-skin objective. The frozen evidence does
not establish violation of its actual accepted invariants; do not silently
expand or repair that helper. The author mapping produced independent left/right
references for vertices influenced by both sides. This is first an infantry
author-mapping/skin-feasibility issue. A coupled mapper might remove introduced
excess; feasibility has not been proved. It cannot repair an immutable native
endpoint that already fails the absolute entry-relative diagnostic.

#221's four product paths remain with its original pair: soldier_arp `pivot.py`
and `game_export.py`, infantry GLB and `.glb.import`. Byte serialization/import
cannot cure incoming matrices. No runtime provider/helper or asset implementation
from that unmerged PR is consumed here. A future mapper needs its own separately
registered literal files after accepted feasibility; this PR creates none.

**Pending decision 1 — authoritative contact/stance interpretation and bound.**
Clarify the original contract's physical stance target and certify its error
bound under the original continuous-domain obligations. This document chooses
no tolerance, source correction, placement change or solver. If authority instead
requires D's strictly zero error in addition to A–C, that conditional conjunction
has no solution at these frozen endpoints. Only under that additional requirement
would preserving C/D require changing A's endpoint source or B's placement.
A source correction would conflict with protected old-five curves; a placement
correction conflicts with protected actor-root/height rules. They remain unselected
conditional options requiring explicit authority and separate registration, not
changes demanded by this evidence or authorized here. Redefining physical ground
to follow the feet is not a solution. Applying the original certified finite
error contract is not a waiver of an already approved zero-error clause: none
has been established. It still requires actual contact certification.

**Pending decision 2 — absolute skin diagnostic at exact native endpoints.**
Preserve the >4× AND >.03 m gate and its failed native cases. A coupled mapper
can address the 45 introduced pairs but cannot pass that absolute diagnostic
at an unchanged failing endpoint. Any source correction or interpretation of
what the diagnostic certifies must be explicit, including the affected original
endpoint/old-five promise and all required revalidation. Excluding edges/phases,
using native failure as a waiver, increasing tolerance or renaming reference
poses as native is not an authorized solution.

The smallest action now is an authoritative contact/stance interpretation and
certification record under the original contract. If an amendment is actually
needed, identify its exact clauses, scope and preserved goals before work.
There is no proposed new solver under unchanged conditional A–D. After an
authorized feasible resolution, a separately registered coupled author mapper would need to prove
whole-skin behavior over the full admitted turn/phase/duration domain, not only
this witness. Physical ground, original numerical gates and all twelve final
goals still require their original acceptance. If an interpretation cannot
preserve them, it must remain pending rather than claim compliance.

## Retained final acceptance and verification

All original tests and thresholds remain, including old-five curves/BIN/import,
skin/binds/rest/gear, exact endpoints, all five cases/four durations/off-grid/seam,
positive affine and deterministic repeat, no input mutation, full arbitrary
phases/turns, ordinary actor/height/scale/R/radius, clock/yaw/save compatibility,
contact/envelope continuous bounds, real-window and original CI requirements.
No reference pair or supported subset completes full P4.

All twelve original design §9 goals remain in full (the original design remains
authoritative):

1. Ten people at full strength; 901→900 displays 10→9, 1→0 displays 1→0;
   conserve personnel and fixed nominal footprint throughout unit lifetime.
2. Ten same-arm people fit with yielding clearance; cavalry mounts/artillery
   do not overlap; opposing flow, three-way crossing, narrow paths, turns and
   reload are clear throughout, with no endless deadlock.
3. Two selected units cannot create a cluster; three can; all eight formations
   test exact eligibility, missing arm, zero-fit, extra and uncontrollable members.
4. Independent speeds without formation; assemble then move at slowest with
   formation; local terrain/injury/supply changes affect budgets immediately;
   detached cavalry is not locked to the army's slowest speed.
5. Undelivered orders preserve old tasks; partial arrivals show; stale orders
   cannot revert versions; actual accompanying king transmits immediately but
   relocation still takes time; disconnected distant units still communicate.
6. Assembly under attack can take casualties, rout and fail; no invulnerable
   stage; joining reinforcements do not penalize the whole stable old line.
7. Expansion retains formation and assigns only additions; changing formation
   physically reforms; partial selection does not implicitly split; cross-cluster
   confirmation/delivery never causes duplicate membership/action.
8. All eight formations have normal, spatially blocked and required-member-loss
   cases; wings actually flank; lure cannot force pursuit; artillery creates
   no fortifications and cannot fire through friendly units.
9. Uncontacted melee cannot deal remote damage; archer/artillery range and
   obstruction apply; explain each bonus's validity; no duplicated charge/flank.
10. Same save/input produces identical state under pause/speed/offscreen and
    mid-substep save; invalid commands never charge twice; old-save people remain.
11. Reproducible equal-input battles compare all eight formations against none
    and test wrong formations being countered, beyond multiplier switches.
12. Real unique-3D-map windows verify full/reduced strengths, friendly crossing,
    enemy engagement, cavalry flanking, ranged fields and attacked reformation;
    browser diagrams do not replace Godot acceptance.

Run from the checkout, with no external evidence directory, Blender or Godot:

```sh
python3 tools/units3d/soldier_arp/test_pivot_feasibility.py --self-check
python3 tools/units3d/soldier_arp/test_pivot_feasibility.py
```

Self-checks exercise hand subtraction, scales 1/2, common translation, strict
AND boundaries, nonunit-weight LBS and corrupt-byte/hash/size/bone rejection.
Two full replay executions must match output and the whole mapped-mesh digest;
fixture bytes must remain unchanged. A malformed fixture must exit nonzero.
No local native/window capture or routine full GUT is needed for these unchanged
frozen inputs. The actual diff selector still governs CI: the JSON fixture
selects functional GUT categories under the existing conservative routing.
Do not relabel/move it or alter the selector to suppress those jobs. All required
current-HEAD CI must pass; absent/skipped/failed/cancelled/timed-out checks are
not success. Retain 2100-second command/75-minute job limits and offline,
parse/runtime, selected-count and expected-error gates. This step claims no
visual PASS, motion certificate, accepted motion prerequisite or P4 completion.
