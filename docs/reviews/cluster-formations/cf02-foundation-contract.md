# CF02 passive foundation contract

Step `CF02F-contract`, 2026-10-26. This document resolves the technical entry
contract required by PR #187; it implements no runtime behavior. The human
approved staging and preservation followed by superseding old CF02. PR #187
merged at `4ac809c8a5884ed161ee320e84080d7ea853a9c0`. Old CF02 is
superseded/unmerged/incomplete, never an accepted dependency. CF01, CF08 and
CF02-rollout-plan are accepted. The rollout document's draft-era questions are
historical context; this contract settles the foundation questions below.
Only the dispatcher registers successors, their exact files, owners and dependencies.

## Evidence and limits

Read-only source: old worktree
`/Users/samuelzhang/.codex/worktrees/cluster-cf02/game_design`,
`.superpowers/cluster-cf02/retirement-preservation/interface-handover.json`,
SHA256 `703ad3afa1c28e8c6fd10d17914f1d40dbd61262e39ec4f73842d44a9181b0dd`,
and `preservation.json`. The latter records all 37 original source hashes matching,
no PR, and preserved unmerged WIP. Selected `unit_bodies.gd` source was read to
resolve semantics, not copied or accepted. Its `migrate` publishes to its argument
and calls `refresh` to invent absent poses; `enter/leave/transfer` mutate supplied
dictionaries. Those are rejected as the candidate contract. No patches, original
fixtures or source-tree files are modified by this step.

The frozen selector remains FAILED: 437 scripts / 4504 tests, 4443 pass,
55 fail, 6 risky/pending, exit 1, runtime gate FAILED. Input SHA256
`19bd7a5b9deb50a1bb1820aac2348e9e20adb8400484d1e3ab6e0729da2fbfb5`;
boundary manifest `9d4dfef057c6ad131ec0f7aa5b7f3ae68e028ea74da24bec0e7f675426a26ee3`.
UNKNOWN and cascades remain unresolved. Foundation tests do not clear actual
road interception, defeat overlap, fresh-campaign horse overlap or ranged
eligibility failures. All 55 and all 6 require classification and resolution at
activation, with no exclusions or weaker radii, fixtures or gates.

## Exact public foundation API

All operations belong to `class_name UnitBodies extends RefCounted`. Typed
GDScript signatures are normative; Dictionary wire shapes below are closed for
control fields. Saved row extension fields are preserved by deep copy.

```gdscript
static func rows(repo: DataRepository, state: GameState, unit: String) -> Array[Dictionary]
static func footprint(repo: DataRepository, unit: String, state: GameState) -> Vector2i
static func home_slots(repo: DataRepository, state: GameState, unit: String) -> Array[Vector2i]
static func migrate_candidate(repo: DataRepository, source: GameState) -> Dictionary
static func transfer_candidate(source: GameState, unit: String, from_battle_id: int, to_battle_id: int) -> Dictionary
```

`rows` returns a deep detached snapshot from the one existing owner:
`battle.groups[unit]` if a live battle contains the unit, otherwise the unit
entry's `body_groups`. No second store, refresh, reconciliation or lazy creation.
Missing bodies return an empty array; callers must not interpret that as a valid
initialized unit. Ambiguous ownership or malformed rows return empty, without
repair; candidate validation supplies the diagnostic. `repo` may be null for
`rows`. `footprint` is fixed measured width/depth, independent of fit; unknown or
invalid configuration returns `Vector2i.ZERO`. `home_slots` returns all ten local
integer offsets even at zero fit; invalid configuration returns empty. These
last two queries require a non-null repo and consume no RNG.

Candidate results have exactly `status: String`, `reason: String`,
`error: String`, `candidate: GameState` (nullable), and
`placement_requests: Array[Dictionary]`. Status is one of:

- `complete`: validated detached candidate; empty error and requests.
- `needs_placement`: validated detached partial candidate and sorted explicit
  requests; empty error. It is compatible legacy input, not a load failure or a
  publishable physical world.
- `deferred`: frozen transaction cannot yet be converted; null candidate, empty
  requests, nonempty reason, empty error. Source and frozen payload stay exact.
- `error`: null candidate, empty requests, nonempty error and causal reason.

