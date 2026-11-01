# CF04c locomotion prerequisite contract

Date: 2026-11-01. Step: `CF04c-locomotion-contract`. Scope: this new document
only. Dispatcher: `01a17398-42c1-7583-8d3f-7b15e877586c`. Implementation:
`01a195ee-2805-7270-a65c-cd6431c9c85d`; its unique document Review is recorded
in the PR/checkpoint. This is a technical proposal to be independently reviewed,
not implemented engine behavior, a product dispatch, or visual acceptance.

## Inputs and reason for the prerequisite

Source baseline is `391f48adda4894ca453fa78a1e5c9bb2d63b560b`. Accepted
dependencies are #200 (candidate render contract), #192 (planner), #194 (march),
#199 (placement), and #187 (approved staging boundary). PR201 is an evidence
input, **not a merge dependency**. No edge returns from this prerequisite to
PR201. The originating implementation proposal is
`.superpowers/cf04cr-render/locomotion-prerequisite-proposal.md` in the
`cluster-cf04cr-render` worktree, SHA256
`607585587e818420688a72473a0c69b8a19eab77ee6e0b2386c8a03f5fae6b6b`.
The same tree's `review-round1-01a195a8.md` independently reproduces the issue.
Neither document is an acceptance waiver.

Actual receipt `corrected/detour-far-1x/slice-05.json`, slot 3, moves
`[1145508,695446] -> [1145508,697299]` while saved facing is 0 (+X).
The retained audit counts 34 transverse detour legs and 8 turn legs. The current
`Map3DUnitRig.gait_rate` scales one forward gait frequency. With fixed +X yaw,
it cannot cancel +Y ground displacement: zero frequency/REST slides too.
`BodyMotion._segments` currently times each ceil-length leg by `budget_m`,
with a stationary tail. `commit` saves endpoint/path and a v1 receipt/priority;
it does not save or certify yaw intervals. #200 requires that timing and saved
facing, so the renderer cannot silently fix this by inventing a turn.

`UnitBodies.rows` is an owner-copy query, not admission or migration.
`ArmySystem.plan_body_march_candidate` / `commit_body_march_candidate` and
`TickEngine.begin_body_march_candidate` / `step_body_march_candidate` are
isolated v1 transactions. Their frozen cursor, route prefix, once-only payment
and JSON retry rules remain real constraints. `military_migration.body_version`
and battle ownership/count versions are separate from the motion version.
Do not bump the body schema merely to relabel an old motion receipt.

The technical choice is **engine-authoritative stop–pivot–move**, with one
re-certified timeline for translation, stationary pivot and waiting. Keeping
saved yaw would require five arms' sideways/backward contact clips, a much
larger change. Instant tangent yaw pops and has no certified swept silhouette;
free easing remains transverse while turning. Restricting paths to saved-facing
parallel legs removes required detours/turns. Changing playback rate, reducing
radius/scale, dropping L-path cases or hiding bodies is not an alternative.

## Conditional precedence and PR201 boundary

`cf04c-render-contract.md` is retained unchanged. Only after all relevant engine,
integration, per-arm art, certification and consumer prerequisites below have
accepted merges, an explicitly registered **v2 consumer** may replace these
v1 playback clauses for an explicitly v2 receipt:

- v1 `path_m`/`budget_m` segment time is replaced by the committed integer
  operation intervals below; no normalization of total path to a slice;
- constant per-row saved facing during motion is replaced by committed yaw
  interpolation; final row facing still equals the committed formation facing;
- v1's transient timing envelope is replaced by a validated v2 receipt plus
  explicit in-slice cursor. A saved v1 path never acquires v2 timing.

Every other #200 requirement survives: admission before lookup, copied data,
no hidden hostile intent, complete schema/ownership/count validation including
zero fit, no partial publication, stable identities, fractional XZ conversion,
terrain seating, reference scale, default-off staging, real windows and costs.
No clause changes merely because this document merges.

PR201 remains draft/active with implementation
`01a1959a-e085-7a33-a7d7-278585c178ba` and sole Review
`01a195a8-dce9-78a2-9818-fa5be7306096`. That pair retains its WIP, original
contract, R1 failure and R2/R3 fixes. This document neither reviews their patch
nor reports R1 resolved. No third product owner/architect/reviewer is introduced.

