# CF02 passive foundation contract

Step `CF02R-contract`, 2026-10-31. Incorporates the human-approved #189
[amendment](cf02-foundation-amendment.md), merged at
`1075e28adfda550881d448ffdd3a1aee08b48703`, into the accepted #188 contract.
The original foundation and retry-contract steps are superseded/unmerged, not
accepted dependencies; their failed WIP and evidence remain preserved.
This replacement changes only the explicitly mapped input/schema clauses.

Original contract basis: `CF02F-contract`, 2026-10-26. This document resolves
the technical entry contract required by PR #187; it implements no runtime behavior. The human
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

The foundation owner additionally reported a FAILED frozen run: 7/8 tests,
1157 assertions, exit 1, input SHA256
`8391ac87056c9bb59be53d0f70c5eaee0505a5782190c14c1725ec8e62e3e381`.
Direct and JSON retries failed while JSON input equality passed. No foundation
product diff is reviewed or accepted by this contract amendment.

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
static func reconcile_candidate(repo: DataRepository, source: GameState, unit: String, previous_fit: Variant) -> Dictionary
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
  requests; empty error. It is compatible legacy or validated pending
  reconciliation input, not a load failure or a publishable physical world.
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
role, facing, personnel, paid cost and frozen cursor, except identities retired
by the explicitly defined safe-boundary legacy regroup below. After that
boundary conversion it validates all present current body envelopes against
measured configuration and each other, including units awaiting placement's
already present neighbors. Existing current-world overlap is an error,
never repaired. It never adds a world position. Repeated migration/JSON replay
is idempotent; source state and RNG remain byte-equivalent on every status.

`transfer_candidate` validates structure and unique ownership only; it requires
an initialized current-schema source with no pending descriptor anywhere,
previously returned `complete` by the
repo-aware `migrate_candidate`, with no intervening pose/configuration changes.
This is a caller precondition, not a stored validation flag or proof that this
repo-free API can infer radii. It returns only
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
cancel can therefore transfer rows verbatim. Ownership-only transfer changes
no point, path or body envelope, so cannot introduce a geometric collision into
that validated world. It cannot diagnose pre-existing geometric collisions:
callers must run repo-aware whole-world validation before live publication,
including after any other staged writer or configuration change. No hidden
global repo or copied radius/configuration is allowed. Frozen day/round means deferred.
Lifecycle writers still own non-body side effects and final battle deletion;
future binding prepares those effects in the same isolated candidate before
publishing the whole transaction, never by mutating live state first.

## Explicit reconciliation operation

This is a passive body-only operation, never bound to production in foundation.
The caller stages a personnel change in an isolated GameState first. `source`
already contains the target fit through the existing personnel ledger; the
function never writes personnel, gold, grain, supply, costs, receipts or orders.
`previous_fit` declares the fit represented by that unit's existing rows before
the staged change. It is not a personnel action or a historical authorization.
The caller remains responsible for its personnel transaction and cost; later
binding prepares and publishes both in one whole candidate.

The input must be an otherwise complete current-body world with exactly one
exception: the named eligible land unit's rows are validated against
`previous_fit` instead of its staged target fit. It must have this contract's complete
world marker, converted battle marker when applicable, and no pending descriptor
anywhere. Its existing row store, slots, homes, counter, points, paths, facing,
roles and measured geometry must all validate. `previous_fit` deliberately accepts
a raw Variant: a typed int parameter may coerce a bool/float before the function
can inspect it. Validate its raw type first; accept only INT or finite FLOAT
with an exact integral value, nonnegative and within the configured ten-group
capacity, then convert to an internal int. Thus 900 and integral JSON 900.0 have
the same semantics; true, null, strings, 900.5, NaN and infinities return the
normal `error` result, never an implicit coercion or argument-type failure.
Apply the same raw-number rule to the staged target fit before normalization.
All other parameters retain their declared types; no wrapper API is added.
Unknown unit, fleet, null/invalid repo, ambiguous owner, legacy unconverted input,
second mismatched unit or arbitrary partial input returns `error` atomically.
The old marker on this specially declared input does not assert that its staged
personnel already agrees with bodies; it is not legal input to normal migration.
To obtain the starting complete world, callers use migration and, later, explicit
placement; reconciliation does not initialize arbitrary legacy rows.