Every candidate is a complete detached GameState, including nested row paths,
unit tables, battle records and RNG state. Use the existing lossless save copier
only where it preserves the input; copying must not call campaign creation,
reorganization or physical refresh. No reference in a result aliases source
mutable data. Mutating any result must not mutate source and vice versa.
There is no public `migrate(repo,state)` mutator, candidate `refresh`, boolean
activation flag, or public partial-field commit in this foundation.

`migrate_candidate` validates raw body values before numeric normalization;
finite integral JSON numbers become ints, fractional/nonfinite/string/bool
values fail. It preserves every existing legal world point, path, identity,
role, facing, personnel, paid cost and frozen cursor. It validates all present
body envelopes against measured configuration and each other, including units
awaiting placement's already present neighbors. Existing overlap is an error,
never repaired. It never adds a world position. Repeated migration/JSON replay
is idempotent; source state and RNG remain byte-equivalent on every status.

`transfer_candidate` requires initialized current body schema and returns only
`complete`, `deferred` or `error`. Battle ID `0` means the nonbattle entry;
positive IDs resolve existing battles by ID inside source, never caller-owned
dictionaries. Negative/unknown IDs, same endpoints, wrong source membership,
occupied destination, duplicate owners, missing required rows or incompatible
schema fail atomically. The candidate moves the exact rows and body ownership
metadata, updates the unit's att/def membership using its original side for merge
and realm allegiance for entry, and removes only source per-unit body metadata.
An entry to a battle without one unambiguous matching realm side fails. Exit
removes membership but does not delete a battle/unit. It preserves order receipts,
terms, supply, personnel, anchor, slot counter, paths and costs; source battle
must survive until its caller has consumed the successful candidate. Destination
may already contain other valid units, whose records remain exact. An identical
replay against the result returns `complete` unchanged only when source has no
membership/rows and destination has the exact requested unit owner; otherwise
it errors. No configuration lookup, layout or movement occurs; repo-null end or
cancel can therefore transfer rows verbatim. Frozen day/round means deferred.
Lifecycle writers still own non-body side effects and final battle deletion;
future binding prepares those effects in the same isolated candidate before
publishing the whole transaction, never by mutating live state first.

## Body schema and passive serialization

Storage is the existing unit entry `body_groups` outside battle and existing
`battle.groups[unit]` inside it. No `body_store`, mirror, cache authority or shadow
runtime. Opt-in metadata is `military_migration.body_version = 1` only when all
eligible land units have validated initialized bodies; battle `body_version = 1`
marks a converted battle. Uninitialized legacy sources keep that marker absent.
`group_size_version/group_size_men` retain their existing meaning. Per-unit
`group_next_slot` is a nonnegative monotonic counter greater than all allocated
slots (retired IDs never reused). `slot` is identity, `home_slot` is 0..9 layout.

Current rows require integer `slot,count,x_m,y_m,home_slot,facing_deg`,
`role` in `front|reserve`; count is positive and at most configured group size;
facing is 0..359. Unique slots and unique homes, at most ten rows, canonical
saved-order count partition and exact sum fit are mandatory. Zero fit has zero
rows. Full counts 1000/901/900/1/0 yield 10/10/9/1/0 with current group size 100.
Survivor rows keep points/IDs/home; casualty reconciliation retires only tail
identities and never shrinks footprint. Initial creation and growth that needs
new points belong to explicit placement, not migration. Configuration comes from
CF01 measured footprint rows and existing balance keys, not script constants.

`path_m`, when present, is an array of integer pairs, preserved including order
and endpoints; absent remains absent. Foundation validates shape only, not a
claim that legacy paths passed future swept motion. All saved motion cursor,
transaction IDs and frozen payload extension fields remain exact. CF03 must
specify and validate its cursor/replay schema before writing it; foundation must
not invent a cursor, consume a path or replay a frozen action. Known old group
size conversion uses the existing pure candidate regrouping rules at a safe
boundary, retaining each survivor's original point/path/ID. It cannot create
missing rows or move to homes; any conversion requiring new points becomes an
explicit placement request, preserving the original rows as constraints.