**Registration blocker, not an inferred permission:** PR201's immutable
registered acceptance requires the old contract. The current append-files
mechanism preserves acceptance and cannot legally turn that PR into the v2
consumer. Thus this document does not promise that PR201 can consume the
revision. The smallest unresolved delivery boundary is a separately authorized
v2-consumer step with exact files and acceptance, after legal resolution of the
existing overlapping PR201 claim. Until that resolution, the existing pair may
fix/review R2/R3, but cannot merge as R1-PASS or silently adopt this contract.
No raw registry edit, reinterpretation, retirement, owner replacement or
acceptance deletion is authorized here. A future rule/registration amendment
must preserve the original pair, evidence and full gates; explicit human
authorization is required for any terminal declaration. Do not dispatch the
overlapping consumer while this boundary is unresolved.

## Integer time, heading and budget protocol (candidate v2)

One existing simulation substep contains `Q = 1_000_000` dimensionless time
quanta. Q is a serialization precision, not real seconds, another clock, or a
tuning value. An interval's endpoints are integer `0 <= t0_q < t1_q <= Q`;
positive duration is mandatory. Operations exactly partition `[0,Q]`, in order,
without overlap or gaps. Shared boundary samples use the next interval; at Q
use the exact final pose. Equal adjacent holds may be coalesced canonically.
Repeated path points generate no move or zero-duration pivot. An entirely
stationary row has one hold covering the slice.

Angles use integer microdegrees (`udeg`), 360_000_000 per revolution. Zero is
pack +X, positive is toward pack +Y, matching saved `facing_deg`; convert to
world yaw with the existing pack/world convention, never camera heading.
Canonical yaw is `[0,360_000_000)`. Signed shortest turn is
`((to-from+180_000_000) mod 360_000_000)-180_000_000`, with the exact -180-degree
tie replaced by +180 degrees. Each pivot therefore turns at most 180 degrees.
Final yaw is exactly `facing_deg * 1_000_000` (facing remains 0..359).

For nonzero integer displacement `(dx,dy)`, move heading is the nearest
microdegree to mathematical `atan2(dy,dx)`, modulo one revolution; exact
half-quantum ties choose the positive-direction result. Maximum angular error
is 0.5 microdegree. Authority must implement correctly rounded heading by
integer/interval arithmetic with refinement until the rounding bin is proved;
platform `atan2` followed by rounding is not an authoritative cross-platform
tie rule. No runtime-generated float/table gets saved as a second authority.
Axis, diagonal, wrap, nearly axial and integer-limit vectors get fixed expected
tests. No new heading lookup table is required by this contract.

All authoritative values and intermediate products are range-checked. Use the
existing BodyMotion coordinate/local-budget bounds; Q and angle products must
fit signed int64 before multiplying, otherwise reject atomically. Persist only
exact integers within JSON's exact integer range (absolute value <= 2^53-1),
canonical strings for saved control integers as below. Reject booleans, null,
fractional/nonfinite numbers, noncanonical decimal strings and future versions;
normalization of integral JSON numbers follows existing `BodyMotion._canonical`.
Never silently truncate a coordinate or duration.

Policy values belong in new rows of `data/army/balance.csv`, one row per arm:
`body_locomotion_<arm>_turn_q` (positive full-revolution duration in quanta),
and `body_locomotion_<arm>_contact_um` (maximum certified ground-contact error,
integer model micrometres). Arms are infantry/archers/cavalry/artillery/royal.
Rows are installed only with actual certificates; missing/zero/out-of-range
policy means unsupported v2 for that arm. No arbitrary tuning numbers are
approved by this document. The policy digest binds exact rows and certificate
digests. Artillery requires its own radius/policy certification even when using
the explicitly permitted infantry model placeholder.

For a move of ceil-Euclidean length L and that slice's already computed
`budget_m = B > 0`, duration is `ceil(L * Q / B)`. Integer square root with
ceil provides L, consistent with the existing length rule. Positive moves take
at least one quantum; rounding never makes them faster than B. A pivot with
absolute turn A takes `ceil(A * turn_q / 360_000_000)` quanta, at least one
when A > 0. These durations consume the **same** Q; pivoting reduces reachable
translation. There is no second movement budget and no added per-frame budget.