At an unfrozen safe boundary compute the canonical target count partition in
existing saved row order with the configured group size (100 in the examples).
Keep the first `min(old_row_count, target_row_count)` rows. Replace only their
counts by that target partition's corresponding counts; retain every other
field and nested extension exactly. Retire only tail rows; preserve the counter,
which must exceed all pre-operation slots, including retired ones. Never allocate
a slot, row, home, path or world point. If the target needs additional rows,
return `needs_placement` with the existing rows as constraints and the descriptor
below. Otherwise remove the descriptor, return `complete`, and retain completion
markers only if the entire world is complete. Zero fit has no rows and does not
shrink the measured footprint or the ten-home query.

Retained rows keep their existing unique homes, even if these are not a prefix
or not in numeric order. Select missing homes as the lowest unused values in
0..9 until target_row_count is reached, then sort the request. This selects local
layout identifiers only, never world coordinates; no existing home is reassigned.

Before changing anything, validate versions and all present row/control structure.
If a pending day/round exists, use its saved frozen personnel/group-size rules,
not the staged target fit, then return `deferred` with null candidate and no
request. No descriptor creation, count edit, cursor advance, replay or eager
regroup occurs while frozen. Corrupt/future data remains `error`, never deferred.
The operation accepts only converted current bodies; frozen legacy conversion
remains the original migration path and matrix 7 unchanged.

The result has exactly the existing `status,reason,error,candidate,placement_requests`
fields and status invariants. Source, source RNG and every mutable object remain
deep isolated on every status. Replaying reconciliation with the same original
source and arguments yields equal output. Against a resulting candidate use
`migrate_candidate` for direct/JSON idempotent retry; calling reconciliation again
with stale `previous_fit` is an `error`, unless it still exactly describes the
complete rows (a harmless same-fit no-op). No special replay receipt/cache is
introduced. Changing personnel again while pending is rejected until explicit
placement resolves it; no pending-to-pending reconciliation is added.

## Serialized pending variant and validation

The only new saved control field is `body_reconciliation` on the existing unit
entry, for both battle and nonbattle units. It is absent when not pending. It is
not duplicated on a battle or in another store. Its closed shape is:

```json
{"version": 1, "basis_fit": 900, "target_fit": 901}
```

`basis_fit` is the fit validated against the complete input rows by reconciliation;
`target_fit` equals the current personnel ledger fit. Both are nonnegative
integers, `version` is exactly integer 1, no unknown keys, nulls, booleans,
strings, fractional or nonfinite values. The descriptor exists only if the target
requires strictly more rows than the basis. Let `B = ceil(basis_fit / group_size)`
and `T = ceil(target_fit / group_size)`, with zero producing zero rows.
Require `0 <= B < T <= 10`; exactly B present rows; unique homes in 0..9;
row i's count exactly the i-th canonical TARGET count; unique nonnegative stable
slots, valid counter strictly above all present slots, and every other required
current row/path/role/facing/geometry validation. Zero-row basis requires a
present empty body array and explicit valid counter, never a missing store.
The descriptor does not contain poses, duplicate personnel authority, allocated
IDs or an alternative row store. Counter/history conservation is asserted by
the operation; loading cannot infer retired history absent from any save.

Global `military_migration.body_version` must be absent while any unit is pending
or otherwise uninitialized. A converted battle retains `body_version = 1` even
when a member is pending: it now denotes the battle's current row schema, not
that every member is physically complete. This is an explicit change to the
marked-partial rejection: only a validated descriptor permits the partial member.
A global completion marker plus any pending descriptor errors. A pending battle
member without the converted battle marker errors. Legacy size conversion cannot
be disguised by a descriptor: it requires supported current group-size metadata
and current rows. Missing/malformed/future descriptor is never read with defaults.

