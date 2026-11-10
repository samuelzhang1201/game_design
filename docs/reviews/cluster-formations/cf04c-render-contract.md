# CF04c candidate render consumer contract

> **Superseded in part (2026-11-10):** the owner rulings in `owner-rulings-2026-11-10.md` win where this document differs (contact bounds, skin diagnostic, certification method, Gram predicate, ownership).

Date: 2026-11-01. This is the bounded `CF04c-contract` documentation step,
not a renderer implementation or production activation. The sole dispatcher is
`01a17398-42c1-7583-8d3f-7b15e877586c`; implementation and its unique Review
own this document PR only. The approved staging decision in PR #187 supersedes
its retained historical DRAFT/wait-for-human wording. It does not waive final
production acceptance. This contract is the implementation author's technical
choice, subject to the unique Review, rather than a dispatcher-designed API.

## Current source boundary

Source baseline: `8ce7f666ec5262d91576dae0ce7242591ea15085` (CF04bR #199).
Dependencies already merged/accepted: CF02 rollout #187, passive foundation,
CF03R planner #192, CF04aR marches #194 and CF04bR placement #199. Their actual
merged contracts/APIs govern; no old WIP, transcript or rejected product patch
is an input. Read `cf02-rollout-boundary.md`, `cf04a-march-contract.md`,
`cf04b-placement-contract.md` beside this file, the approved design §2–3/§9,
plan Task CF04c and staging/real-window sections, and `scripts/map3d/CLAUDE.md`.

Current `Map3DBattleGroups.sample(ctx, code)` admits through `ctx.regiments()`
before reading saved battle groups, returning copied rows. It does not consume
nonbattle bodies or their paths. `Map3DLayerUnits` owns physical child placement,
ordinary predictions, animation and unit-level picks. `Map3DFormation` creates
existing figure scenes. `UnitBodies.rows(repo, state, unit)` copies the unique
owner's rows (nonbattle `body_groups` or live battle `groups[unit]`), preserving
slot/home/path. Empty output alone cannot distinguish invalid rows from a valid
zero-fit unit. `BodyMotion.commit` writes each row's endpoint and `path_m`, and
stores `military_migration.body_motion` version/day/substep/receipt/priority;
these saved control integers are decimal strings. March's outer cursor is
`day_resolution.body_march.next_substep`, the next slice, not the rendered one.
No source currently provides a ready-made candidate render projection. The
projection below extends the existing admitted-copy boundary in the owned
Map3DBattleGroups file; it is not a new engine authority or a new context class.

## Exact candidate entrances and projection

Future product adds these entrances, retaining all ordinary signatures:

```gdscript
# Map3DBattleGroups: admission and copied-data boundary
static func sample_candidate(ctx: Map3DContext, code: String, committed: Dictionary = {}) -> Dictionary
# Pure sampling of the copied projection, no state/context lookup
static func along_candidate(sampled: Dictionary, share: float) -> Dictionary
# Map3DLayerUnits: explicit fixture opt-in, false initially
func set_candidate_bodies(enabled: bool, committed: Dictionary = {}) -> void
```

The fixture binds the existing `Map3DContext.state_fn` to the isolated committed
candidate and then opts in with the successful commit timing envelope described below.
There is no second candidate state argument that
could disagree with sight admission. Neither Map3DView nor any ordinary boot,
Game, save/load, tick, battle or placement dispatcher calls the opt-in before
atomic activation. Tests prove that negative call graph and the default false.
The setter invalidates the render cache and clears candidate display history on
mode changes; it does not modify state or create bodies. Existing `step(delta)`
and `ctx.day_share()` supply the presentation share; delta never advances a
simulation cursor. The fixture drives the candidate clock explicitly.

`sample_candidate` is the only renderer path allowed to query UnitBodies or
saved controls. First require code in `ctx.regiments()` for this same context,
exclude ghost-prefixed IDs and naval units, and determine `ctx.fogged(code)`.
Rejected/ghost codes return `fallback` **before** any body/path/control query.
For a currently observed hostile, whitelist-copy current raw pose fields only;
do not call UnitBodies.rows, which deep-copies paths. Do not read or copy
`path_m`, future orders, destinations or motion receipts. Ordinary
non-DEV sight never grants enemy route visibility. DEV uses its explicit
existing admission, but cannot change simulation. No renderer traverses the
hidden roster to precompute or hash paths. Generic ghosts and fleet counters
keep their existing presentations.

For admitted land units with initialized current bodies, validate the raw
owner/schema/count/unique slot and home-slot facts before accepting the copied
`UnitBodies.rows` result. Do not run migration, reconcile, placement, planner or
commit as a query. Do not treat `[]` as valid unless raw rows are an Array,
fit is zero, and the initialized version/ownership is valid. Check positive
count bounded by saved group size, total equals admitted active fit, canonical
ceil count (0..10), nonnegative stable slot, home_slot 0..9 and facing 0..359.
Missing current required fields or conflicting owners are invalid, never a
legacy fallback manufactured by the renderer. Absent uninitialized legacy
bodies retain ordinary fallback until activation's compatibility path exists.

Exact result keys (deep copies, JSON-compatible except `along_candidate`'s
transient float coordinates):

```text
{mode: "bodies" | "fallback" | "invalid", error: String,
 unit: String, moving: bool,
 cursor: {} | {version: 1, abs_day: int, substep: int, receipt: String},
 rows: [{slot: int, home_slot: int, count: int, role: "front"|"reserve",
         x_m: int, y_m: int, facing_deg: int, path_m: [[int,int], ...], budget_m: int}],
 key: Array}
```

Fallback/invalid have empty rows/cursor and moving=false; invalid has a
nonempty diagnostic. There is no partial-unit publication. A visible hostile's
path is synthesized as its single admitted current point, cursor={}, moving=false;
this does not read its hidden saved path. An initialized stationary own unit
without motion similarly has a one-point path. `key` includes mode/error/unit,
all projected rows and projected cursor, never hidden values or camera pose.
Cache changes on same-day count, ownership transfer, path, facing, admission or
receipt changes. Candidate invalid suppresses that unit's candidate physical
figures/hit boxes, exposing the error to test/developer evidence; it must not
fall back to guessed slots, stale paths or a misleading full-strength figure.
Ordinary dispatch's existing legacy policy remains unchanged.

## Committed path and cursor semantics

For an own/DEV moving unit, validate nonempty integer point arrays and that the
last point equals the authoritative row x_m/y_m. Read only the latest committed
BodyMotion receipt with version 1, nonnegative integral decimal day/substep,
nonempty receipt and valid saved identity priority. The projection canonicalizes
those known string controls into integers; it does not coerce malformed floats,
nulls, fractional strings or future versions. For an active body-march boundary,
its day must agree and inner substep must equal outer next_substep minus one.
An uncommitted next slice, missing receipt with requested multipoint playback, stale or
inconsistent boundary is invalid. Before the first committed slice, present
current points only. A stationary body participating in a committed slice may
have a one-point path with the same cursor as moving peers.

One projection represents **one already committed slice**. share is the finite
normalized presentation fraction of that slice, clamped to [0,1]; NaN/Inf is
invalid. It is not the absolute day fraction across all saved substeps. The
fixture derives local share from its existing day clock and known substep_count
and presents each committed slice in order, committing the next candidate only
at the next slice boundary. It must not commit a whole day then animate only the
last slice. This fixture clock is a test driver, never a second production clock
or a new persisted cursor. At activation the real bridge must provide the same
slice-local mapping; activation cannot simply pass whole-day share unchanged.

The optional `committed` input is a transient, trusted fixture-driver envelope:
`{cursor:{version:1,abs_day:int,substep:int,receipt:String},
 moves:[{unit:String,slot:int,budget_m:int}, ...]}`. The driver constructs it
only after a successful commit, using exact retained plan data:
`BodyMotion.commit(repo, candidate, proposed, boundary)` returns only status/reason;
retain `proposed.moves` and bind `BodyMotion._hash(proposed)` to the resulting
saved inner receipt. For `ArmySystem.commit_body_march_candidate`, the returned
plan is `result.plan`; use `result.plan.motion.moves` and bind
`BodyMotion._hash(result.plan.motion)` to `result.candidate.military_migration.body_motion.receipt`.
The envelope's day/substep come from that same motion plan's cursor. Verify
success and exact receipt equality before filtering moves through ordinary
sight admission; include only own/DEV admitted units. No new engine API is needed. It supplies no positions or replacement
paths. Receipt must equal the saved inner motion receipt and every sampled
moving identity must have exactly one nonnegative integer budget. No duplicate
identity or mixed cursor is allowed. This envelope is presentation timing from
an already committed plan, not an engine state writer, new saved authority or
renderer-generated plan. Never derive budgets from camera speed or path length.
A saved receipt does not persist per-body budgets, so after load without this
same successful-commit evidence, draw endpoints only. A caller cannot claim
in-slice playback from saved path/cursor alone. Activation must explicitly
supply successful-commit timing through its separately owned bridge.

`along_candidate` returns the same mode/error/unit/cursor and rows with original
identity/count/home/facing plus `x_m`/`y_m` as transient floats. It uses the exact
BodyMotion._segments timing: each leg duration is ceil(Euclidean length) divided
by that body's committed budget_m, followed by a stationary tail to share=1.
Interpolate linearly within each leg. This matches the planner's actual relative
sweep; normalizing every body's total path to the whole slice would change
collision timing. For [[0,0],[3,0],[3,4]], budget=7 and share=0.5 gives (3,0.5),
not (1.5,2). With budget=10, share=0.5 gives (3,2); it reaches the endpoint at
0.7 and waits. Diagonal legs use the same ceil timing as the planner, not a new
Euclidean-normalized timeline. Reject total ceil leg cost > budget or moving
path with zero budget. Repeated points cost zero; one-point/all-zero paths stay
at their endpoint; endpoints are exact. It never changes saved integers or
returns deltas. All peers use the same slice fraction with their own committed
budgets; independent per-body springs/lag/easing cannot distort collision timing.
Preserve fractional positions throughout conversion:
`pack_px = Vector2(row.x_m, row.y_m) / float(ArmySystem.metres_per_pack_px(repo))`,
then `xz_world = ctx.to_world(pack_px)`. Do not call `metres_to_pack` here: its
Vector2i argument would truncate interpolated metre coordinates. Do not round
to integers before terrain seating or hit-box projection.
Use per-row saved facing; keep upright ground seating and ordinary reference
scale. No anchor translation, corner shortcut, terrain snapping in XZ, camera
heading, visual separation or fabricated swept detour is permitted. Facing is
the committed per-row value; this step does not invent an uncertified rotation
trajectory. Continuous turn clearance still needs real-window verification.

With matching successful-commit timing, a new receipt selects its new path at share=0. Repeated receipt,
refresh, pause, FPS change and JSON reload never replay a completed slice.
On first bind/rebind/load without an explicitly supplied in-slice fixture clock,
show the committed endpoint; do not restart an old saved path at zero. The
existing production clock/save boundary is not altered in this candidate step.
Transfer changes owner storage, not identity: key child nodes by (unit, slot),
not battle ID, array index, count, home_slot or receipt. Preserve surviving node,
model, animation phase and shown pose across nonbattle -> battle -> merged
battle -> nonbattle transfers; do not rebuild on storage-owner changes alone.
Retired slots never renumber/reuse; 1000/901/900/1/0 fit shows 10/10/9/1/0.
A subsequent legitimate receipt starts at the previous endpoint; mismatched
continuity is a reported invalid input, not an interpolation bridge across a gap.

## One bounded future product scope

Proposed product is one separately registered step, dependent on accepted merge
of this document and the above planner/march/placement prerequisites. Only the
original dispatcher may register/start it with a new implementation/Review pair.
This document creates no session, claim or product authorization by itself.
Exact proposed owned files:

- `scripts/map3d/map3d_battle_groups.gd`: admitted projection, pure polyline
  sampler and reuse of existing child sync/place/evidence.
- `scripts/map3d/map3d_layer_units.gd`: explicit default-off candidate seam,
  copied-projection cache, identity-preserving update and slice sampling.
- `scripts/map3d/map3d_formation.gd`: only if needed to reuse the existing
  one-figure construction without tier/index identity; no new asset/layout.
- `scripts/map3d/CLAUDE.md`: actual current candidate rule once implemented;
  this is the existing indexed location, no new topic guide is authorized.
- `tests/map3d/test_body_paths.gd` and its `.gd.uid`: red/green contracts.
- `tools/map3d/body_paths_fixture.gd` and its `.gd.uid`: one explicit windowed
  SceneTree fixture/capture/measurement entry. This necessary addition keeps
  GUT's test base separate from the real-window main loop. Reuse existing map
  world/layer and benchmark helpers, bind an isolated candidate, and explicitly
  opt into the candidate seam; take --map and existing quality/resolution inputs.
  No production call site or persistent fixture framework. The future dispatcher
  must register these exact added paths and this reason before product Start.

Use worktree-local ignored evidence staging and existing snapshot/bench
helpers; no committed scene/resource/config/UI bridge, new renderer or
engine mutation is part of this scope. If the single driver needs more owned
files, stop before implementation and have the dispatcher register a specifically
justified addition or separate bounded dependency. Do not silently expand into a catch-all fixture
framework or reduce the real-window gate. No .tscn/.tres look edit is needed;
any actual look edit requires separately registered scope and gdai editor.

## Product verification and acceptance

First red then green `./run_tests.sh --test tests/map3d/test_body_paths.gd`:

- L-path hand calculations above, unequal body budgets and early stationary
  tails compared with BodyMotion._segments, missing/mixed timing envelopes,
  zero-length/duplicate/negative coordinates,
  fractional world output: L-path (3,0.5) must equal
  ctx.to_world(Vector2(3,0.5)/float(ArmySystem.metres_per_pack_px(repo)))
  and differ from the truncated (3,0) result in nondegenerate map metadata,
  exact endpoints, invalid nonfinite shares, malformed controls/paths, rejected
  incomplete ownership/counts, and mutation of returned copies leaves source intact.
- 0/1/9/10 figure identities, 901->900 and 1->0 survivor node identity/phase;
  transfer through all owners without pose/scale flash, frozen/rejected transfer
  leaves source and view unchanged. No array-index resurrection or slot reuse.
- Two opposing and three crossing planner-committed candidates, detour and
  turning, multiple slices and receipt retry/JSON resume. Sample intermediate
  points densely and at segment boundaries, check fixed measured envelopes;
  an endpoint-only assertion cannot certify full swept or rendered clearance.
- Own/admitted foe/unseen foe/ghost/naval/DEV matrix. Instrument body/path
  access to prove unseen/ghost lookup count zero, observed hostile saved-path
  lookup zero, and changing only a hidden path changes neither result nor key.
- Identical candidate inputs at pause/1x/4x, near/far/offscreen and differing
  FPS/delta partitions produce equal simulation state/RNG hashes, personnel,
  supplies, costs and saved receipts. View sampling is read-only. Assert no
  ordinary caller reaches candidate opt-in/API before activation.

Run unchanged `test_map3d_units.gd`, `test_map3d_battle_groups.gd`,
`test_map3d_preview.gd`, `test_map3d_editor_owned_look.gd`, and the relevant
unit-body/motion/march/placement regressions on frozen inputs. Use the shared
Godot lock, affected selector and all required current-HEAD CI. No routine full
local suite; explicitly opt in to any required gameplay-classified suites.

Candidate acceptance **requires** visual-review in a real Godot window on the
unique 3D map: before and at least two variants, full window and 3x crops,
unique Review's independent eight-axis critique, continuous recorded opposing
passage/three-way crossing/L-detour/turning, near/far, pause/1x/4x and frame-rate
variation, full strength and reduced strength, each arm using CF01 measured
production radius/scale. Check entire motion for penetration/hover/slide/identity
flash, not just endpoints. Preserve actual input/HEAD/commands/window resolution,
clips, measurement output and failed variants in evidence. Use existing
snapshot_screen real-window workflow; never headless 3D or browser substitutes.

Performance uses existing `tools/map3d/bench.gd` tier/size/budget settings,
near/middle/far, still and --pan, candidate fixture and ordinary baseline at
identical inputs. Record mean/median/p95 and render/engine work, no lowered
budget/hidden armies/reduced radius to pass. Candidate benchmark must explicitly
opt in to the seam, otherwise the existing bench measures ordinary dispatch
and is not evidence. A fixture-driven equivalent using those same tier budgets
must report its exact setup. Missing local window means acceptance is pending,
not merged-as-visual-PASS. Atomic activation repeats these visual/performance
checks in the actual live world with the production clock and all writers.

## Retained end-state obligations

Inherited frozen run: 437 scripts/4504 tests, 4443 pass, **55 fail and 6
risky/pending**, exit 1, FAILED runtime gate, input SHA256
`19bd7a5b9deb50a1bb1820aac2348e9e20adb8400484d1e3ab6e0729da2fbfb5`.
This document resolves none: UNKNOWN/cascades, actual road contact, defeat
continuation, current-campaign placement/save/load and ranged eligibility remain
obligations of their owning steps/activation. CF01 covers only 17 pose samples
and the explicitly allowed artillery infantry placeholder; CF08 is pure layout,
not eight playable formations. No inherited failure or pending item becomes PASS.

All twelve design §9 gates remain: (1) ten/count/fixed footprint; (2) real-radius
sweeps/yield/turn/reload; (3) eligibility for eight formations; (4) independent
speed/assembly/local budgets; (5) real command delivery/version/king position;
(6) vulnerable assembly/stable existing line; (7) expansion/reform/partial
selection/unique membership; (8) eight normal/blocked/member-loss behaviors;
(9) physical contact/fire/occlusion/explained nonduplicated bonuses; (10)
save/speed/camera determinism/cost/personnel compatibility; (11) reproducible
formation-vs-none and countered outcomes; (12) actual 3D-map real-window visual
and performance acceptance. Battle/damage and final atomic activation remain
later dependencies, not implied by render success. Activation must switch all
writers together, validate legal old saves and real new-game roundtrip, preserve
files/state on failure, resolve all inherited red/pending results and repeat
live-world visual/performance acceptance. CF04 original production completion
requires a/b/c and activation acceptance, not merely staged candidate merges.

This document PR checks source/API traceability, precise future scope, preserved
acceptance, whitespace/selector/harness/config/guide checks, unique independent
Review and required current-HEAD CI. No Godot, visual or performance PASS is
claimed by this documentation step.