The planner constructs turn + move operations before reservation, including a
final pivot to saved formation facing. It selects only a complete integer
waypoint prefix for which that final pivot also fits. If a desired move does
not fit, it may deterministically shorten it to an integer point under its
bounded search, then recompute heading/pivots/duration and revalidate everything;
it cannot proportionally cut an unvalidated operation. Otherwise hold and give
a blocked reason. Remaining quanta become a hold. `used_m` is sum of executed
ceil leg lengths, <= B; pivots have zero translation, not free elapsed time.
Unused distance/time does not carry to another body, slice or day. March
charges the existing gait/run/supply policy once and advances route credit only
for actual reached route prefix, never pivot time, endpoint chord or all-body
sum. No new fatigue, RNG draw or extra order charge is introduced.

## Candidate APIs, saved receipt and atomic publication

These exact proposed APIs are future scope, not callable source today:

```gdscript
# Pure RefCounted engine code, existing v1 entrances retained unchanged.
BodyMotion.plan_locomotion_candidate(repo: DataRepository, state: GameState,
    intents: Array, abs_day: int, substep: int,
    march_boundary: Dictionary = {}) -> Dictionary
BodyMotion.commit_locomotion_candidate(repo: DataRepository, state: GameState,
    proposed: Dictionary, march_boundary: Dictionary = {}) -> Dictionary
# Read-only validated COPY; no repo/state/context, no plan/commit/query calls.
BodyMotion.sample_locomotion_candidate(projected: Dictionary, time_q: int) -> Dictionary
```

Intent identities/paths/budgets/hostility retain v1's admission and complete
world validation; final facing comes from the validated row, not a renderer
parameter. Plan status/reason/blocked diagnostics follow v1. A successful plan
has exactly `version, cursor, policy_digest, moves, reasons`. Version is integer
2. Cursor has `abs_day, substep, basis, intents, priority, boundary`; integers
are typed integers here. Moves are canonically sorted by `(unit,slot)`, priority
is the existing deterministic reservation priority (not move array order).
All required bodies, including zero-displacement peers, participate.

Each move has exactly:

```text
unit:String, slot:int, start:[int,int], end:[int,int],
start_yaw_udeg:int, final_facing_deg:int, budget_m:int, used_m:int,
ops:[{kind:"hold"|"pivot"|"move", t0_q:int,t1_q:int,
      a:[int,int],b:[int,int],yaw0_udeg:int,turn_udeg:int}]
```

Hold: a=b, turn=0. Pivot: a=b, nonzero shortest signed turn. Move: a!=b,
turn=0, yaw0 is the engine-quantized tangent. Endpoint yaw wraps by the rule
above. Every op starts at the preceding endpoint/yaw; first matches start,
last matches end/final facing. No redundant zero turn or zero move, unknown
keys or duplicate identities. Final row x_m/y_m/facing are exactly these
endpoints. `path_m` remains the canonical translated waypoint list (including
the starting point); it is compatibility geometry, never v2 timing authority.

Basis hashes the exact precommit `state.to_dict()`, input intents, existing
footprints/clearance/local-search inputs, policy/certificate digests, boundary,
and applicable diplomacy, as v1 binds its relevant inputs. All arrays have
explicit stable order. Canonical serialization uses the existing recursive
sorted-key `BodyMotion._canonical` and SHA256 `_hash`, including integer
normalization. Receipt is `_hash(full successful plan)`; it includes every
operation, policy, priority, basis and reason. No self-referential receipt field
appears in the hashed plan. No source file path, wall time or camera enters it.

The committed `military_migration.body_motion` v2 control has exactly
`version:"2", abs_day:String, substep:String, receipt:String, priority:Array,
plan:Dictionary`. Day/substep and priority control integers retain canonical
nonnegative decimal-string encoding; the embedded full plan retains typed
JSON integers under the rules above. Plan and outer control cursor/priority
must agree after normalization. Receipt must hash the embedded plan. Only one
saved motion authority exists: this control plus its validated endpoint rows;
no separate renderer receipt/store or independently mutable per-body timeline.
The full plan persists to permit read-only validation after JSON load. The
render projection admits and copies only its unit's operations; it never
exposes the global plan, priority/intents or basis as a hostile-data oracle.

