# CF04b candidate placement contract

Step `CF04b-contract`, 2026-11-01. Documentation only. Source baseline
`4dbade74dc08d7988fbbd68ba34fd915021b008f` (CF04aR, #194, accepted merge).
Implementation `01a19522-9fb2-74e2-b138-8e15c64c734f`; sole dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`. This supplies the exact technical
contract required by accepted #187 (`4ac809c8a5884ed161ee320e84080d7ea853a9c0`).
Its historical DRAFT wording does not reopen human-approved staging. Only the
dispatcher registers product ownership after this document's Review/CI/merge.
No product, guide, fixture, category, loader or production binding changes here.

CF04a's candidate marches are not production activation or complete P4. P3
(#197, merge `7c79245335ed9a8185c9d7b8d52d81c07a058bb4`) repairs baseline
receipts/observation, not body placement. Superseded, unmerged P1/P2 are not
accepted dependencies. This contract retains Task CF04b and spec §§2–9,
including eventual legal legacy loading and current new-campaign roundtrip.

## Actual source trace and authority gap

References below are repository-relative paths and actual methods at the baseline:

- `scripts/engine/unit_bodies.gd`: `rows` reads detached sole-owner rows;
  `home_slots` returns ten **local**, unrotated `Vector2i` offsets, not world
  placements. `_config` selects `MapObjects.army_piece` and verifies measured
  radius/pitch/width/depth; `_migration` validates all owners and present rows,
  returning `needs_placement` only for absent legacy poses or validated growth.
  `_request` returns exactly `{unit,battle_id,reason,anchor_m,facing_deg,
  missing_home_slots}`. It has no placement writer. `_copy` preserves raw state
  and RNG without loader normalization. `reconcile_candidate` stages canonical
  counts and `body_reconciliation={version,basis_fit,target_fit}`; it does not
  recruit people. `transfer_candidate` moves storage ownership, not world poses.
- `scripts/engine/body_motion.gd`: `plan(repo,state,intents,abs_day,substep,
  march_boundary={})` and `commit(repo,state,proposed,march_boundary={})` require
  complete initialized bodies. All bodies reserve space; continuous relative
  sweeps validate movement. It cannot consume `needs_placement`, invent a row,
  choose an initial home or certify terrain. Its receipt is a motion receipt.
- `scripts/engine/army_system.gd`: `plan_body_march_candidate` /
  `commit_body_march_candidate` bind body motion, anchors, gait and cost together.
  `_body_path_terrain(grid,path,radius)` checks swept discs against actual
  grid/bounds; `_body_terrain_error` checks motion outputs. Reuse that terrain
  predicate for a stationary new circle (`path=[point]`); do not duplicate a
  weaker center-cell test. `position_of`, `starting_state`, `roster`, `regiment`
  and `MilitaryRoster.fit` remain the corresponding read authorities.
- `scripts/engine/army_ground.gd`: `ring`, `slot_m`, `first_ring`, `free_slot`
  implement stable camp lattice enumeration. `free_slot` uses old unit circles,
  accepts an `any_terrain` pass and may return `NONE`; it does not place ten
  measured bodies. `settle`, `_put`, `refill`, `take_seat` teleport anchors;
  `leave` preserves camp law before clearing it. `reconcile` clears lost seats
  and may refill them. These ordinary mutators cannot be called as the new
  physical authority, even on a clone followed by a corrective body snap.
- `scripts/engine/army_split.gd`: `opening_sources` and `split` create source /
  preview roster and seats; `_make`, `_place`, `_preview_crews`, `_seat` use
  legacy placement. `halves` and `saved_sources` concern personnel provenance,
  not new bodies. `scripts/engine/game_state.gd:new_campaign` obtains opening
  sources, runs `MilitaryBootstrap.initialize`, `ArmySystem.ensure`, then
  `EnemyAi.spawn`. CF04b does not edit that boot chain.
- `scripts/engine/enemy_ai.gd:spawn` obtains `host_units`, uses host pack-pixel
  start, spreads old unit circles, calls `starting_state`, writes `foes` and
  `ai_hosts`, and refills seats. Its fallback to `start` is not body clearance.
  Reuse host membership/order and initial-state formulas, not that fallback.
- Existing production callers: `army_system.gd:set_march_m`, `set_garrison`
  and ordinary march/arrival paths call ground leave/settle; `courier_system.gd`
  delivers `take_seat`; `tick_engine.gd` calls ground reconciliation;
  `battle_system.gd` calls ground leave on withdrawal. None switches in CF04b.
- Source rules: `guide/cluster_formations.md`, `guide/body_marches.md`,
  `guide/regiments.md` under `scripts/engine/`; foundation/amendment and march
  contracts beside this document; approved plan Task CF04b and staged mapping;
  `docs/superpowers/specs/2026-10-25-cluster-formations-design.md` §§3,8,9.

The minimal new authority is explicit placement of **only missing rows** on an
isolated candidate. Existing-row movement remains exclusively BodyMotion within
CF04a's cost/anchor transaction. Placement never calls a planner on incomplete
bodies, deletes frozen data to enable planning, translates an existing body to a
new home, or invents bodies in a query/migration/legacy helper.

## Exact future public API

These are proposed additions, not already implemented APIs. Classes remain pure
`RefCounted`. Existing public signatures and ordinary behavior remain unchanged.

```gdscript
# ArmyGround: pure plan, detached atomic commit, convenience plan+commit.
static func plan_body_placement_candidate(repo: DataRepository, source: GameState,
        request: Dictionary, boundary: Dictionary) -> Dictionary
static func commit_body_placement_candidate(repo: DataRepository, source: GameState,
        proposed: Dictionary, boundary: Dictionary) -> Dictionary
static func body_placement_candidate(repo: DataRepository, source: GameState,
        request: Dictionary, boundary: Dictionary) -> Dictionary
# ArmySplit: initialize already bootstrapped roster; no people/equipment split.
static func initialize_bodies_candidate(repo: DataRepository, source: GameState,
        operation_id: String, sequence: Variant) -> Dictionary
# EnemyAi: explicit host initialization, same transaction as its new bodies.
static func spawn_body_candidate(repo: DataRepository, source: GameState,
        host_code: String, operation_id: String, sequence: Variant) -> Dictionary
# UnitBodies: raw validation only, no new row or version repair.
static func validate_placement_candidate(repo: DataRepository, source: GameState,
        boundary: Dictionary) -> Dictionary
```

Each result has exactly `{status,reason,error,candidate,plan}`:

- `complete`: empty error, causal nonempty reason. Plan success has null
  candidate and the closed plan below; commit/convenience success has a detached
  candidate and that plan. An exact commit retry returns a detached unchanged
  candidate and the identical accepted plan, without applying effects again.
- `deferred`: nonempty reason, empty error, null candidate, empty plan. Reasons
  distinguish `space_unavailable`, `requires_motion`, `frozen_transaction` and
  `pending_personnel_boundary` by that leading token plus explanatory prose.
  This is no publication and no paid cost; the caller retains its original world.
- `error`: nonempty equal reason/error, null candidate, empty plan. Malformed,
  corrupt, stale, tampered or unsupported input is never deferred as legacy.

No partial success, `needs_placement` publication, caller-supplied body rows,
optional safety switch or production fallback. Foundation's existing result
shape is unchanged; these APIs adapt it internally and preserve its diagnostics.

Closed request (no unknown keys):

```text
{version:1, operation_id:String, sequence:String, operation:String,
 unit:String, host:String, previous_fit:null|String}
```

`operation_id` must start with the literal `placement:` and have a nonempty
suffix, caller-stable for this one outer transaction. Apply this validation to
both requests and saved controls, including exact retries. This mandatory prefix
cannot match `GameState._is_encoded_int` or `_is_encoded_float`: from_dict
decodes the entire military_migration tree through `_decode_values` when
import_main_v7 is present, so arbitrary IDs such as `i42` or
`f3ff0000000000000` would change type on reload. Such unprefixed IDs error;
`placement:i42` and `placement:f3ff0000000000000` remain literal IDs. No loader
change or alternate ID normalization is authorized;
`sequence` is a canonical nonnegative decimal int64 string. Wrapper Variant
arguments must themselves be such strings (numeric/bool inputs error).
Operations are exactly `initialize`, `legacy_missing`, `recruit`, `settle`,
`leave`, `take_seat`, `refill`, `reconcile`, `enemy_spawn`. `initialize` handles
already staged opening/split units together; it does not perform a personnel
split. `legacy_missing` handles all migration-generated missing requests.
For initialize/legacy_missing/reconcile, unit and host are empty and previous_fit
null. Recruit names one land unit, empty host and canonical previous_fit string.
Settle/leave/take_seat name one land unit, empty host, previous_fit null.
Refill names a town in `unit` (not a regiment), empty host, previous_fit null.
Enemy_spawn has empty unit, host is a real `raid_hosts.host_code`, previous_fit
null. Reject every other combination. No free-form host dictionary, anchor,
fit total, radius, cost delta or external pose permission enters this wire.

Closed boundary has one of two exact shapes:

```text
{version:1, kind:"safe", abs_day:String}
{version:1, kind:"march_complete", abs_day:String, receipt:String}
```

Day is canonical decimal, equals `source.absolute_day()`. Safe requires empty
`day_resolution` and no live pending round; frozen inputs are validated before
deferral, not erased. Completed-march requires actual v4 candidate `body_march`,
its next_substep == substep_count > 0, valid last/inner receipts, no pending
encounter/round and the exact saved last full-plan receipt. Validate using the
real `UnitBodies.validate_march_candidate` at preceding substep plus existing
`DayResolution.body_march_incompatibility_reason`; preserve the entire frozen
transaction. Only metadata-only settle/leave/seat/refill/reconcile on already
complete bodies may use this boundary. No initialization, growth, spawn or
legacy conversion is authorized while frozen. Nonfinal MARCH or ordinary day
transactions defer; invalid/future/raw malformed transactions error. This is
not a new resolver phase or permission to resume production from a candidate.

`validate_placement_candidate` returns the existing foundation five-field
result. At safe boundary it delegates supported provenance/pending validation
to migration, retaining `needs_placement` without fabricating a pose. At the
completed boundary it validates complete rows unchanged and returns complete.
It validates the new saved placement control before either path. No broad
`ignore_frozen` argument is added to foundation or motion.

## Plan, saved control and replay

A closed plan is exactly:

```text
{version:1, request:Dictionary, boundary:Dictionary, basis:String,
 placements:Array, effects:Dictionary}
```

Request/boundary are the canonical forms above. Sorted placement rows are
exactly `{unit:String,battle_id:int,slot:int,home_slot:int,count:int,
 role:String,x_m:int,y_m:int,facing_deg:int,path_m:Array}`; every path starts
and ends at the one new point (`[[x_m,y_m]]`). They describe new rows only.
Effects is exactly `{entries:Dictionary,seats:Dictionary,hosts:Dictionary}`:
entries maps affected unit codes to their computed complete resulting entry,
seats is resulting whole town_seat, hosts is resulting whole ai_hosts. Existing
entry/host extension fields survive. They are proposals compared to independent
recomputation, never trusted assignments. Battle-owned rows go solely into the
battle's groups map; effects entries must not acquire a duplicate body store.
No personnel ledger, RNG, body_motion or day_resolution payload is supplied
as effects. Existing supplies remain exact except a new host entry's one initial
ration calculation via starting_state; this is initial stock, not repeat payment. Plans carry no hidden GameState instance and JSON roundtrip.

Persist exactly one closed control in `military_migration.body_placement`:

```text
{version:"1", sequence:String, operation_id:String, receipt:String}
```

Receipt is lowercase SHA256 of the **whole canonical plan**. No duplicate poses,
costs, personnel or request queue. Absent control starts at sequence `"0"`;
present control requires next sequence old+1, checked for overflow. Same sequence
and same operation_id/receipt is an exact lazy retry; same sequence with any
other receipt/id, older sequence, skipped sequence or overflow is error. Only
latest receipt can retry. Convenience retry first recognizes that cursor and
verifies the full supplied request/boundary against the accepted-plan hash:
because the four-field control cannot reconstruct the previous plan, convenience
APIs do not reconstruct a retry plan from changed state. Instead they return
`error` with reason `retry_requires_original_plan`; the caller retains the plan
from its first success and retries via commit. This limitation is part of the
API, not permission to pay/recruit twice. Direct and JSON commit retries work.

Basis is sorted-key canonical SHA256 of raw source save (including previous
control), request, boundary, footprint/group-size/lattice/camp settings, live
ownership/roster/personnel, host configuration and actual MarchPath grid pixels,
bounds and resolution. Use `BodyMotion._canonical/_hash` semantics (whole JSON
floats canonicalize to ints). Hash content, not cache identity/map id. Terrain,
fit, seat, command, supply, schema or owner changes invalidate an uncommitted
plan. Validate all raw schemas before normalization or integer conversion;
null/fractional/NaN/bool/future controls cannot load into valid defaults.

Commit validates source/control and proposed closed schema first. At an exact
saved retry cursor verify full-plan receipt before basis comparison (the basis
naturally names the precommit state); return copied source without replanning.
Otherwise verify next sequence and basis, independently compute the full plan
and compare **all** fields, apply only that computed result on a private raw
copy, run whole-world validation and publish the detached candidate once.
Any failure discards every staged entry, seat, host, slot counter and marker.
No input source, nested array, RNG or source file changes on any result.

## Placement and lifecycle algorithms

1. At a safe boundary, validate sole owners, supported source/save/body/group
   versions and raw counts first. Reuse migration's conversion of valid legacy
   rows; preserve every legal existing position/path/role/slot/home/facing.
   Absent legacy whole stores with no current marker may request placement;
   present empty positive-fit stores, missing required current stores, malformed
   arrays, unknown future versions and partial legacy battle maps error. A
   valid zero-fit unit gets no rows, but keeps ten nominal homes/footprint and
   its nondecreasing identity counter. Legal old saves with missing optional
   nonbattle poses are handled explicitly here, not blanket rejected by load.
2. Initialize accepts an already bootstrapped detached current campaign or
   staged split roster/personnel. New missing entries are permitted only for
   actual roster land units with ledger provenance and no prior body marker;
   caller cannot relabel a current damaged unit as new by removing one field.
   Migration validation determines the complete missing set, not request input.
   Reject duplicate regiments/foes and ambiguous battle ownership. CF04b changes
   neither MilitaryBootstrap nor MilitaryReorganization; their future outer
   transactions must create/split people once, then publish only the completed
   placement candidate. Post-split pending/failed candidates never enter play.
3. Recruit accepts a source with its one named unit's fit already staged by the
   outer personnel transaction and a raw previous_fit. Reuse
   `UnitBodies.reconcile_candidate` exactly once if not already pending; existing
   validated pending growth goes through migration, never reconciles personnel
   twice. Preserve survivors and count partitions. Missing homes are lowest
   unused identifiers; new slots allocate monotonically from group_next_slot,
   never retired IDs. Loss/no-new-row reconciliation changes counts only.
   Validate all other units complete. CF04b does not debit recruit money or
   transfer cohorts; activation must bind personnel/cost and placement in one
   outer detached publication, discarding all on deferred/error.
4. Each missing request keeps its saved anchor and facing. Rotate the matching
   local home offset using the same y-down convention as `WarFront.facing_vector`,
   use double sin/cos and roundi once per local component (no float32 world
   vectors), check int64 overflow before addition; try that point
   first. If occupied/forbidden, enumerate ArmyGround.ring/slot_m offsets around
   that **home point**, increasing rings, existing walk order, configured
   army_slot_spacing_m through army_slot_max_rings. Compute/check local lattice
   offsets before adding to int64 world points; never narrow world coordinates
   through slot_m's Vector2i. Reuse existing configured
   limit, no new tuning constant or unbounded search. Unit code, battle id,
   then home id determines allocation order. At each candidate test measured
   CF01 circle against all present and previously proposed bodies globally,
   terrain and bounds. No unit-radius broad rejection: friendly deployment
   rectangles can overlap while their real bodies remain disjoint. Hostile,
   dormant foreign, royal, crown and battle-owned bodies are all reservations.
   Never skip the first host unit's clearance. No any-terrain second pass.
   Missing terrain grid is error; exhausted legal space defers atomically.
   A missing body's first pose has no travelled segment; this permission cannot
   relocate a surviving body or change the saved anchor to make space.
5. Newly placed rows use canonical `BattleGroups.counts(fit,battle_group_size)`,
   existing request owner, role front, measured home, saved facing and one-point
   path. Survivors are not rewritten beyond foundation's authorized count/schema
   conversion. On completion remove only resolved body_reconciliation descriptors,
   retain group_next_slot, mark current body schema using existing foundation
   markers and revalidate canonical whole-world counts/circles/sole owners.
6. Settle/camp keeps the actual current rows and anchor. Derive town/holding
   through existing town_at/holds rules, apply LawSystem.on_settle once on the
   clone. It may assign an empty seat only if already at the town point with
   legal bodies; otherwise it camps at its real legal point (camp_town if in
   reach). It does not call `_put` or free_slot to move the unit. A requested
   seat requiring travel returns `requires_motion` with target town in reason;
   caller must issue/complete normal candidate march before trying again.
   Refilling and take_seat use existing eligibility/ranking/ownership but never
   swap anchor/body positions. Their seat transfer is complete only after the
   selected unit legally reaches the point. Waiting keeps old seat/laws exact.
7. Leave calls law-on-leave before clearing camp_town/seat, without moving any
   row, changing order/packing deadlines or immediately refilling by teleport.
   Reconcile clears invalid seat metadata, preserves all bodies, and only fills
   a seat from an eligible unit already physically there; other candidates
   remain camped awaiting real movement. CampSystem packing/building and
   received-command gates remain authoritative outside this placement API.
8. Enemy wrapper resolves host by code and host_units. Stage only previously
   unspawned host, initial entries/rations via starting_state using actual
   proposed terrain, standby/host/camp metadata and ASSEMBLE mind as spawn does.
   Existing lawful bodies transferred regiments -> foes retain poses and sole
   storage; if assembly requires relocation, defer requires_motion, never reset
   them to host start. Truly missing first poses use host start as new anchor
   and the same ten-home search. Transfer ownership/removal of obsolete entry
   and seat clearing are atomic; never double-register a regiment and a foe.
   Host already present with a new operation id is error, not another spawn.
   A frozen or partially pending world defers with its state unchanged.

Stationary geometry uses actual radii: for infantry R=927, tangent centers at
1854 m are legal, 1853 m are not; two local homes are 3708 m apart. Ten infantry
homes span width 16686/depth 5562 m including circles, independent of fit. These
are hand checks of the current CSV, not new script constants. CF01 footprint
selection follows army_piece (including royal selection), not guessed arm data.
Tests must derive their expected configuration from the actual committed table
and separately assert these calibration inputs; no no_clearance/smaller-radius
fixture can certify placement.

## Exact future owned files and compatibility

Register all of the following before product implementation; this contract owns
only itself. No implied ownership outside this list:

- `scripts/engine/army_ground.gd`: three candidate entries, bounded search,
  lifecycle metadata staging and receipt transaction; ordinary entries unchanged.
- `scripts/engine/army_split.gd`: initialize wrapper only; preserve existing
  split/opening_sources/cache results and ordinary new-campaign call graph.
- `scripts/engine/enemy_ai.gd`: spawn candidate wrapper only; ordinary spawn,
  arrival, strategy and marching untouched.
- `scripts/engine/unit_bodies.gd`: validation-only placement boundary/control,
  reuse raw-copy/owner/count/circle validation, no new query/migration writer.
- `tests/engine/test_body_placement.gd` and
  `tests/engine/test_body_placement.gd.uid`: new tests and local fixtures only.
- `tests/engine/test_unit_bodies.gd`: raw placement-control and exact frozen
  boundary preservation tests; do not relax old assertions.
- `tests/categories.json`: append only test_body_placement.gd to engine-military
  patterns, preserving gameplay precedence and every existing category/gate.
- `scripts/engine/guide/body_placement.md` (new): implemented candidate rules.
- `scripts/engine/guide/regiments.md`: one short topic reference to new guide;
  no old-topic move, history rewrite or production rule replacement near cap.
- `scripts/engine/guide/cluster_formations.md`: short validation/control entry
  for UnitBodies, with reference to body_placement guide. No broad rewrite.

No new class/script UID, BodyMotion algorithm, ArmySystem, DayResolution,
TickEngine, GameState/save loader, Game, CampSystem, personnel system, CSV,
shared fixture, renderer, battle or damage path is authorized. Reuse the actual
ArmySystem terrain helper; do not refactor it for this step. If that helper
cannot validate stationary paths or the exact boundary needs an additional
writer, stop with concrete evidence for dispatcher scope/split registration
before editing another path. New control is passively serialized inside the
existing military_migration Dictionary; current raw loader preservation must
be proved by tests, never assumed or worked around by schema defaults.

Ordinary API return types (`settle/leave/reconcile/spawn` void, `take_seat` bool,
`refill` String, split Dictionary) stay compatible. A source/caller scan must
prove none calls these candidate entries. Future atomic activation alone binds
boot, migration/load publication, courier seats, all arrivals/halting/retreats,
AI spawn and personnel/split/recruit to their candidate transactions. No live
partial switch, feature flag, permanent fallback or second position writer.

## Executable future acceptance (not executed in this doc PR)

Use SuiteData.repo/campaign copies, production footprint/ring settings and local
MarchPath.build/use grids with real bounds. No DataRepository.load_all or global
fixture edits. First run new tests red for absent APIs, then green. Required
named scenarios in test_body_placement.gd:

- `test_home_counts_and_identities`: full/901/900/1/0 fit => 10/10/9/1/0 rows at
  group size 100, exact sum; ten homes and same width/depth always. Kill tail,
  regrow, prove slots never reused and survivors/path/history unchanged;
  901 partitions [100 x9,1], 900 [100 x9]. Verify invalid >capacity refuses.
- `test_all_realms_and_overlapping_rectangles`: crown, royal, all foreign land
  units and enemy against the same algorithm; genuine table-selected radii.
  Construct overlapping deployment rectangles with disjoint home circles,
  accept them; 1854/1853 infantry separation accepts/rejects. Every pair,
  including already occupied battle bodies and first enemy, is checked.
- `test_finite_space_and_terrain`: blocked preferred home finds first exact
  deterministic legal lattice point; permuted dictionaries produce same plan.
  Fully occupied neighborhood defers with space reason and unchanged counters.
  Water, scarp, edge-grazing circle, out-of-bounds, missing grid and int64
  overflow fail closed; no any-terrain fallback, tiny radius or forced start.
- `test_existing_pose_is_authority`: legal off-home rows/paths remain exact
  across migrate/read/initialize/camp/leave/reconcile, including arbitrary
  facing. A seat swap requiring movement defers unchanged; candidate march
  walks actual polyline and pays its existing cost, then seat claim completes
  without another metre or debit. No direct ground teleport is permitted.
- `test_missing_vs_corrupt_and_old_load`: legal absent legacy whole store at
  safe boundary obtains explicit request then placement; legal existing legacy
  poses preserve their points and authorized regroup history. Present empty
  positive-fit, current missing, duplicate owner/home/slot, future/null markers,
  corrupt counts/paths, partial battle map and retired-slot reuse error. Test
  current GameState.to_dict -> JSON -> from_dict on initialized campaign and
  compatible legacy candidate; controls retain raw invalid values for rejection.
  Test zero-fit empty store separately from missing positive-fit corruption.
- `test_recruit_split_and_host_once`: real staged MilitaryRoster fit transition
  900->901 allocates one row, no personnel creation; pending retry completes
  placement without repeating cohort or money operations. Loss/recruit cycles
  keep counter monotonic. Real bootstrap split provenance/halves and host_units
  resolve exact counts, no duplicate regiments/foes. Host spawn failure keeps
  mind/seat/rations/RNG exact. Existing bodies cannot respawn at host start.
- `test_plan_raw_stale_atomic_json`: source/nested paths/RNG/save-file bytes
  unchanged on every plan, successful detached result and rejection. Change
  grid/config/owner/fit/seat/command/supply or one plan coordinate/count/effect:
  commit errors and publishes nothing. Closed controls reject bool/fractional/
  numeric-string confusion, unknown keys/version, stale/skipped sequence, wrong
  boundary and forged receipt. Exact original-plan direct/JSON retries return
  unchanged detached candidate with no law/cost/slot/personnel duplication;
  convenience retry errors as specified. Include a valid import_main_v7
  migration record and prove successful placement control with IDs
  `placement:i42` and `placement:f3ff0000000000000` survives to_dict -> JSON ->
  from_dict unchanged and exact commit retry remains a no-op. Reject empty
  suffix, missing prefix, `i42` and `f3ff0000000000000` in both raw requests and
  saved controls before planning/retry. Mutate output and prove no alias.
- `test_saved_boundaries`: ordinary frozen day/round with valid legacy rows
  defers preserving payload; malformed frozen controls error before deferral.
  Completed CF04a candidate at exact receipt allows metadata-only leave/camp;
  nonfinal boundary, wrong day/receipt or pending encounter reject/defer as
  specified. Missing/growth/spawn never bypass frozen validation. Inner/outer
  march receipt, budgets, journal, arrivals and costs stay byte-equivalent.
- `test_production_inputs_and_dispatch`: current actual campaign incl. crown,
  royal, foreign and all hosts, actual roster/terrain/radii must initialize,
  roundtrip and remain physically valid; missing space yields reproducible
  input-specific failure evidence requiring resolution, not an accepted fixture
  substitute. Check source call graph preserves all ordinary dispatch. This
  candidate test does not certify ordinary boot/save activation.

Product commands, under the project shared Godot lock (see cicd_procedure.md):

```sh
./run_tests.sh --test tests/engine/test_body_placement.gd
./run_tests.sh --test tests/engine/test_unit_bodies.gd
./run_tests.sh --test tests/engine/test_body_motion.gd
./run_tests.sh --test tests/engine/test_body_marches.gd
./run_tests.sh --test tests/engine/test_army_ground.gd
./run_tests.sh --test tests/engine/test_army_seat.gd
./run_tests.sh --test tests/engine/test_enemy_spawn.gd
./run_tests.sh --test tests/engine/test_army_split.gd
./run_tests.sh --test tests/engine/test_military_save.gd
./run_tests.sh --test tests/engine/test_battle_save.gd
./run_tests.sh --test tests/engine/test_save_load.gd
./run_tests.sh --test tests/engine/test_recruitment.gd
./run_tests.sh --test tests/engine/test_law_military.gd
./run_tests.sh --test tests/engine/test_army_clearance.gd
./run_tests.sh --test tests/engine/test_defeat.gd
```

Include affected selector/runtime/current-HEAD CI. Product PR must explicitly
include `GUT_INCLUDE: gameplay`; clearance is gameplay-classified and cannot
silently skip. Keep original assertions/fixtures/thresholds. At activation run
unedited road interception/defeat continuation and actual production boot/load,
reorganization and personnel/cost determinism checks on final frozen inputs;
classify and resolve failures rather than accepting old or candidate evidence
as a new PASS. No routine full local suite for this document.

## Retained completion gates

Inherited frozen selector: 437 scripts, 4504 tests, 4443 pass, **55 fail,
6 risky/pending**, exit 1/runtime FAILED; input SHA256
`19bd7a5b9deb50a1bb1820aac2348e9e20adb8400484d1e3ab6e0729da2fbfb5`.
P3 evidence concerns the old route only. Current-campaign overlap, road/defeat
and ranged eligibility require actual resolution/acceptance in their mapped
steps and atomic activation. CF01 finite 17 pose samples and artillery infantry
substitute remain limits; changed art/input requires new calibration evidence.

All twelve spec §9 gates remain: ten/count/fixed footprint; real-radius sweeps
through turns/reload; eight-formation eligibility; independent speed/local
budgets; delivered command versions/real king/courier movement; vulnerable
assembly/stable old lines; expansion/reform/unique membership; all eight normal,
blocked and member-loss behaviors; physical melee/ranged occlusion/explained
nonduplicated bonuses; save/speed/camera/cost/personnel determinism; reproducible
formation-vs-none/countered outcomes; unique 3D-map real-window visual/performance.
Eight playable formations and the complete chapter are not waived by staging.

Activation must preserve legal old archives in place, original paths, identities,
people and paid costs, explicitly place compatible missing poses before world
publication and reject corrupt/overlapping/future saves without modifying the
file or live state. It must also succeed for a real new current campaign boot
and save/load, switch all writers together, and complete real-window
visual-review/performance on live inputs. CF04b's candidate API cannot declare
that production work complete or reject legitimate missing fields to avoid it.

This document's acceptance is source/API/schema trace, precise future ownership,
executable negative/hand-check matrix, retained requirements, doc whitespace,
selector, harness/config/guide-cap checks, independent Review and required
current-HEAD CI. It runs no Godot and claims no product/visual/performance PASS.