GameState passive serialization may round-trip explicitly present valid body
metadata and rows without generating them. `to_dict/from_dict` keep SAVE_VERSION
7 and MIN_SAVE_VERSION 6 and existing production load/organization behavior;
no new call to UnitBodies from ordinary save/load/new_campaign. Do not globally
reject the unchanged old production runtime for lacking the opt-in schema.
Candidate validation, not passive serialization, decides physical readiness.
Unknown future body versions are candidate errors. Missing marker is legacy only
when the supported save/group-size provenance permits it; a present malformed
marker is not legacy. Do not add body-version defaults on reads or save.

## Legacy missing versus malformed

Classification uses supported save version, body marker and existing group-size
metadata together, never just `get(field, default)`:

- Supported unmarked legacy land unit outside battle with no `body_groups`:
  legal missing placement. Preserve its saved anchor, personnel, counter, orders
  and costs; emit a request. Fresh current campaign is this case too.
- Unmarked legacy battle with valid old rows: retain exact positions and paths;
  infer missing stable slots only where existing legacy group migration allowed
  array-order allocation, with counter raised beyond all allocated IDs. Missing
  home uses saved row order, missing facing uses valid saved unit/battle facing,
  or the documented legacy zero convention. These add metadata, never points.
- A supported legacy battle whose old schema allowed no groups at all: legal
  missing placement for each member, with its exact battle/side and anchor.
  If a groups entry exists but omits required old `count,x_m,y_m,role`, has a
  wrong type or contradictory counts, it is malformed, not missing placement.
- Version-1 marked unit/battle missing rows for positive fit, required current
  fields, required counter, or containing empty/partial rows: error. Present
  empty legacy arrays for positive fit also error unless the known legacy
  schema explicitly represented uninitialized groups by an empty array; test
  that provenance case separately rather than accepting arbitrary emptiness.
- Duplicate ownership/slots/homes, overflow beyond ten, bad size/version,
  fractional coordinates/path points, invalid facing/role/count, invalid path
  shape or existing overlap: error. Fleets are excluded, not silently converted.
- Frozen day or round: first validate supported versions and frozen/present row
  structure. Corrupt/future data errors; otherwise defer the entire migration
  without changing rows, cursor, costs or RNG until the existing safe boundary.
  Legacy frozen partial counts use their saved group size and frozen personnel,
  not post-round fit. No eager regrouping or replay is permitted.

A future activation must accept all legal legacy cases above using explicit
placement on a load candidate, retain legal existing poses, then validate the
whole world before publication. Lack of immediate room waits with a reason and
retryable candidate; it is not permission to permanently reject a legal old
save, discard units, enlarge fixtures or teleport existing bodies. Activation
cannot land until supported legacy fixtures and actual fresh campaign roundtrip
succeed. Malformed/overlapping/future saves fail closed with original file and
current running state unchanged, without raising MIN_SAVE_VERSION.

## Explicit future placement request boundary

Each migration request is exactly `{unit: String, battle_id: int,
reason: String, anchor_m: Array[int], facing_deg: int,
missing_home_slots: Array[int]}`. Sort by unit then battle ID; anchor has two
whole metre values from the existing saved anchor, facing uses the legacy rule
above, missing homes are sorted 0..9. Reason is `legacy_missing_pose` or
`legacy_regroup_requires_pose`. Existing rows remain in the candidate and
constrain placement. The request is data, never an inferred second position set.

CF04b must implement an explicitly named candidate placement transaction using
this request and the CF03 planner. Its exact function signature, atomic
anchor/rows/personnel/budget boundary and typed outcome must be separately
contracted before that step's registration; they are not a foundation API.
The foundation has no placement writer or placement stub. A request grants no
permission to call old refresh, pick homes in world coordinates or publish a
partial world. Candidate march/battle/render/damage callers accept only
`complete` initialized candidates, never `needs_placement` or `deferred`.

## Executable foundation test matrix

All new tests live in `tests/engine/test_unit_bodies.gd`, with local small fixtures
using `SuiteData.repo/campaign`; no shared fixture edits. Each test asserts source
`to_dict()` and RNG unchanged as well as its specific result. Red tests precede
implementation. These names and assertions define the successor's acceptance:

1. `test_queries_are_detached_and_never_materialize`: missing land/fleet/unknown,
   valid battle/nonbattle, ambiguous store; mutate returned nested paths, prove
   source unchanged; ten local homes and fixed measured extent at all strengths.
2. `test_counts_survivors_and_retired_slots`: hand-computed counts above,
   901→900 keeps first nine points/IDs, tail retired, regrowth cannot reuse its
   ID; no migration-created row or world point; zero fit remains ten home query.