Commit replans against the exact basis and compares the entire hash before
publishing on a detached candidate. Endpoints, path, facing, motion receipt,
march journal/cursor, supply/route progress and prior payment receipt publish
atomically through the integration transaction. Failure leaves source, RNG,
personnel, money, supplies and cursor byte-equivalent. Same cursor + identical
receipt retries return a detached unchanged candidate/no-op, including after
JSON roundtrip; same cursor + another receipt rejects. Changed state/policy,
stale/future cursor, owner transfer or forged operation rejects; it does not
replan behind the caller's back during publication. Frozen transactions remain
frozen and resume once through the owning boundary, never through the view.

## Unified sweep and pure sampling

Reservation runs **after** the complete timed plan is constructed. Retain the
production CF01 circle radius/clearance, stable priority and bounded yield/
detour search. For every pair of overlapping op intervals, intersect their
integer time ranges and minimize squared relative distance over that interval
using linear motion (zero velocity for pivot/hold). Use exact rational/int64
checked arithmetic or conservative outward rounding; boundary contact follows
the existing strict-clearance rule. Include endpoints and the whole tail.
Do not certify a v1 sweep then insert pivots/waits. A delayed peer may collide
with a stationary pivot even when the old translating pair was clear.
Static terrain/closed-cell/water/bounds checks include every translated swept
circle; stationary pivot circles remain occupied for their whole duration.
Enemies keep actual contact and diplomacy constraints. No hidden obstacle is
removed just because it is not admitted to the view.

The fixed circle is valid for pivoting only after full yaw/pose/contact
certification at the unchanged ordinary model scale. CF01's 17 measured poses
do not prove this. Bounds must contain the **body** through all accepted pivot
parameters, clip transitions and forward gait phases (mounted arms include
horse/rider; equipped archer includes its attached body envelope). Weapon
contact uses the existing body/weapon distinction; no new permissive exception.
If an envelope cannot fit the current radius, mark that motion unsupported and
require a separately registered footprint/art contract step. Never shrink the
model or radius, silently enlarge deployment spacing, or claim all turns pass.

The pure sampler validates the copied v2 schema and `time_q in [0,Q]`, selects
its interval, then linearly interpolates X/Y and unwrapped yaw before wrapping.
Return transient float coordinates/yaw plus operation kind and exact identity;
the source remains unchanged. Floating presentation values are never saved or
fed back into simulation. Sampler rejects malformed inputs with empty rows and
a diagnostic. It makes no admission/state/hidden-order/stance lookup. No free
easing, positional spring, per-body lag, tangent inference, extra wait, corner
shortcut, teleport, model rescale or yaw chosen by frame delta is allowed.
Use fractional pack-to-world conversion from #200, upright seating and the
ordinary reference scale. Terrain Y/visual limb contact cannot alter XZ/yaw.

An own/DEV projection supplies only copied operations, receipt/version/cursor,
policy/certificate IDs and admitted row identity/count/home. Observed hostiles
receive current pose only, no future ops, cursor, orders or stance reads at
**any downstream animation layer**; unseen/ghost/naval retain existing fallback
before any body lookup. Validate current body versions even for empty arrays.
Visibility cache keys include only admitted information. A v2 current pose does
not authorize future hostile motion or action selection.

