# CF02F foundation amendment — approval draft

Step `CF02F-amendment-proposal`. This is a substantive proposed replacement of
specific #188 input/schema clauses, not an editorial clarification and not
permission to change the current contract or its immutable registered acceptance.
Keep this PR DRAFT after independent review and current-HEAD documentation CI;
merge and product dispatch remain on explicit human approval hold.

## Evidence and bounded decision

Sources are the accepted [#188 contract](cf02-foundation-contract.md),
[#187 staged rollout](cf02-rollout-boundary.md), and the original owners' reports:

- Foundation: `/Users/samuelzhang/.codex/worktrees/cluster-cf02f-foundation/game_design/.superpowers/cluster-cf02f-foundation/boundary-report.md`.
- Retry contract: `/Users/samuelzhang/.codex/worktrees/cluster-cf02f-retry-contract/game_design/.superpowers/cluster-cf02f-retry-contract/boundary-report.md`.

No foundation product diff was reviewed. Its reported final frozen run is FAILED:
7/8 tests, 1157 assertions, exit 1, input SHA256
`8391ac87056c9bb59be53d0f70c5eaee0505a5782190c14c1725ec8e62e3e381`.
Direct and JSON retries fail while the JSON input equality assertion passes.
That evidence remains failed; this document does not repair or accept the WIP.

The counterexample is nine legal rows totaling 900 at fit 901, slots/homes 0..8,
next slot 20, save provenance 7, no completion marker. The old contract requires
both an unchanged `needs_placement` retry and rejection as contradictory legacy.
A deterministic function cannot distinguish byte-identical inputs. Separately,
casualty inputs change personnel while rows still represent the prior fit;
that is outside the old exact-sum input domain.

The minimum proposed resolution is one explicit reconciliation operation plus
one serialized, validated pending-reconciliation descriptor. Normal migration
continues to reject unmarked contradictory totals. The descriptor is a real new
accepted data variant with defined semantics, not evidence of trusted origin,
a completion flag, an identity token, or a reason to skip physical validation.
A caller may construct this variant only subject to all checks below; there is
no cryptographic claim that a save came from a particular function.

## Public operation and input domains

Retain all five #188 APIs and their result envelope unchanged. Add only:

```gdscript
static func reconcile_candidate(repo: DataRepository, source: GameState, unit: String, previous_fit: int) -> Dictionary
```

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
`previous_fit` instead of its staged target fit. It must have the #188 complete
world marker, converted battle marker when applicable, and no pending descriptor
anywhere. Its existing row store, slots, homes, counter, points, paths, facing,
roles and measured geometry must all validate. Both fits are finite nonnegative
integers; bool/string/fractional/nonfinite values are rejected before conversion.
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

An initialized complete unit has homes 0..row_count-1 in saved row order for this
operation. This makes the prescribed tail-only survival and missing-home request
unambiguous. A complete source with another valid home ordering may still be
queried/migrated/transferred under #188, but reconciliation returns a causal
`error` without rearranging it. Later placement must use canonical home order;
if actual required fixtures demand other orderings, stop for a bounded amendment
rather than silently accepting an ambiguous reconciliation rule.

Before changing anything, validate versions and all present row/control structure.
If a pending day/round exists, use its saved frozen personnel/group-size rules,
not the staged target fit, then return `deferred` with null candidate and no
request. No descriptor creation, count edit, cursor advance, replay or eager
regroup occurs while frozen. Corrupt/future data remains `error`, never deferred.
The operation accepts only converted current bodies; frozen legacy conversion
remains the original migration path and matrix 7 unchanged.

The result has exactly #188's `status,reason,error,candidate,placement_requests`
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
Require `0 <= B < T <= 10`; exactly B present rows; homes in order 0..B-1;
row i's count exactly the i-th canonical TARGET count; unique nonnegative stable
slots, valid counter strictly above all present slots, and every other #188
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
v6/v7 legacy cases from #188, including frozen size-50 conversion.

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
#188's exact request fields, saved anchor/facing and unit/battle sort order.
Missing homes are B..T-1. Existing points constrain future placement. That future
separately contracted placement transaction allocates only fresh slots from the
counter, validates the whole world and clears the descriptor only on complete
success. Foundation has no placement writer/stub; no room means later placement
waits, never discards constraints or teleports existing rows.

## Executable amendments to matrices 2, 3 and 5

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
   901→1 and 1→0, same-fit no-op. No pending result is used as a complete input.

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
- Mutate each descriptor key independently: missing/extra key, null, bool,
  string, fractional/nonfinite, version 0/2, negative basis/target, target differs
  from ledger, B>=T, T>10, wrong row count/count partition/home order, bad
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

## Mapping to every #188 section

- **Evidence and limits:** unchanged failed/unknown status, 55 failures/6 risky,
  old CF02 preservation and CF01 limitations. This proposal adds no game PASS.
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
  Add one unit descriptor, canonical home order for reconciliation and new
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

## Approval and legal registration route

Current helper supports cumulative file additions, not immutable acceptance
replacement. Neither this draft nor a green documentation CI changes the active
foundation/retry-contract claims. Do not edit their registry records, replace
owners, resume the blocked product against this proposal, or mark either accepted.

After explicit human approval, the original owners first preserve their WIP,
failed logs, input manifests/hashes and reports; verify actual unmerged status.
Only each original implementation/unique Review may then submit its own
`kind: "step_terminal"`, `terminal_status: "superseded"`, `unmerged: true`,
nonempty reason and `human_authorization.statement/reference`, with the normal
source/status/summary, through the existing helper. Preserve complete previous
step, ownership, failure evidence/history. Terminal steps release active file
claims only; they are never accepted dependencies. No terminal is executed here.

Use separate fresh IDs and fixed new pairs for an approved contract amendment
and, only after its accepted merge, replacement passive implementation. The
contract step owns only `docs/reviews/cluster-formations/cf02-foundation-contract.md`
and incorporates the changes mapped above while retaining all unchanged clauses.
The dispatcher records actual accepted CF01/CF08/rollout/original-contract
prerequisites; never use a superseded step as an accepted dependency. It validates
no ownership overlap, cycles or duplicate launch before starting either step.
The proposal's approval/merge and any approved replacement contract merge must
be explicitly recorded; approval alone is not a merged dependency.

Replacement implementation's exact maximum scope remains:

- `scripts/engine/unit_bodies.gd`, `scripts/engine/unit_bodies.gd.uid`
- `scripts/engine/game_state.gd`, `scripts/engine/data_repository.gd`
- `scripts/engine/guide/cluster_formations.md`, `scripts/engine/guide/battle_groups.md`
- `scripts/engine/CLAUDE.md`, `data/army/unit_footprints.csv`, `data/tables.csv`
- `tests/engine/test_unit_bodies.gd`, `tests/engine/test_unit_bodies.gd.uid`
- `tests/categories.json`

New implementation extracts only necessary preserved logic against current main,
not a wholesale WIP patch. Register exact paths, acceptance, dependencies,
worktree, branch, implementation and unique Review before work. Retain targeted
red/green and four regressions, final-input affected selector, all runner gates
and current-HEAD required CI. No formula/save/determinism acceptance is waived.
If this cannot remain passive or requires another path/input variant, stop and
return a bounded proposal. No product successor is created by this document.

The minimum concrete human approval is:

> I approve the substantive CF02F input/schema amendment described in this
> proposal at its reviewed commit, including explicit reconcile_candidate and
> serialized pending reconciliation, while preserving all stated compatibility,
> isolation, geometry and complete P4 acceptance. I authorize the original owners
> of CF02F-foundation and CF02F-retry-contract to preserve their WIP/failed/input
> evidence, verify they are unmerged, and individually retire those steps as
> superseded/unmerged through step_terminal. I authorize the dispatcher to
> register fresh contract-amendment and replacement-implementation IDs/new fixed
> pairs in the stated scopes, serially after their required accepted merges.
> This does not accept the old failed work or authorize skipping required checks.

The approval must reference the reviewed proposal commit and an actual human
statement; a general “remove blocker” request is not retirement authorization.
Dispatcher owns obtaining/recording that approval and later registration.
Document Review checks sources, consistency, executable distinctions and this
route only; it neither reviews foundation product nor edits or dispatches work.

## Acceptance of this proposal PR

Only the new document changes. Check whitespace, docs-only selector,
Python hook/selector/runner/timeout self-checks, shell/config syntax and guide
caps as specified by the current workflow. Independent unique Review and required
current-HEAD `harness-checks`/`gut-tests` must pass, then keep DRAFT on human hold.
No Godot, physical, visual, performance, product acceptance or merge is claimed.