3. `test_candidate_migration_isolated_and_idempotent`: valid marked and legacy
   rows, integral JSON numbers, exact path/facing/extension preservation;
   mutate both source/result independently; JSON migrate twice is equal.
4. `test_legacy_missing_pose_requests`: fresh current campaign plus supported
   v6/v7 nonbattle and groupless legacy battle; request shape/order exact,
   existing rows preserved, no body_version completion marker or invented pose.
5. `test_malformed_is_not_legacy`: each required field missing/type invalid,
   partial/empty current rows, illegal legacy empty provenance, bad counters,
   duplicates, >10, totals, fractional/nonfinite/bool/string values, malformed
   paths, future versions, duplicate stores and measured overlap all error.
6. `test_candidate_transfer_lifecycle`: enter→merge→exit/end/cancel, single-member
   exit, null-repo equivalent transfer, only one owner, exact IDs/paths/counter,
   membership and personnel conservation, retained unrelated records, identical
   replay inert; destination ID/member/side/schema/collision conflicts roll back.
7. `test_frozen_candidate_defers_without_replay`: pending day/round with legacy
   partial rows and costs stays exact; corrupt frozen rows/future version error;
   safe-boundary retry converts once without new RNG/cost/personnel action.
8. `test_passive_serialization_and_production_route_unchanged`: actual baseline
   fresh campaign to_dict/from_dict succeeds with absent bodies remaining absent;
   existing valid metadata roundtrips; constants stay 7/6. Source-call assertions
   prove no UnitBodies call in ordinary march/spawn/battle/damage/render/load,
   no feature flag, no automatic refresh and no production lifecycle edits.

Run targeted new tests then affected selector on frozen final inputs, preserving
all runner gates. Existing `test_battle_groups.gd`,
`test_group_size_migration.gd`, `test_living_cap_battle_migration.gd` and
`test_battle_save.gd` remain regressions, not rewritten acceptance fixtures.
The final production activation additionally tests the original file hash and
live Game.load_campaign rollback; foundation only tests pure source isolation
and passive serialization, and must not claim production publication validated.

## Exact successor scope and stop conditions

A newly registered passive-foundation step may own only:

- `scripts/engine/unit_bodies.gd` and `.gd.uid`
- `scripts/engine/game_state.gd`, `scripts/engine/data_repository.gd`
- `scripts/engine/guide/cluster_formations.md`,
  `scripts/engine/guide/battle_groups.md`, `scripts/engine/CLAUDE.md`
- `data/army/unit_footprints.csv`, `data/tables.csv`
- `tests/engine/test_unit_bodies.gd` and `.gd.uid`, `tests/categories.json`

The dispatcher must register a fresh ID/pair/worktree on current main after this
contract is accepted, with accepted CF01/CF08/rollout/contract dependencies and
no overlapping guide/loader claims. This list grants no claim itself. Extract
only necessary logic against current main, never apply old WIP patches wholesale.
Do not edit the denied twelve tests, original fixtures, production BattleSystem,
BattleGroups, Game, lifecycle or movement writers. Stop and return a bounded
scope proposal if the matrix needs another owned path or if passive copying
cannot retain the existing save contract; do not silently enlarge the step.

The candidate itself is not a live publication API. Later binding publishes one
fully validated whole candidate at the existing transaction boundary after all
side effects are prepared, with file/map rollback on load failure. No partial
regiments/battles assignment, automatic read materialization, global flag,
permanent fallback or persistent shadow runtime is allowed. Final activation
must remain wiring-only; otherwise stop and split the unmet algorithm first.

Complete P4/spec §§2–9 acceptance remains: ten figures, fixed footprint,
full relative swept movement/rotation/yield, real spawn/contact/direct fire,
terms/communications/cost/personnel conservation, eight clusters and automatic
behavior, one body authority, save/replay determinism, real-window visual-review
and performance. CF01's 17-sample and artillery infantry-substitute limitations
remain disclosed. CF03–06 candidates and final activation repeat the production
checks assigned by #187; no foundation PASS substitutes for them.

This document PR stops at its unique Review's independent review and all required
current-HEAD documentation CI, then merge. It creates no product successor.
No Godot, visual or performance result is claimed by this document.