`migrate_candidate` recognizes this variant before applying ordinary exact-sum
checks. It validates all units and whole-world measured envelopes, returns the
same detached pending candidate and sorted request, and preserves its descriptor
byte-equivalently through direct/JSON retries. It never rewrites `basis_fit` to
match the current rows' sum. Without the descriptor, the identical fit/rows
mismatch is still malformed and errors. A malformed descriptor errors even if
the rows could otherwise be treated as missing legacy placement. Partial current
rows, missing required fields, duplicate owners/homes/slots, overlap, unknown
versions and bad provenance stay errors. Absent descriptors retain all supported
v6/v7 legacy cases in this contract, including frozen size-50 conversion.

Passive `GameState.to_dict/from_dict` preserves an explicitly present descriptor
and nested row extensions losslessly; candidate validation, not deserialization,
checks readiness. It creates no descriptor/default and does not globally reject
the old production runtime. SAVE_VERSION remains 7, MIN_SAVE_VERSION remains 6.
Ordinary load/new campaign/march/battle/damage/render routes gain no UnitBodies
call. A pending variant is never publishable or transferable; queries remain
snapshots, not a readiness guarantee. `transfer_candidate` still requires a
repo-validated complete world with no pending descriptor anywhere.

Existing legacy missing-pose requests retain their reasons/shapes unchanged.
Add exactly `reason: "reconciliation_requires_pose"` for this variant, retaining
this contract's exact request fields, saved anchor/facing and unit/battle sort order.
Missing homes are the lowest T-B unused homes in 0..9, sorted. Existing points
constrain future placement. That future
separately contracted placement transaction allocates only fresh slots from the
counter, validates the whole world and clears the descriptor only on complete
success. Foundation has no placement writer/stub; no room means later placement
waits, never discards constraints or teleports existing rows.

## Body schema and passive serialization

Storage is the existing unit entry `body_groups` outside battle and existing
`battle.groups[unit]` inside it. No `body_store`, mirror, cache authority or shadow
runtime. Opt-in metadata is `military_migration.body_version = 1` only when all
eligible land units have validated initialized bodies; battle `body_version = 1`
marks its converted row schema, including a validated pending member as specified
above. Global completion is absent while any unit is pending or uninitialized.
Uninitialized legacy battles keep their battle marker absent.
`group_size_version/group_size_men` retain their existing meaning. Per-unit
`group_next_slot` is a nonnegative monotonic counter greater than all allocated
slots (retired IDs never reused). `slot` is identity, `home_slot` is 0..9 layout.

Current rows require integer `slot,count,x_m,y_m,home_slot,facing_deg`,
`role` in `front|reserve`; count is positive and at most configured group size;
facing is 0..359. Unique slots and unique homes, at most ten rows, canonical
saved-order count partition and exact sum fit are mandatory for complete rows;
only the explicit reconciliation input and validated pending prefix above are
exceptions. Zero fit has zero
rows. Full counts 1000/901/900/1/0 yield 10/10/9/1/0 with current group size 100.
Survivor rows keep points/IDs/home; explicit `reconcile_candidate` retires only tail
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
metadata, explicitly present reconciliation descriptors and rows without
generating them. `to_dict/from_dict` keep SAVE_VERSION
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
  home is assigned only after safe-boundary regrouping, by resulting row order
  0..9; missing facing uses valid saved unit/battle facing or the documented
  legacy zero convention. Validate legacy input by its known saved size and fit
  first: size 50 legitimately permits 20 rows for 1000 fit. Neither current
  ten-row nor current home_slot constraints apply before conversion. At a safe
  boundary consume rows in slot order using existing migrate_size semantics,
  retain each output group's first surviving row point/path/slot/role, retire
  consumed identities permanently, keep group_next_slot beyond every old slot,
  then map the resulting at-most-ten rows to homes and validate current schema.
  Metadata allocation and regrouping never create a world point.
