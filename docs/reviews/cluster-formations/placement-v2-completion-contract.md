# V2 completed MARCH placement proof contract

2026-11-01 · `PLACEMENT-V2-COMPLETION-CONTRACT`. Documentation only.
Implementation `01a19741-a829-7201-a38c-ef8237aa0d11`; dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`. Unique document Review is assigned
by the dispatcher before handoff. This document defines an external saved
interface prerequisite; the original B-PV2 pair owns its product design,
implementation, tests and review. It is not another participant in that PR.

## Authority and reproduced failure

Baseline: accepted main `7c39fc1be6dbb8783699c48e0ece8f5d4027f953`,
including #206 (v2 MARCH), #203 (locomotion), #199 (placement) and #209
([CF05 contract](cf05-battle-contract.md), B-PV2 and its acceptance).
Retain [placement](cf04b-placement-contract.md),
[locomotion](cf04c-locomotion-contract.md),
[MARCH](cf04a-march-contract.md) and
[engine boundary](candidate-engine-dag-boundary.md) contracts.

Necessary evidence only: original `cluster-b-pv2/game_design` worktree's
`.superpowers/b-pv2-setup-checkpoint.json` and `.superpowers/b-pv2-red.log`.
The named `test_v2_completed_metadata_preserves_receipts` failed with
`Invalid raw placement boundary`; 20 existing tests passed, 1 new test failed,
1615 assertions, exit 1. Its source-valid and placement-sequence-only
stale-basis assertions passed. Log SHA256:
`2bf953d238f62ee366428b63706cda483ecddc792bfc8ec60f0ca7aa39a3285d`;
reported test input SHA256:
`e98bde1b2097e33755f0f963f3502b57660b101fc8f555d50bd629caedbb9086`.
These are inherited RED facts, not a passing result or copied unmerged tests.

Actual accepted source explains both failures:

- `UnitBodies._placement_boundary_error` accepts only placement boundary v1;
  `validate_placement_candidate` hardcodes march protocol 1.
- `ArmySystem._body_source_error(...,2)` checks the original whole-save
  `last.result` after every committed slice. `_body_basis(...,true)` omits
  **only** `day_resolution.body_march.last.result`; it includes camp/law/seat
  metadata and `military_migration.body_placement`.
- `ArmyGround._placement_stage` may change camp metadata and unit laws;
  commit then publishes its own four-field receipt. Either change invalidates
  the old MARCH result. That control and the closed placement plan do not hold
  the overwritten source preimage.
- `BodyMotion._loco_saved_source_ok` proves saved plan/policy/endpoints/geometry;
  it does not replace the outer full-save check. Neither inner nor outer
  result may be regenerated to bless placement changes.

## Unchanged authority and scope

This proof admits only `settle`, `leave`, `take_seat`, `refill`, `reconcile`
at an already complete explicit v2 MARCH. No missing-row initialization,
legacy migration, recruitment, spawning, transfer, movement or personnel
operation is admitted here. Travel still returns `requires_motion`; incomplete
valid MARCH defers. Malformed input errors before that deferral.

The entire `day_resolution` and the entire `body_motion` control, including
original plans, cursor, priority, receipts and `last.result`, remain byte-for-byte
canonical equal to the original completion. Bodies, paths, facing, slot/highwater,
anchors, rosters/cohorts, supply, gait/run-up, paid costs, tasks, journal, RNG and
calendar remain unchanged. Existing camp/seat/law semantics at the actual
position remain authoritative; no extra LawEffects, order cost or day meal runs.
V1 placement controls, safe boundaries, frozen-day refusal and latest-plan-only
retry retain their accepted behavior. Unknown versions never fall back to v1.

This adds an explicitly versioned **placement** proof inside the existing whole
JSON save. It changes neither `GameState.SAVE_VERSION`, day-resolution version,
nor MARCH/BodyMotion v2 payloads. There is no production activation, flag,
sidecar save, database, policy installation or waiver.

## Closed raw interface

`H(x)` means exactly `BodyMotion._hash(x)`: recursively sort dictionary keys,
preserve array order, convert only finite integral JSON numbers to integers,
then compact `JSON.stringify` with its default key sorting and SHA256 UTF-8.
Validation precedes arithmetic and hashing. Hashes are 64 lowercase hex digits.
`C(x)` denotes those canonical JSON bytes; canonical equality compares C bytes,
not a partial projection or merely declared effect hashes.

The existing request and plan remain closed placement v1 shapes. A v2 completion
boundary is exactly `{version:2,kind:"march_complete",abs_day:String,receipt:String}`.
Here `version` is an exact JSON integer, day is a canonical nonnegative decimal
string in supported int64 range, and receipt is the **original outer MARCH plan
receipt**. Boundary version selects MARCH protocol, not placement plan version.
Safe/v1 callers keep their old shapes. No `result`, proof, source or context key
is allowed in the external boundary.

The new saved control is exactly:

```
{version:"2", sequence:String, operation_id:String, receipt:String,
 completion_json:String}
