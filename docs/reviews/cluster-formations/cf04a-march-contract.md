# CF04a candidate march contract

Step `CF04a-contract`, 2026-11-01. Documentation only, based on main
`f56cc5b2bbaa0c95437f6e46ce9ee369eba55cef`. Implementation owner
`01a192b7-2596-7723-8c7e-d861f2fc2ea2`; dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`. Only the dispatcher registers product
work after this contract's independent Review and required current-HEAD CI.
This document supplies the missing exact candidate interface from #187. It does
not replace the approved Task CF04a, mark runtime acceptance passed, or activate
production. Accepted prerequisites are CF02R-foundation (#191), CF03R-planner
(#192), and CF02-rollout-plan (#187); historical draft wording in the latter
is not a new request for human approval.

## Source and bounded reach

Read against the actual merged files, not old unmerged product trees:

- `docs/superpowers/plans/2026-10-25-cluster-formations.md`, Task CF04a and staged
  mapping; `docs/reviews/cluster-formations/cf02-rollout-boundary.md`, CF04a and
  activation; `docs/superpowers/specs/2026-10-25-cluster-formations-design.md` §9.
- `docs/reviews/cluster-formations/cf02-foundation-contract.md`, its
  `cf02-foundation-amendment.md`, and `scripts/engine/guide/cluster_formations.md`:
  sole-owner rows, complete candidates, frozen transactions and passive saves.
- `scripts/engine/unit_bodies.gd`: `migrate_candidate`, `_migration`, `_frozen`,
  `_copy`, `rows`, `transfer_candidate`. The existing public migration remains
  deferred for frozen transactions. Transfer is structural, not geometry proof.
- `scripts/engine/body_motion.gd`: `plan`, `commit`, `_saved_ok`, `_segments`,
  `_distance_ceil`. These are the actual swept planner and receipt authority.
- `scripts/engine/army_system.gd`: `day_walk_budget`, `march_day_saved`,
  `_march_one`, `_publish_march_state`, `route_m_of`, `march_ahead`, `eat_one`;
  `scripts/engine/unit_gait.gd`: `refresh`, `pays_run`, `run_step_m`.
- `scripts/engine/tick_engine.gd`: `resolve_day`, `_resolve_phase`,
  `_resolve_battles`; `scripts/engine/day_resolution.gd`: `begin`,
  `incompatibility_reason`; `scripts/engine/march_path.gd`: `of_pack`, `clear`,
  `cells_on`, `cell_of`; `scripts/engine/game_state.gd`: `to_dict`, `from_dict`.

Existing movement freezes daily entries/budgets, splits integer remainders,
advances crown then foes, and pays running supply before walking. Day-end food
is a separate SUPPLY_AND_CONDUCT phase. `BodyMotion` instead reserves all bodies
in one relative sweep, returns actual polylines, and commits only rows and its
receipt. It neither validates terrain nor updates anchors, march budgets or
supplies. Existing `MarchPath.cell_of` clamps out-of-map points; `clear` alone
therefore does not prove bounds. Existing routing may return a straight fallback
when no terrain route exists; that fallback is not candidate clearance proof.

## Real prerequisite gap: explicit MARCH boundary

Today `UnitBodies._frozen` returns true for every nonempty `day_resolution` or
live pending round. Consequently current `BodyMotion.plan/commit` cannot execute
a saved tactical MARCH boundary, even in an isolated candidate. Calling them on
a world with the transaction deleted, swapping the old anchor mover underneath,
or adding a wrapper which claims this already works is forbidden.

The minimum bounded product amendment is a **validation-only** foundation entry
and optional boundary argument on the real planner. These are proposed additions,
not APIs already present:

```gdscript
# UnitBodies; same closed result shape as migrate_candidate.
static func validate_march_candidate(repo: DataRepository, source: GameState,
        boundary: Dictionary) -> Dictionary
# BodyMotion; existing callers retain exactly their current behavior.
static func plan(repo: DataRepository, state: GameState, intents: Array,
        abs_day: int, substep: int, march_boundary: Dictionary = {}) -> Dictionary