- A supported legacy battle whose old schema allowed no groups at all: legal
  missing placement for each member, with its exact battle/side and anchor.
  If a groups entry exists but omits required old `count,x_m,y_m,role`, has a
  wrong type or contradictory counts, it is malformed, not missing placement.
- Version-1 marked unit/battle missing rows for positive fit, required current
  fields, required counter, or containing empty/partial rows: error, except the
  strictly validated pending-reconciliation variant specified above. A converted
  battle marker alone never permits a partial member. Present
  empty legacy arrays for positive fit also error unless the known legacy
  schema explicitly represented uninitialized groups by an empty array; test
  that provenance case separately rather than accepting arbitrary emptiness.
- Duplicate ownership/slots, duplicate current homes, current-schema overflow
  beyond ten (legacy count limits follow its saved size), bad size/version,
  fractional coordinates/path points, invalid facing/role/count, invalid path
  shape or existing overlap: error. Fleets are excluded, not silently converted.
- Frozen day or round: first validate supported versions and frozen/present row
  structure. Corrupt/future data errors; otherwise defer the entire migration
  without changing rows, cursor, costs or RNG until the existing safe boundary.
  Legacy frozen partial counts use their saved group size and frozen personnel,
  not post-round fit; 20 valid size-50 rows must defer unchanged, without adding
  home_slot or applying current count/home limits. No eager regrouping or replay
  is permitted. Physical readiness validation of the converted current world
  occurs after the safe-boundary regroup, not as a current-schema prerequisite
  that could reject a legitimate frozen legacy transaction.

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
`legacy_regroup_requires_pose`, or `reconciliation_requires_pose` for the
validated pending variant. Legacy reasons/shapes remain unchanged. Existing rows
remain in the candidate and
constrain placement. The request is data, never an inferred second position set.

CF04b must implement an explicitly named candidate placement transaction using
this request and the CF03 planner. Its exact function signature, atomic
anchor/rows/personnel/budget boundary and typed outcome must be separately
contracted before that step's registration; they are not a foundation API.
The foundation has no placement writer or placement stub. A request grants no
permission to call old refresh, pick homes in world coordinates or publish a
partial world. Placement consumes and clears the pending descriptor only on
complete whole-world success, allocating fresh slots from the preserved counter.
No room means wait without discarding constraints or teleporting. Candidate
march/battle/render/damage callers accept only
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
   duplicates, current-schema >10, invalid legacy saved-size totals,
   fractional/nonfinite/bool/string values, malformed
   paths, future versions, duplicate stores and measured overlap all error.
6. `test_candidate_transfer_lifecycle`: enter→merge→exit/end/cancel, single-member
   exit, repo-free end/cancel on a previously repo-validated source, only one
   owner, exact IDs/paths/counter,
   membership and personnel conservation, retained unrelated records, identical
   replay inert; destination ID/member/side/schema conflicts roll back. Assert
   every world point/envelope is unchanged, hence a valid geometry stays valid.
   A separate repo-aware migration case rejects overlapping geometry before
   transfer; transfer alone must not claim collision validation. Two repos with
   different measured radii demonstrate that its structural outcome is identical
   while repo-aware physical validation can differ; no shadow config is added.
7. `test_frozen_candidate_defers_without_replay`: pending day/round with legacy
   partial rows and costs stays exact; corrupt frozen rows/future version error;
   explicit 1000-fit fixture with slots 0..19 and 20 rows of 50 returns deferred
   byte-exact under both pending-day and pending-round cases, with no homes added.
   After clearing only the frozen boundary, retry yields ten rows of 100 with
   slots 0,2,...,18, each survivor's exact point/path/role, homes 0..9 and
   group_next_slot at least 20 (or its larger saved value); no retired ID reused.
   Use legal measured spacing so physical validation passes. JSON/retry remains
   identical without new RNG/cost/personnel action.