```

Its first four values mean the same latest-placement cursor/id/plan hash as v1;
sequence is canonical nonnegative int64 decimal, operation_id has `placement:`
and a nonempty suffix. The string is exactly `C(proof)` where proof is:

```
{version:1, origin:Dictionary, plans:Array[Dictionary]}
```

`origin` is the **entire** original completed state's `to_dict()`, before the
first placement in this completion chain. It includes the original full frozen
transaction, all unmodified controls and the preceding v1 placement control if
present. It must contain no v2 placement proof, even nested as a second origin.
`plans` is a nonempty ordered list of the exact closed existing placement plans
accepted at this completion, each including original request, boundary, basis,
placements and effects. Each has integer version 1 and `placements=[]`.
There is no arbitrary patch, caller-supplied inverse, endpoint digest, proof
receipt or separately editable context authority.

The string envelope is deliberate. `GameState.from_dict` currently recursively
rounds `military_migration` numbers with `_whole`, or decodes legacy value
strings in the imported provenance branch. A string starting with `{` survives
both codecs unchanged, so malformed proof numbers are still visible to the
proof validator. `to_dict` copies it without another value codec. No GameState
loader change is required for this format; a dictionary in `completion_json`
is an error, never converted to a string. A numeric v2 control discriminator
cannot round into string `"2"`; all five control fields are strings.

Parse with an error-reporting JSON parser; require a dictionary and exact closed
keys, then require input string equal to C(parsed proof). This rejects duplicate
keys, noncanonical spelling, whitespace variants, numeric exponents and rounded
out-of-range numeric text. Reject nonfinite, fractional, unsafe (>2^53−1 in
magnitude) plain numeric leaves; encoded GameState int/float strings keep their
existing exact codec semantics only at their own schema positions. Embedded
control versions/cursors are strings; embedded plan numbers are exact integers,
not numeric strings or encoded `i…`/`f…` substitutes. Do not decode the proof
string recursively with a legacy value decoder.

`origin` must be a complete current-version save image, not a sparse legacy save.
Validate its raw shape, required controls, numeric types and complete bodies
before any normalizing loader can hide corrupt input. Rehydrate privately using
`GameState.from_dict(origin,false)` only after that check, then require
C(rehydrated.to_dict()) == C(origin). Unknown/dropped keys, added defaults,
clamped fields, fractional controls and non-roundtrippable encodings reject;
loading is not evidence that a root is valid. Existing unrelated encoded float
state stays bit-exact. No migration or repair is allowed at this seam.

## Admission, deterministic replay and publication order

A complete proof is a reproducible derivation, not permission to omit metadata
from any hash. Let S0 be the rehydrated origin, Pi the i-th stored plan, Si the
full state after publication of that prefix, and B its common v2 boundary.

1. For a first call with no v2 proof, validate the **actual source** using
   `ArmySystem._body_source_error(repo,source,2)` and full original result.
   Require exact day, closed candidate MARCH shape, positive count,
   `next_substep==substep_count`, original outer receipt B.receipt, matching
   current v2 inner receipt, policy/certificate, terrain, geometry, bodies and
   raw personnel provenance. V1 is not silently promoted. Capture all of
   source.to_dict() as origin only after these checks.
2. For a saved proof, validate S0 through that same original strict entrance.
   Require B and every plan boundary to match S0, including protocol/day/receipt.
   Validate original starts as well as current endpoints. A fabricated
   `last.result` in the current descendant cannot replace the one in S0.
3. Starting at S0, for each Pi independently recompute the existing placement
   basis on **the entire preceding Si−1**, including any earlier proof prefix,
   using `_placement_basis` and the current repository/terrain. Independently
   run the existing legal camp metadata rules at the actual position and
   derive the exact closed plan. Compare C(recomputed plan)==C(Pi).
   Never apply its declared effects as an unrestricted patch.
4. Require no body allocations or movement; only the deterministic camp field,
   seat and `LawSystem.on_settle/on_leave` unit-law effects may differ.
   Existing law authority (`LawSystem._take_camp`) is reused. Check all immutable
   invariants above explicitly, and all body/terrain/personnel validity after
   effects. A late failure publishes no receipt, cost or partial candidate.
5. Compute ri=H(Pi) **before** inserting the current receipt/proof. Publish on
   the private Si the v2 control containing request i's sequence/id, ri, and
   C({version:1,origin:S0.to_dict(),plans:[P1,…,Pi]}). Each prior Si−1 has the
   shorter prefix; Pi contains no current control and no hash of Si itself.
6. After replay, require C(Sn.to_dict())==C(actual source.to_dict()). This
   compares the whole current save, including all controls and the exact proof
   string. Check unchanged context through original MARCH and every placement
   basis, not a context supplied in the proof. Only then is source admitted.

For a new operation, admission first validates the entire current prefix;
planning then uses that full current source, and commit recomputes against the
same source before appending. Final validation must replay the new prefix and
compare the full candidate, never pass that descendant directly to the old
full-result predicate and then ignore its failure.

The dependency graph is finite: S0 → P1 → r1 → S1 → P2 → r2 → S2.
The proof contains one root and a linear plan list, not recursively nested
prior full snapshots. Prefix materialization is temporary. No hash contains
its own receipt/current proof; no result rehash, fixed point, hash exclusion,
ignored changed field or recomputed old result is permitted. No compaction or
history truncation is defined; sequence overflow rejects. Storage grows with
operations until a legitimate lifecycle consumer consumes the completion.

As with existing offline receipts, these unkeyed hashes provide consistency
against a retained basis, not signed authorship against an attacker rewriting
an entire save and all its authorities. Adding authentication is outside scope.

## Calls, retries, restores and transitions

- **First plan:** existing `ArmyGround.plan_body_placement_candidate` returns
  the existing detached closed plan; it neither publishes a control nor charges.
  A no-effect operation still appends one receipt exactly once at commit.
- **First commit:** existing `commit_body_placement_candidate` validates the
  actual strict S0, recomputes the whole plan, and returns detached S1 with the
  new proof. Original source and caller plan are unaliased and unchanged.
- **Latest exact retry:** supply the original full plan and boundary. Validate
  all saved proof first, require exact latest sequence/id/receipt **and plan**,
  then return a detached unchanged endpoint. Never reapply laws, pay or append.
  Convenience retries retain `retry_requires_original_plan`. Earlier plans,
  repeated ids, skipped cursors and changed latest plans reject; max sequence
  allows its exact retry, but no successor.
- **Multiple operations:** require sequence previous+1, new id, same completed
  day/receipt and a basis over the complete preceding prefix. Retain S0 and
  append one plan. An operation needing motion defers with no appended proof.
- **Whole JSON/load:** the exact same proof must be admitted after
  `JSON.parse_string(JSON.stringify(state.to_dict()))` followed by
  `GameState.from_dict(...,false)`, in both ordinary and imported provenance
  branches. The raw string's equality prevents laundering fractions or numeric
  strings. Direct and restored calls return canonically identical saves/RNG.
- **MARCH retry/successor:** original `ArmySystem`/`BodyMotion` entrances stay
  strict. A placement descendant is not their original full-save endpoint;
  they must continue rejecting it. Exact placement retry uses the completion
  entrance, never a relaxed march entrance. The exhausted day's next march
  slice cannot exist; count/substep mutation or an incomplete-day proof rejects.
  No wrapper silently redirects either consumer.
- **Resume/begin while frozen:** current `TickEngine` consumers do not own the
  completion protocol. They may refuse the descendant; ordinary resolve still
  refuses candidate days. Proof acceptance does not clear `day_resolution`,
  advance a day, eat a meal or settle another phase. Repeated placement is the
  only additional transition delivered by B-PV2.
- **Genuine day closure / later day:** a future explicit owning lifecycle
  transaction must first admit this exact endpoint, then atomically execute
  its actual remaining phases/closure and consume the proof, retaining only
  the four-field v1 latest placement cursor/id/receipt for global sequencing.
  No intermediate downgraded control with the old frozen day is publishable.
  It must prove its own entire successor state, costs and once-only phases;
  this contract does not supply or implement that driver. Only an actually
  closed new source can enter a new-day begin; it must not inherit the old
  proof as a fresh completion. Resetting day/cursor or deleting proof by hand
  is not closure. Prior-day proof, receipt or plan cannot admit a new day's
  completion; its new first placement captures that day's genuinely valid S0.

## Hand-worked publication and tamper examples

Take an actual legal complete source S0 at day D, previous placement sequence
`"6"`. Regiment U has an actual position at held town T; camp_town=T,
town_seat[T]=U, and a delivered unit law already equals the town's decree.
Let B name S0's exact v2 receipt. `leave`, sequence `"7"`, id `placement:leave-7`
clears camp_town and seat, preserves the already identical unit law. Its plan
has no placements and effects derived from those exact metadata changes.
All rows, metres, supply, money, people, RNG and full frozen payload are equal
before/after. Hand accounting: 0 translated metres, 0 new bodies, 0 extra run
charges, 0 extra meals, 1 placement receipt. Repeating the same original plan
keeps sequence 7, list length 1 and every value identical. A legitimate `settle`
with sequence 8 returns camp_town=T and its eligible seat, but length becomes 2;
its basis includes the sequence-7 receipt and first proof, even if ordinary
metadata is restored to S0's values. Therefore its basis cannot be S0's basis.

Canonical byte arithmetic, independently checkable without Godot: the tiny
JSON value `{"b":2,"a":1}` canonically has bytes `{"a":1,"b":2}` (13 bytes).
Its SHA256 is
`43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777`.
Parsing numeric 1 and 2 as integral JSON floats gives those same canonical bytes;
`{"a":1.5,"b":2}` must fail integer admission, never hash as that value.
This is a serialization example, not a substitute game-state fixture/hash.

For the actual example, write b1=H(full placement basis of S0),
r1=H(P1), q1=C({version:1,origin:S0.to_dict(),plans:[P1]}).
The endpoint's control is precisely `("2","7","placement:leave-7",r1,q1)`.
Compute b1, then P1, then r1, then q1/control; no endpoint digest is needed.
After whole JSON restore q1 is the same string, so replay reproduces that
same five-field control and full endpoint. P2 uses the full endpoint containing
q1, while q2 contains [P1,P2]; it never embeds q2 in P2's own basis.

Concrete tampering outcomes (none publish a candidate):

- Change only endpoint sequence 7→8: replay still derives 7; full equality fails.
- Change endpoint supply by −1, a body facing by +1, RNG, law decree, journal or
  any unrelated treasury value: no permitted replay writes it; equality fails.
- Change origin supply but retain original last.result: strict S0 result fails.
- Change Pi's effects and recompute ri: independent legal replay disagrees.
- Remove P1 but retain P2: its source basis/sequence no longer matches S0.
- Insert `7.5` or `"7"` into a plan's numeric field: raw schema fails before
  normalization; outer JSON roundtrip retains it inside q1 verbatim.
- Add a proof key, duplicate key, unknown version or noncanonical decimal;
  remove origin, result, inner plan, final receipt or required root field:
  strict schema/preimage admission fails. A safe/v1 boundary is not a fallback.
- Publish receipt first and use that changed source to recompute the old result:
  forbidden order, not an admissible proof. A correct chain leaves S0's result
  exactly unchanged, even though it deliberately differs from a direct hash of S1.

## Feasible product seam and remaining ownership

No implementation bodies are prescribed here. The minimal product interface
remains the existing three ArmyGround candidate APIs plus
`UnitBodies.validate_placement_candidate`; completion verification may be private
helpers shared by those entrances. Required responsibilities within B-PV2:

- `scripts/engine/unit_bodies.gd`: exact raw boundary/control/proof admission,
  complete source validation and detached completion validation.
- `scripts/engine/army_ground.gd`: legal metadata recomputation, original basis,
  acyclic prefix receipt publication and latest retry; use its existing terrain
  and law predicates. Never recursively call public proof admission for each
  prefix: root admission then private metadata replay terminates by list length.
- `tests/engine/test_body_placement.gd`, `tests/engine/test_unit_bodies.gd`:
  direct/native and whole-JSON tests using SuiteData and explicit legal policy
  fixtures, never production certificates; retain the original RED regression.
- `scripts/engine/guide/body_placement.md`: document the completed proof seam,
  strict consumers and the remaining day-closure boundary.

These are the original owner's currently recorded paths (ArmyGround is its
necessary caller amendment). The string format needs no GameState, ArmySystem,
BodyMotion, TickEngine, new script, categories, CSV, renderer or art change.
Those consumers' unchanged strict rejection is intentional and must be tested,
not called successful march resume. New raw loader or consumer integration
needs new registered ownership **before editing**. No separate product
prerequisite is required to deliver completion placement itself.

Future atomic closure/consumer integration is a separate dependent lifecycle
step, outside B-PV2; it may overlap UnitBodies/ArmyGround and therefore must run
serially after that PR's accepted merge. If the existing B-PV2 acceptance is
interpreted to require march-API retry/resume on the modified endpoint, that
conflicts with frozen full-result authority: stop and report the conflict to
its dispatcher, do not silently alter acceptance/dependencies or broaden files.
This document neither changes those active records nor dispatches a successor.

## Named future tests and acceptance retained

Keep `test_v2_completed_metadata_preserves_receipts` as the original failing
regression, then add these exact focused names in the owned existing suites:

- `test_v2_completion_proof_first_commit_and_full_endpoint`
- `test_v2_completion_proof_latest_retry_direct_and_whole_json`
- `test_v2_completion_proof_multiple_metadata_operations_and_law_once`
- `test_v2_completion_proof_canonical_string_both_provenance_branches`
- `test_v2_completion_proof_rejects_fractional_missing_unknown_corrupt_raw`
- `test_v2_completion_proof_rejects_rehashed_effects_and_changed_basis`
- `test_v2_completion_proof_rejects_tampered_origin_and_prefix`
- `test_v2_completion_proof_sequence_overflow_and_old_retry`
- `test_v2_completion_proof_strict_march_consumers_and_new_day_refusal`
- `test_v2_completion_proof_v1_and_safe_controls_unchanged`

Exercise every metadata operation, law-before-leave, no-op effects, travel
refusal, incomplete/mixed/unsupported controls, absent rows, all forbidden
state/context changes, exact boundary/hash/day/cursor checks and late failure
atomicity. Future closure tests belong to its owning lifecycle step; a manually
cleared day is a negative fixture, not a passing closure test. Tests compare
entire source/endpoint saves and RNG, original frozen controls and once costs;
no weakened fixture/assertion or discarded RED. Relevant tests run on frozen
final inputs with the shared Godot lock and all current-HEAD required CI.

This document is checked with pure harness/selector/config/guide/link/source
hash checks and hand-worked example checks only; no Godot or visual claim.
Its independent Review and required current-HEAD CI precede accepted merge.
All twelve formation gates, CF05/CF06 scope, historical **55 failures and 6
risky/pending**, cost/save/determinism, real-road defeat, full arm/contact art,
native real-window visual/performance acceptance and final **ALL-writer atomic
activation** remain due. No previously failed/pending gate becomes green here.