In-slice playback requires the driver's explicit `{version:2,abs_day,substep,
receipt,time_q}` bound to the saved plan. Same receipt/refresh/pause/load cannot
restart a completed slice. Without this envelope on load/rebind, show the exact
committed endpoint, not an invented rewind. All peers sample the same time_q.
Only the existing clock/fixture maps slice-local share to time_q (floor share*Q,
with exact Q at the boundary); FPS/camera/near/far/offscreen never create a
simulation cursor. Preserve child `(unit,slot)` identity and phase through owner
transfers. A new receipt starts at the preceding committed pose; discontinuity
is invalid, not a blending bridge.

## Compatibility and mandatory negative cases

No valid old save becomes unloadable because pivot art is unavailable. Current
GameState-supported saves and v1 motion remain readable under their existing
protocol. Uninitialized legacy bodies use the accepted explicit migration/
placement path; preserve original file, people/costs/coordinates and overlap
diagnostics. Never repair a save in a render query or claim an overlapping old
save is clear. Legitimate initialized v1 receipts keep v1 endpoint display on
load, without speculative yaw playback. Existing v1 candidate execution stays
available to complete/resume an already frozen v1 day unchanged. Only at a
validated closed day boundary may a caller explicitly begin the separately
versioned v2 transaction. No in-flight receipt conversion, reset or repayment.

Integration introduces explicit `ArmySystem.plan_locomotion_march_candidate` /
`commit_locomotion_march_candidate` and `TickEngine.begin_locomotion_march_candidate` /
`step_locomotion_march_candidate`, retaining v1 entrances and ordinary call
graphs. The new outer body-march control uses version "2" and binds the inner
version 2 receipt; do not silently interpret v1 fields as v2. DayResolution
must validate both known protocols and refuse unknown/mixed protocols. Final
activation still owns selecting the protocol and normal boot/day dispatch.
Unsupported v2 returns an explicit candidate diagnostic without damaging a
valid save or masquerading as completed movement. It cannot count as acceptance
of required L/turn gameplay; all required arms/cases must eventually certify.

Mandatory failures: zero/negative/overflow duration, gaps/overlap, total >Q,
zero budget with movement, negative budget, wrong tangent or endpoint facing,
nonshortest/wrong-wrap pivot, stale policy, missing certificate/clip, forged
hash/basis, duplicate/reused slot, wrong owner/fit, absent current schema with
present rows (also zero fit), mixed inner/outer version, stale retry, malformed
JSON integers/strings, unknown fields/version, invalid shares/times. Each must
preserve state and RNG. Unknown/future motion fails publication with a
diagnostic; failing closed is not permission to reject all supported old saves.

## Hand-computed acceptance examples

Use miniature test budgets/policies, not production tuning. For Q=1_000_000,
`turn_q=400_000`, B=10, initial/final facing 0, desired
`[(0,0),(3,0),(3,4)]`: move +X occupies 0..300_000; pivot +90 degrees occupies
300_000..400_000; move +Y occupies 400_000..800_000; pivot -90 occupies
800_000..900_000; hold to Q. At 350_000 position=(3,0), yaw=45 degrees;
at 500_000 position=(3,1), yaw=90; at 850_000 position=(3,4), yaw=45.
Used distance is 7, time cost is 900_000. This intentionally differs from v1
at share 0.5, which is (3,2). The complete new timing must be re-swept.

With B=8, move durations are 375_000 and 500_000; two pivots add 200_000,
total 1_075_000, so that full L plan is invalid. Holding, executing an affordable
validated prefix or replanning is legal; speeding the clip or omitting the final
pivot is not. With B=20 the L consumes 150_000 +100_000 +200_000 +100_000 =
550_000, then holds. Unequal bodies therefore share time, not endpoint arrival.
For diagonal (0,0)->(3,4), L=5, B=10: move time=500_000 and heading
53_130_102 udeg; quantization tolerance is checked in certification.

Wrap: 359->1 degrees gives +2_000_000 udeg and duration 2_223 (ceil 2222.22…);
1->359 gives -2_000_000; 0->180 chooses +180_000_000 and takes 200_000.
Equal headings make no pivot. A stationary row holds throughout Q.
Pivot occupancy counterexample: radius=1, clearance=0 in a test fixture;
A stays (0,0) while pivoting through 300_000..400_000. B moves
(-3,0)->(3,0) during that same interval; distance is zero at 350_000, so reject.
An old sweep in which A had already left does not certify the new plan.

Required future GUT: these exact values; boundary samples; repeated/zero legs;
negative coordinates; opposing/three-way/unequal-speed and pivot-versus-hold
collisions; closed land; bounded blocked retry; integer overflow/heading bins;
all negative cases; whole-JSON equality across repeat/roundtrip/frozen resume;
cost/personnel/slot/RNG conservation; real downstream forbidden-read counters;
same simulation hashes for pause/1x/4x, near/far/offscreen, camera and different
delta/FPS partitions. Use SuiteData, no new DataRepository.load_all tests.

## Installed art facts and required pivot evidence

Read-only GLB JSON inspection at this baseline found **no pivot clip**:

- Infantry `assets/3D/units/infantry/infantry.glb`: MARCH, GARRISON, ATTACK,
  SLASH, ATTACK_VAR1; SHA256
  `bb1d80b916be406f91390883034e07d0cf2d7690666951c3216b202393548085`.
  Current installer/exporter is `tools/units3d/soldier_arp/game_export.py`
  (source `soldier_knight_arp.blend` in the object's ignored model_wip),
  not the old `infantry_blueprint/export.py`.
- Archers `assets/3D/units/archers/archers.glb`: STANDBY, MARCH, SPRINT,
  DRAW, GARRISON, DEATH; SHA256
  `7484f4977058fed353c12d5507837257992e97bc52283487d61c7886e6481b9b`.
  `tools/units3d/archer_arp/export.py` reads `archer_six_clips.blend` and
  exports the body plus `archers_bow.glb`, `archers_quiver.glb`,
  `archers_arrow.glb`. The installed scene shares named skeleton binds;
  old `archer_rig`/`archer_tripo` exports are not the current source chain.
- Cavalry `assets/3D/units/cavalry/cavalry.glb`: ATTACK, DEFEND, GARRISON,
  MARCH, STANDBY; SHA256
  `545a6b66052a780c03c83eb476fea8853ce53d98d03c681bbb58dfdf0b0dd916`.
  `tools/units3d/cavalry_rig/actions.py`, shared `royal_rig` export helpers,
  and `cavalry_rig/install.py` use ignored `rig/cavalry_rig_work.blend`.
- Royal `assets/3D/units/royal/royal.glb`: STANDBY, GARRISON, MARCH, ATTACK,
  DEFEND; SHA256
  `3c5ca58c7bed3b946d95e255f179351a5650565e1a8b07904767740de1ac0527`.
  The current source is the owner's ignored `tripo/knight_rig_anim.blend`,
  installed by `tools/units3d/royal_install/install.py` from its 20k delivery.
  `royal_rig/actions.py` alone is not proof of current installed clips.
- `assets/3D/units/army_models.tres` binds artillery to infantry.tscn.
  This approved placeholder is not a distinct certified cannon or pivot.

The actual scene paths are `scenes/models/units/infantry.tscn`,
`scenes/models/units/archers.tscn`, `scenes/models/units/cavalry.tscn`,
`scenes/models/units/royal.tscn`; artillery shares the first. No scene/art edit
occurs here. Future imports/editor saves must preserve named binds, ordinary
scale, skins, gear, all existing clips and source ownership.

Proposed new exact clip names are `PIVOT_LEFT` and `PIVOT_RIGHT` for each model.
Positive pack turn selects RIGHT; negative selects LEFT. For example, pack
+X -> +Y is +90 degrees, while pack_to_world maps +Y to world +Z and yaw_for
maps those headings to world yaw -90 -> -180 degrees: the model turns right.
The reverse turn selects LEFT. Certify this mapping on real ground rather than
relying on a Blender axis label. Each clip contract
takes the committed signed turn, duration and normalized operation phase. A
generic rotated idle or time-scaled 180-degree clip is **not** contact proof for
arbitrary angles. The per-arm author must supply a contact-preserving parameter
mapping (and enumerate any necessary visual limb solver in a separate registered
scope before code) covering every admitted microdegree turn and start/stop
transition. No runtime limb solver may alter body origin, yaw or simulation.
Without such coverage the supported set is explicit and all other turns reject;
the required full L/turn acceptance remains pending, never weakened to that set.
This is a real art feasibility gate, not an assumption that two clip names solve it.

Per-arm evidence consists of exact new files under
`docs/reviews/cluster-formations/evidence/locomotion/<arm>/`:
`source.json`, `pivot-contacts.json`, `pivot-envelope.json` (arm is one literal
arm per registration). source.json binds source blend hash, exporter hash,
installed GLB/import/scene/gear hashes, bone/contact names, clip lengths/frame
rate, angle mapping, model-to-world scale and policy. Contacts records each
stance interval's planted sole/hoof world coordinates, normal/separation,
slip/penetration/hover error, transitions to/from MARCH and both pivot signs;
bind accepted error to contact_um. Envelopes bound the full yaw silhouette and
all intermediate deformed poses against the existing radius. Finite samples
alone do not prove continuous coverage: provide conservative interpolation/
skinning bounds or a parameter-domain bound plus independent dense adversarial
checks. Include exact 180 tie, near-zero turns and wrap. Contact and envelope
both must pass; unsupported cases are explicit red evidence. Real-window
continuous near/far pause/1x/4x and FPS clips plus native foot/hoof crops are
mandatory after numeric certification, not replaced by these JSON reports.

## Future bounded scopes and dependency order

These are proposed registrations, **not tasks started by this PR**. Only the
original dispatcher may reconcile existing claims and register each once with
its own implementation/unique Review/worktree/branch/acceptance. No wildcard
asset ownership or combined planner+art+renderer PR. New literal files below
are proposed names; a required additional file must be registered before edit.
Shared files enforce serialization even where dependency edges would allow
parallel work.

1. `LOCO-TIME`: depends on this accepted document and accepted #192. Own
   `scripts/engine/body_motion.gd`, `tests/engine/test_body_motion.gd`,
   `scripts/engine/guide/body_marches.md`. Implement candidate v2 planner,
   commit, pure sampler, unified sweep and the hand calculations/negatives;
   use test-injected policy/certification data, no installed arm support claim.
   Existing v1 behavior/tests remain. No march/payment/renderer/art change.
2. `LOCO-MARCH`: after LOCO-TIME. Own `scripts/engine/army_system.gd`,
   `scripts/engine/unit_bodies.gd`, `scripts/engine/tick_engine.gd`,
   `scripts/engine/day_resolution.gd`, `tests/engine/test_body_marches.gd`,
   `tests/engine/test_unit_bodies.gd`, `tests/engine/test_day_resolution.gd`,
   `scripts/engine/guide/body_marches.md`. Add explicit v2 integration,
   frozen-day/JSON compatibility and atomic payment/route receipt tests.
   GameState already saves the whole dictionary; no new save file or silent
   SAVE_VERSION bump is authorized. If new GameState work is necessary, split
   and register it explicitly. This scope cannot overlap LOCO-TIME's guide.
3. Four independent arm clip steps after the document, each with separate
   acceptance; use existing animation/rig skills locally. Infantry owns only
   new `tools/units3d/soldier_arp/pivot.py`, existing
   `tools/units3d/soldier_arp/game_export.py`, and
   `assets/3D/units/infantry/infantry.glb` / `infantry.glb.import`.
   Archers owns new `tools/units3d/archer_arp/pivot.py`, existing
   `tools/units3d/archer_arp/export.py`, and
   `assets/3D/units/archers/archers.glb` / `archers.glb.import`.
   Cavalry owns new `tools/units3d/cavalry_rig/pivot.py`, existing
   `tools/units3d/cavalry_rig/install.py`, and
   `assets/3D/units/cavalry/cavalry.glb` / `cavalry.glb.import`.
   Royal owns new `tools/units3d/royal_install/pivot.py`, existing
   `tools/units3d/royal_install/install.py`, and
   `assets/3D/units/royal/royal.glb` / `royal.glb.import`.
   Each new pivot.py authors/exports on a copy of its actual source chain;
   ignored source blends stay in that object's model_wip, originals retained.
   Do not amend shared royal helpers or old rigs implicitly. Archers' separate
   gear stays byte-identical unless the dispatcher first enumerates the exact
   required gear files. No texture/material/scene scope is implicit.
4. `LOCO-CERT-<arm>`: **five separate steps**, each after its corresponding
   clip accepted merge (artillery after infantry clips), using LOCO-TIME's
   protocol. Own exactly the three evidence JSON files for that literal arm
   above, plus a new dedicated
   `tools/units3d/certify_<arm>_locomotion.py`. Scripts audit installed GLB and
   existing scene, never rewrite either. Each independently verifies full
   parameter contact/envelope bounds and real-window evidence with its unique
   Review. Infantry evidence does not certify artillery's different radius.
   If a scene/bind/import change is required beyond the clip step, register a
   separate literal scene step using gdai/editor plus visual-review, then
   recertify; no text editing or blanket scenes/ ownership.
5. `LOCO-POLICY-<arm>`: five small serial steps after that arm's certificate
   and LOCO-MARCH. Each owns `data/army/balance.csv` and that arm's
   `source.json` solely to bind its accepted policy/certificate digest, plus
   `tests/engine/test_body_motion.gd` for its real-policy admission assertion.
   Each installs only its named two rows. Certificate hashing excludes the
   digest field itself; define the signed source payload before certification
   so binding does not recursively invalidate itself. Preserve evidence of the
   certification inputs and rerun affected policy acceptance. These steps
   serialize on the CSV/test file, not five simultaneous claims. No new table,
   data/tables.csv or footprint edit is needed.
6. `LOCO-CONSUMER`: after LOCO-MARCH and all five policies/certificates, and
   **only after the PR201 registration blocker above is legally resolved**.
   Exact proposed files are `scripts/map3d/map3d_battle_groups.gd`,
   `scripts/map3d/map3d_layer_units.gd`, `scripts/map3d/map3d_unit_rig.gd`,
   `scripts/map3d/CLAUDE.md`, `tests/map3d/test_body_paths.gd` and `.gd.uid`,
   `tools/map3d/body_paths_fixture.gd` and `.gd.uid`. Existing ownership must
   be reconciled; this list is not an appended scope for PR201. New explicit
   `sample_locomotion_candidate`/`along_locomotion_candidate` projection seams
   consume copied v2 operations and the pure sampler, keeping v1 entrances.
   Clip selection/contact mapping is presentation only. If arm feasibility
   requires new runtime solver files, this proposed scope is insufficient:
   register the exact bounded solver dependency before this step starts.
   Test downstream sight/hidden-action reads, stable phase/identity, actual
   advancing fixture clock and the full continuous real-window matrix.

The DAG has document -> time -> march; document -> each arm clips -> each arm
certificate -> each serial policy (also march) -> consumer. All five policy
branches converge once. None depends on PR201 merging; consumer additionally
has an unresolved legal ownership/acceptance gate, not a fake accepted edge.
Final atomic activation remains separately owned after all other P4 writer,
battle/damage and original staging prerequisites, including live bridge changes
and boot/load. This document starts no activation, product or successor session.

## Retained acceptance and document verification

All twelve spec §9 gates remain: (1) ten/count/fixed footprint; (2) full-radius
sweeps/yield/turn/reload; (3) eight-formation eligibility; (4) independent speed,
assembly and local budgets; (5) actual delivery/version/king; (6) vulnerable
assembly/stable old line; (7) reform/expansion/partial selection/single membership;
(8) normal/blocked/member-loss behavior for all eight; (9) physical contact,
fire/occlusion and explained nonduplicated bonuses; (10) save/speed/camera
determinism/cost/personnel compatibility; (11) reproducible formation-vs-none
and countered outcomes; (12) actual 3D-map visual/performance acceptance.
The inherited frozen run remains **55 fail and 6 risky/pending**, not PASS.
Real road contact, defeat continuation, live boot/current-campaign placement/
military reorganization/save/load and ranged eligibility remain obligations.
CF01 is only 17 sampled poses plus the approved artillery-infantry placeholder;
CF08 remains layout-only. No new art/turn support is certified in this PR.

Future consumer and activation use real-window visual-review: before and at
least two variants, native full-window and 3x contact crops, sole Review's
independent eight-axis critique, continuous opposing/three-way/L-detour/turns,
near/far, pause/1x/4x, different FPS, full/reduced strengths and all arms.
Check the whole animation for penetration, hover, slip and identity flash.
Use the project shared Godot lock and faithful snapshot_screen workflow;
headless 3D, fixed screenshots and numerical circles cannot substitute.
Evidence binds exact inputs/HEAD, operation receipt, window resolution,
commands, native clips, contact results and failed variants.

Performance retains existing `bench.gd` tier/size/budget near/middle/far and
still/pan comparisons, mean/median/p95 plus render/engine work. Both ordinary
baseline and candidate use identical accepted inputs. Also measure a genuinely
advancing full slice clock through pivot/move/receipt boundaries, not a
fixed-share=0 consumer fixture with walk clips playing. Final activation repeats
in the live world under the production clock/all writers. No lowered radius,
hidden armies, reduced count/budget, second RNG/budget or fixed-share benchmark
may stand in for this acceptance. Required CI is current-HEAD, with no missing,
skipped-required, failed, cancelled or timed-out checks treated as success.

This document-only step runs Python hook/selector/runner/timeout self-checks,
shell/config/guide checks, explicit documentation-only selection and whitespace
checks. It runs no Godot/Blender, changes no script/test/CSV/scene/art/config,
and makes no visual PASS claim. Its sole Review checks source facts, arithmetic,
compatibility, conditional precedence, exact scopes and acyclic prerequisites,
then merges only after required current-HEAD document CI passes. Only the
original dispatcher can register later work; this pair ends after its document
PR completes.