8. `test_passive_serialization_and_production_route_unchanged`: actual baseline
   fresh campaign to_dict/from_dict succeeds with absent bodies remaining absent;
   existing valid metadata roundtrips; constants stay 7/6. Source-call assertions
   prove no UnitBodies call in ordinary march/spawn/battle/damage/render/load,
   no feature flag, no automatic refresh and no production lifecycle edits.

### Required reconciliation extensions to matrices 2, 3 and 5

Use the existing local SuiteData-based test file, production measured spacing,
no shared fixture edits. `J(S)` means
`GameState.from_dict(JSON.parse_string(JSON.stringify(S.to_dict())))` through
the existing supported copier, preserving save provenance. Every case asserts
source `to_dict` and RNG unchanged, detached nested mutations both ways, no
invented point, and the result status/envelope. Names and other assertions stay.

Matrix 2 (`test_counts_survivors_and_retired_slots`):

1. Begin with valid complete fit 901, ten rows [100 x9, 1], slots/homes 0..9,
   next_slot 20, valid markers. Stage ONLY personnel to 900 in a detached copy.
   `reconcile_candidate(repo, staged, unit, 901)` is `complete`: nine rows
   [100 x9], slots/homes 0..8, original points/paths/extensions, counter 20.
   Direct migration and migration of J(result) are complete and equal.
2. Stage ONLY personnel from that complete 900 candidate to 901.
   `reconcile_candidate(repo, staged, unit, 900)` is `needs_placement`: nine
   rows [100 x9], counter 20, descriptor `{version:1,basis_fit:900,target_fit:901}`,
   no global completion marker, missing homes [9], reconciliation request reason.
   Slot 9 is absent; no new slot or point exists. Future placement's first fresh
   slot must be 20, never 9; foundation asserts the request/counter, not a fake
   placement result.
3. `migrate_candidate(repo, partial)` and migration of J(partial) both return
   `needs_placement`, equal candidate and exact request. Repeat twice, including
   JSON between each retry. Pending rows/counter/descriptor stay exact.
4. Repeat operation boundaries for 1000/901/900/1/0 with hand-computed
   10/10/9/1/0 rows. Include growth 1→1000 (one retained row now count 100,
   nine missing homes) and 0→1 (zero existing rows, home [0] missing), casualty
   901→1 and 1→0, same-fit no-op. No pending result is used as a complete input. Include complete rows with
   non-prefix/out-of-order homes: survivor homes stay exact, and missing homes
   follow the lowest-unused rule rather than moving existing homes.

Matrix 3 (`test_candidate_migration_isolated_and_idempotent`):

- Retain marked/legacy/integral-JSON and all isolation/extension tests.
- Add the exact matrix-2 partial and zero-basis pending variants, outside battle
  and as one member of a converted battle. Direct and J retries are equal;
  pending member's converted battle marker remains 1, global marker absent.
  Another valid unit's rows, orders, costs, personnel and RNG remain exact.
- Reconcile original staged input twice to equal results. Migration of outputs
  never executes the personnel change again. Reconcile a pending result, or a
  complete result with stale previous_fit inconsistent with its rows, errors.

Matrix 5 (`test_malformed_is_not_legacy`):

- Remove ONLY the descriptor from the matrix-2 partial (leave all other fields
  equal): both direct and J migration error for contradictory legacy totals.
  Add a global completion marker to that unmarked mismatch: error too.
- On an otherwise valid complete 900-person basis staged to fit 901, pass raw
  Variant arguments 900.5, true, null, "900", NaN and positive/negative infinity
  directly as `previous_fit`: each returns `error`, null candidate and no requests,
  with source/RNG unchanged. Also use a complete one-person basis staged to fit 2
  with raw true, proving bool cannot become an accepted prior fit of 1. Raw 900
  and 900.0 both yield the same valid pending result. Negative and over-capacity
  raw numbers error before conversion; pending/legacy validation is not involved.