static func commit(repo: DataRepository, state: GameState, proposed: Dictionary,
        march_boundary: Dictionary = {}) -> Dictionary
```

The nonempty boundary is exactly `{version: 1, abs_day: int, substep: int}`;
nonnegative raw whole integers exclude booleans, NaN and fractions. It must match
the saved candidate-only transaction described below and the planner cursor.
Validation requires current `body_version`, complete existing current-schema
rows, unambiguous sole ownership, canonical counts, measured nonoverlap and no
pending reconciliation, placement, decision or live battle round. It performs
no schema conversion, regroup, transfer, slot allocation, normalization or pose
creation. A valid explicit MARCH boundary may return `complete` with an exact
detached clone despite the day transaction; all other frozen inputs remain
`deferred` (invalid inputs remain `error`). The frozen payload is retained and
validated before and after the row update. Reuse foundation's actual validators
and copier; do not duplicate a weaker body validator. Existing
`migrate_candidate` and empty-boundary planner calls keep their frozen rejection.

The actual planner's replan, full-plan hash comparison, saved receipt, relative
sweeps and final physical validation remain authoritative. Its boundary-aware
basis additionally binds the boundary; commit must use the same validation path
for both source and final candidate. This amendment does not authorize battle
movement, damage, lifecycle, production load or Game changes. Exact additional
files and the negative tests are listed below. Product registration must include
this reach; without it CF04a is blocked, not implementable in its original five
paths. No third architect or new owner is needed to resolve this known gap.

## Exact candidate entry points and wire outcomes

The four transaction entries and DayResolution validator are new and explicit. Ordinary march/prediction signatures,
`TickEngine.resolve_day`, production call routing, save constants 7/6 and Game
publication remain unchanged. No feature flag or legacy fallback selects them.

```gdscript
# TickEngine instance already owns DataRepository as data.
func begin_body_march_candidate(source: GameState) -> Dictionary
func step_body_march_candidate(source: GameState) -> Dictionary
# ArmySystem, engine-pure queries/transactions.
static func plan_body_march_candidate(repo: DataRepository,
        source: GameState) -> Dictionary
static func commit_body_march_candidate(repo: DataRepository,
        source: GameState, proposed: Dictionary) -> Dictionary
# DayResolution, explicit validator; the existing validator rejects this marker.
static func body_march_incompatibility_reason(tx: Dictionary) -> String
```

All results have exactly `{status: String, reason: String, candidate: GameState,
plan: Dictionary}`. Status is `complete`, `deferred`, or `error`. `error` and
`deferred` have null candidate and empty plan. Planning success has null candidate
and a plan; begin success has a detached candidate and empty plan; commit/step
success have a detached candidate and the accepted plan; an exhausted-day step
is an unchanged detached candidate with empty plan and a completion reason.
A stationary/partially
blocked legal plan is `complete` with causal per-body reasons, not a transaction
error. Every result leaves source, its nested arrays, RNG and source save file
unchanged; only a later explicit consumer may replace its candidate reference.
`BodyMotion.commit` mutates a private working clone inside this transaction,
never the supplied source or production state.

Begin accepts only an explicitly initialized, complete, unfrozen current-body
world. It validates before invoking any legacy helper which might initialize
state. It copies the existing daily march setup calculation on the clone,
including eligible received departures and frozen routes/budgets; it does not
run WORKS, couriers, AI, battle, settlement, economy or the calendar. This is a
march-only harness boundary, not a second day resolver. Existing orders, camp
packing deadlines, command changes and retreat authorization are respected.
Absent/malformed bodies do not invoke `ensure`, placement or migration repair.
Repeated begin on an open candidate day is deferred unchanged; resumption uses
step, never begins today's budget again.

The candidate transaction uses the existing DayResolution v4 phase/order header,
positioned at FIXED_TACTICAL_SUBSTEPS, `battle_step == ""`, with no pending
encounter/round and the existing `march_entries`, `march_budgets`, `marching_codes`
and journal. Add exactly one candidate-only `body_march` control record to that
transaction. `DayResolution.incompatibility_reason` must reject a present
`body_march` before ordinary `resolve_day` performs any mutation; only the new
explicit validator accepts it. It checks the usual v4 header as well as this
extension. This prevents accidentally feeding a candidate save into the old
production mover. No v3/legacy frozen transaction is relabeled or resumed by the
candidate route.

`step_body_march_candidate` is plan then commit, with no other movement or cost
writer. It processes one saved MARCH slice only, across all eligible crown,
royal regiment, foreign and foe units together. Royal here means an army unit;
the king's personal `king_state` travel remains outside CF04a. Legal withdrawal
uses `BattleSystem.may_withdraw` and the same planner; an unauthorized combatant
stays an obstacle. It must not call `BattleGroups.follow_anchor/translate`,
`ArmyGround.settle`, battle discovery, round execution or any refresh which
creates/moves bodies. Arrival records an arrival at its actual legal point;
placement/settlement belongs to CF04b, contact/battle to CF05. Prediction invokes
these same entries on detached candidates, never `march_ahead` followed by a
body correction. Ordinary public predictions remain on their existing route
until activation.

## Saved control and plans

`day_resolution.body_march` is closed:

```text
{version: "1", abs_day: String, next_substep: String, substep_count: String,
 last: {} | {substep: String, receipt: String}}