- Mutate each descriptor key independently: missing/extra key, null, bool,
  string, fractional/nonfinite, version 0/2, negative basis/target, target differs
  from ledger, B>=T, T>10, wrong row count/count partition/home value, bad
  counter, absent body store, missing converted battle marker, unsupported
  group-size metadata or global completion marker: each direct and J-representable
  malformed case errors. Nonfinite raw values are tested before JSON, since
  standard JSON cannot encode them; their null encoding also errors.
- Valid descriptor plus overlap, duplicate owner/slot/home, invalid point/path,
  unknown body/save version or frozen corruption errors; descriptor is no bypass.
- A complete ordinary world carrying an unnecessary descriptor errors. Personnel
  changed again while pending errors, rather than silently changing the target.
- Retain every original malformed/legacy/future case and matrix 7 frozen cases.
  For a valid frozen reconciliation input, both direct and J return deferred
  with exact source and no candidate/request; clearing only the boundary then
  permits the specified reconciliation. No failing assertion is deleted.

Matrix 6 additionally rejects any pending descriptor. Matrix 8 additionally
proves passive descriptor roundtrip and no descriptor/default creation, retaining
all production source-call assertions and save constants. Matrices 1 and 4, all
original assertions above and all four named regressions remain unchanged.

Run targeted new tests then affected selector on frozen final inputs, preserving
all runner gates. Existing `test_battle_groups.gd`,
`test_group_size_migration.gd`, `test_living_cap_battle_migration.gd` and
`test_battle_save.gd` remain regressions, not rewritten acceptance fixtures.
The final production activation additionally tests the original file hash and
live Game.load_campaign rollback; foundation only tests pure source isolation
and passive serialization, and must not claim production publication validated.

## Amendment traceability and unchanged obligations

The approved #189 sections map to this authoritative contract as follows:
public operation → Explicit reconciliation operation; serialized variant → the
same section and Body schema; executable amendments → required matrix extensions.
The following obligation map is retained in full for item-by-item review.

- **Evidence and limits:** unchanged failed/unknown status, 55 failures/6 risky,
  old CF02 preservation and CF01 limitations. This amendment adds no game PASS.
- **Exact public API / queries:** five APIs retained; add the explicit
  reconciliation signature/input domain. Original migration no longer has an
  implicit casualty/growth responsibility on mismatched unmarked rows.
- **Result envelope / isolation:** unchanged for all four statuses, every nested
  store and RNG. Pending descriptor is included in whole-state deep isolation.
- **Migration validation / idempotence:** retain raw numeric validation, geometry,
  no new point, safe legacy regroup and all-status direct/JSON replay; extend the
  accepted domain only by the strictly validated pending variant.
- **Transfer:** all original endpoint, membership, conservation, replay,
  repo-precondition and freeze requirements retained; pending variant prohibited.
- **Body schema / serialization:** exact-sum remains mandatory for complete rows;
  reconciliation input and serialized pending prefix are explicit exceptions.
  Add one unit descriptor, explicit missing-home selection and new
  request reason. Stable IDs/counter, current counts, footprint and paths stay.
  Global marker completeness retained; converted battle marker meaning narrowed
  to schema, with validated pending-member exception. Save constants stay 7/6.
- **Legacy classification:** retain every supported missing/old-size/frozen case
  and malformed rejection. Only explicitly described pending current variant is
  added; contradictory unmarked legacy is not reclassified as valid progress.
- **Future placement:** same separate CF04b contract, no foundation writer or
  publication. It must additionally consume/clear the descriptor atomically.
- **Matrix 1:** unchanged queries; **2/3/5:** additions/input changes above;
  **4:** unchanged legacy requests; **6:** unchanged transfers plus pending reject;
  **7:** unchanged legacy freeze plus explicit reconciliation defer case;
  **8:** add passive descriptor roundtrip/no-default proof, retain all production
  source-call assertions and constants. All four named regressions unchanged.
- **Exact scope / stop conditions:** same twelve foundation paths, no added
  product path, original denied fixtures and production writers still excluded.
  Existing candidate-only publication boundary, complete P4/spec §§2–9, CF03–06
  staged checks and final production activation remain mandatory.

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