```

Strings are canonical nonnegative decimal int64, not numeric Variants; version
is exactly `"1"`. They avoid the loader's legacy `_whole` rounding, as the
existing motion cursor does. Counts and indices agree with the v4 header;
`0 <= next_substep <= substep_count`, count positive. Last is empty initially,
otherwise exactly the preceding substep and a lowercase SHA256 full march-plan
receipt. Unknown, null, future, fractional/numeric controls or inconsistent
receipts/cursors are errors. The daily entries/budgets stay in their existing
saved tables; do not duplicate poses, personnel or paid-cost ledgers here.
At the final slice, retain the completed candidate transaction (index == count);
step returns the same candidate unchanged and does not start tomorrow, clear
frozen inputs, eat food or advance the calendar. Activation must bind this
explicit boundary into the real phase machine; this harness is not boot wiring.

A march plan is exactly:

```text
{version: 1, abs_day: int, substep: int, basis: String,
 motion: Dictionary, units: Array[Dictionary], arrivals: Array[String]}
```

`motion` is the unchanged actual `BodyMotion` result shape
`{moves, blocked, reasons, cursor}`. Each sorted unit row is exactly
`{unit: String, anchor_path_m: Array, used_m: int, step_budget_m: int,
 entry_after: Dictionary, saved_entry_after: Dictionary}`. Entry dictionaries
retain existing extension fields, but are proposals, never trusted assignments.
All path points are whole int64 pairs. Basis hashes canonical source save,
explicit boundary, relevant march/gait/footprint/motion settings and the actual
terrain grid/bounds content. Use sorted-key canonical hashing as in BodyMotion;
integer-valued JSON floats canonicalize to integers. Terrain cache identity or
map id alone is insufficient. Supply, command, route, owner, row, grid or budget
changes invalidate an uncommitted proposal.

Commit first validates source and closed raw controls. At the same saved last
cursor, an identical whole-plan receipt returns a detached unchanged source
without calling gait, planning, movement or supply again (direct and JSON retry).
A different receipt at that cursor, older cursor, future/skipped substep, wrong
day, unknown schema or stale basis fails unchanged. Otherwise it independently
replans from source, compares the entire canonical plan, and applies only that
result to its private clone. Do not replan a retry against already moved poses.
`BodyMotion` retains its own exact receipt and priority strings under
`military_migration.body_motion`; the inner receipt is the hash of `plan.motion`, while the outer receipt is the
hash of the full march plan; their cursors must agree on the committed slice. An absent outer receipt with a same-slice inner receipt is corruption,
not permission to finish half a transaction. Restoring before or after any slice
must yield the same next move, cost, priority, counts and RNG as uninterrupted
execution. No durable state exists between body commit and outer publication.

## One movement, one cost, one publication

1. Validate and snapshot the complete candidate and frozen input tables. Gate
   movement by capture, received order, camp packing, battle/withdrawal and
   existing command-version rules. Do not consult hidden knowledge for gait or
   treat all foreigners as hostile. Derive hostility from existing relationships
   and engagement rules; friendly bodies may yield, opponents cannot bypass as
   friendly. Include stationary and nonmoving bodies as planner reservations.
2. Preserve the existing integer daily-budget/remainder calculation and its
   saved `day_walked_m`/`march_step` meaning; call actual gait selection/payment
   once on the private clone, then `run_step_m` once when affordable. No budget
   is first spent by `_march_one`/`MarchRoute.along` and spent again by bodies.
   Each body receives its unit's one slice allowance, not allowance divided by
   personnel or multiplied by ten. Frozen ordinary routes are desired paths,
   not proof of safety. Translate their polylines from each authoritative body
   point using its existing offset from the anchor; keep stable slot/home IDs.
3. Invoke the real BodyMotion once for the simultaneous world slice, using
   the cost-staged private clone as its basis in both plan and commit. Its
   per-body `used_m` is the sum of ceil Euclidean lengths of **every travelled
   segment**, including sidesteps. Unit `used_m` is the maximum of its bodies'
   used metres (simultaneous movement, not their sum); increment the existing
   actual-distance counter once. Each body's used distance must be <= its one
   allowance. Last-slice remainder and running must not refund detour metres,
   grant a second allowance, or use an endpoint chord as distance. Waiting
   bodies use zero; a positive-cost run retains the existing pays_run semantics
   even if reservations subsequently make it wait. Reservation/replan never
   pays again. Existing running `supplies/run_supply_rem` changes are part of
   this same transaction, with the daily base meal reserved by UnitGait.
4. Anchor progress is conservative route progress shared by all extant bodies:
   for each body, measure the greatest ordered prefix of its requested,
   translated route it actually reached; a sidestep earns forward progress only
   when it rejoins that route. Take the minimum across the unit, retain zero
   for no bodies, and advance the anchor along the corresponding original
   route prefix. Include all crossed corners in `anchor_path_m`; no endpoint
   shortcut. The anchor is command/route metadata, never a replacement collision
   body. A lagging body can hold anchor progress while other bodies have moved;
   their exact poses/paths persist and are next slice's starts, never snapped
   back to home slots. No automatic arrival/last-metre teleport is allowed.
5. Validate terrain and map bounds for all actual body segments, including
   sidesteps and stationary endpoints, and for anchor_path_m. Use the measured
   CF01 swept-circle envelope for body ground/bounds, not just a center ray;
   a circle cannot cross closed/water cells or extend outside the map. Test
   touched grid-cell rectangles against the swept disc, corners included.
   `MarchPath.clear/cells_on` can supply centerline traversal but are not by
   themselves disc clearance. Check raw bounds/overflow before Vector2i
   conversion or clamped `cell_of`; do not wrap whole-metre positions into
   int32. Candidate marches with no valid terrain grid fail with a clear reason;
   test grids are explicitly injected through existing `MarchPath.use`.
   Do not open each sidestep endpoint's closed cell or accept routing's unsafe
   straight fallback. A returned forbidden segment rejects the **whole slice**
   unchanged with terrain/bounds reason; never trim a plan after sweep proof or
   commit some units. Later route search can be separate, not silent bypass.
6. Commit BodyMotion on the clone using the explicit boundary, then apply the
   independently computed anchors, exact remaining routes, command-preserving
   entry updates, actual budget use, gait/supply remainder, arrivals and outer
   cursor/receipt together. Final validation proves whole-world geometry,
   sole ownership, terrain, control consistency and unchanged personnel/RNG.
   Publish only the detached result after every check passes. A failed final
   check discards all clone changes, including paid running costs.

This preserves the existing writer and formulas for costs; it adds no per-body
meal, order fee or monthly settlement. Day-end `eat_day`/enemy food remains in
SUPPLY_AND_CONDUCT, not moved into a MARCH slice. This step's supply tests cover
running and unchanged/reserved base food; full-day food replay remains required
at activation. Pursuit/range limits must constrain desired routes before the
sweep and be credited once from actual legal movement, never from reservation
length. No new damage, fatigue, regroup, role or deployment algorithm is added.

## Exact future product ownership

Original CF04a paths, fully qualified:

- `scripts/engine/army_system.gd`
- `scripts/engine/tick_engine.gd`
- `scripts/engine/day_resolution.gd`
- `scripts/engine/guide/regiments.md`
- `tests/engine/test_body_marches.gd`
- `tests/engine/test_body_marches.gd.uid` (new Godot script identity)
- `tests/categories.json`: append exactly `tests/engine/test_body_marches.gd`
  to engine-military patterns. Do not let the engine-core fallback misclassify
  this military contract or alter existing expensive-category precedence.

Necessary bounded amendment for the real frozen-boundary gap, to register
explicitly before product work:

- `scripts/engine/unit_bodies.gd`: validation-only explicit march boundary;
  retain existing migration deferral and reuse the same physical validators.
- `scripts/engine/body_motion.gd`: optional boundary, direct validation and
  boundary-bound replan/basis in the actual plan/commit implementation.
- `tests/engine/test_unit_bodies.gd`: frozen-boundary authorization and exact
  preservation/deferral tests; no fixture threshold changes.
- `tests/engine/test_body_motion.gd`: actual planner boundary commit, atomic
  rejection and direct/JSON receipt tests, retaining existing sweep tests.

No other file is implied: no Game/save loader, MarchPath, UnitGait, ArmyGround,
EnemyAi, BattleGroups, renderer, data, asset, old fixtures, original plan or
foundation contract edits. New pure terrain checks stay in ArmySystem and new
fixtures stay in test_body_marches. If implementation shows another essential
path or exceeds this bounded transaction, stop and give the dispatcher the
exact reason/split before touching it; do not accumulate placement/battle work.

## Executable red/green acceptance for product implementation

Use SuiteData copies and personnel helpers; initialize explicit legal rows in
new test setup only and prove foundation completion. No `load_all`, reduced
production radii or old failing-fixture edits. Tests below are short functional
contracts, classified engine-military. They are **not executed by this doc PR**.

- `test_real_boundary_not_wrapper`: ordinary frozen migration and empty-boundary
  BodyMotion defer/reject; exact candidate MARCH boundary validates unchanged
  frozen payload and commits real swept movement. Wrong phase/day/substep,
  pending decision/round, legacy/future version, missing/pending/ambiguous rows
  fail unchanged. Never delete tx to make validation succeed.
- `test_opposed_and_three_way`: two head-on and three crossing friendly units,
  permuted input order, one simultaneous slice; use actual configured CF01
  radii and full ten rows plus 901/900/1/0 cases. Check minimum continuous
  separation for every relative segment interval, not only endpoints, finite
  wait reasons and stable priority. Legal overlapping deployment rectangles
  cannot become an unconditional unit wall. A constructed body gap must admit
  progress; a sealed pocket must wait without repeated retreat/replanning.
- `test_hostile_and_withdrawal`: same map/body inputs with enemy relationships
  must block hostile through-passage; lawful retreat moves by the same sweep,
  illegal retreat does not. This certifies candidate interception geometry,
  not production contact discovery or battle victory. Crown/royal/foe setup
  changes table ownership only, not algorithm or radius rules.
- `test_budget_and_supply_once`: different unit allowances; hand check an L
  path [0,0] -> [3,0] -> [3,4] costs 7, not 5, and diagonal [0,0] -> [1,1]
  costs 2. Include a real planner sidestep. Max body usage debits a unit once;
  no sum-of-ten debit, last-slice refund or second run multiplier. With
  fixture run_supply_permille=2000, ten slices, base/run bite=100 and zero
  remainder, one run charge is 10 supplies; replay charges zero. At supplies
  100 the reserved base meal prevents that charge and the slice walks. Blocked
  successful run preserves paid-run semantics; rejected terrain plan restores
  supply/remainder. Base food is unchanged in every MARCH slice.
- `test_polyline_terrain_and_bounds`: inject a MarchPath.build/use land grid;
  requested centerline legal but planner sidestep crosses water/scarp; reject
  entire result. Also reject a circle grazing a forbidden cell, out-of-map
  side leg, int32-wrap attempt and missing grid; accept legal multi-corner
  routes and exact legal body-to-body tangency. Validate **all** returned legs, not the
  anchor's old direct route. No fallback/snapping fixes failed geometry.
- `test_atomic_stale_and_json`: source equality/RNG/personnel/slots before and
  after plan, rejected commit, altered unit/plan/path/grid/config, wrong cursor,
  duplicate receipt and completed-day retry. Before/after every one of ten
  slices, GameState.to_dict -> JSON -> GameState.from_dict; resume without
  replay, same hashes, counts, actual polylines, supplies and priorities.
  Numeric/fractional/null/future saved controls cannot normalize into valid
  receipts. Mutating output paths/entries cannot mutate source.
- `test_received_orders_and_prediction`: packing deadline, changed/newer march
  or cancel, law-in-force gait/supply and pursuit bounds remain effective;
  prediction matches committed candidate paths while source stays unchanged.
  A current campaign with explicitly initialized candidate rows can roundtrip;
  this is not evidence production boot initializes bodies. Ordinary entry
  source/call-graph checks prove none dispatches to candidate APIs pre-activation.

Run the new file first red (absent APIs), then green; include foundation/motion
boundary tests and original ordinary-march/save/law regressions without edits:

```sh
./run_tests.sh --test tests/engine/test_body_marches.gd
./run_tests.sh --test tests/engine/test_unit_bodies.gd
./run_tests.sh --test tests/engine/test_body_motion.gd
./run_tests.sh --test tests/engine/test_army_march.gd
./run_tests.sh --test tests/engine/test_day_resolution.gd
./run_tests.sh --test tests/engine/test_day_resolution_substeps.gd
./run_tests.sh --test tests/engine/test_unit_gait_march.gd
./run_tests.sh --test tests/engine/test_law_military.gd
./run_tests.sh --test tests/engine/test_army_clearance.gd
```

Use the shared Godot lock and frozen relevant-input evidence. The clearance
suite is gameplay-classified; the product PR must explicitly request
`GUT_INCLUDE: gameplay` and meet the affected selector/current-HEAD CI, not
report a skipped suite as passed. No routine full local suite for this document.

## Retained end-state acceptance and evidence

This contract clears no inherited product failure: frozen 437-script run had
4504 tests, 4443 pass, **55 fail and 6 risky/pending**, exit 1 and FAILED runtime
gate, input SHA256
`19bd7a5b9deb50a1bb1820aac2348e9e20adb8400484d1e3ab6e0729da2fbfb5`.
UNKNOWN/cascades, road interception, defeat overlap, current-campaign placement
and ranged eligibility still require classification/resolution. CF01's finite
17 animation samples and artillery infantry substitute remain limits. No
radius, fixture, gate or compatibility requirement is weakened here.

All twelve spec §9 items remain required: (1) ten bodies/count conservation and
fixed footprint; (2) real-radius clearance/yielding through turns and reload;
(3) eligibility for all eight formations; (4) independent speeds, assembly and
local budgets; (5) courier/king command versions and real reposition time;
(6) vulnerable assembly and stable existing lines; (7) expansion/reform/partial
selection and unique membership; (8) all eight normal/blocked/member-loss
behaviors; (9) physical melee, ranged occlusion and explained nonduplicated
bonuses; (10) save/speed/camera determinism, costs and old personnel;
(11) reproducible formation-versus-none and countered-formation outcomes;
(12) actual unique 3D-map real-window visual/performance acceptance.
CF04b owns placement, CF04c owns path rendering, later steps own battle/damage,
formations and activation. Final activation still requires real new-game
boot/save/load, legal old-save compatibility, all production writers switched
together, unedited road/defeat checks and real-window visual-review. Candidate
march success cannot pre-clear any of those or the rest of P4.

This document's acceptance is source/API trace correctness, bounded owned paths,
executable future tests, unchanged end-state obligations, whitespace/selector
and harness/config/guide checks, independent Review and current-HEAD CI. It runs
no Godot and makes no visual, product or performance PASS claim.
