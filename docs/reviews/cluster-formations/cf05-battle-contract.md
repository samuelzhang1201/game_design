# CF05 candidate battle contract

Date: 2026-11-01. Step `CF05-CONTRACT`; implementation
`01a196e5-91ef-7131-a460-0bedc3229bc1`, dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`. Unique document Review is assigned by
that dispatcher before handoff. This document freezes future interfaces and
independently rejectable product scopes. It implements no game behavior and
starts no product, Review or successor session.

## Authority, sources and concrete gaps

Accepted source is main `67312485daf56b5806035adc0e6f81aae83f32bd`.
Read the [approved spec](../../superpowers/specs/2026-10-25-cluster-formations-design.md)
§2–9 and [original plan](../../superpowers/plans/2026-10-25-cluster-formations.md)
CF05, CF06 and staged acceptance together with this contract. The accepted
[#208 boundary](candidate-engine-dag-boundary.md) permits this contract before
render/art completion; it does not permit implementation before actual engine
prerequisites or activation before all twelve gates. Historical DRAFT headings
in accepted #187 are not a renewed approval request.

Concrete accepted interfaces used here:

- [Foundation](cf02-foundation-contract.md), its
  [amendment](cf02-foundation-amendment.md), `UnitBodies.rows`,
  `migrate_candidate`, `transfer_candidate`, `_frozen`, `_copy` and
  `guide/cluster_formations.md`: one owner, complete current bodies, immutable
  survivor identities, no transfer while a day/round is frozen.
- [#194 MARCH](cf04a-march-contract.md), `ArmySystem._body_stage`,
  `plan_body_march_candidate`, `commit_body_march_candidate`,
  `TickEngine.begin_body_march_candidate`, `DayResolution` and
  `guide/body_marches.md`: idle v4 MARCH, saved routes, exact integer remainder,
  cost staging, minimum route prefix and one simultaneous reservation.
- [#199 placement](cf04b-placement-contract.md), `ArmyGround` candidate APIs,
  `UnitBodies.validate_placement_candidate` and `guide/body_placement.md`:
  completed MARCH permits metadata only, not pose allocation or travel.
- [#202 locomotion](cf04c-locomotion-contract.md), accepted #203
  `BodyMotion.plan_locomotion_candidate` / `commit_locomotion_candidate`:
  stop–pivot–move/hold, Q=1,000,000, measured circles, policies/certificates,
  source/result hashes and explicit integer timeline.
- `BattleGroups.translate/follow_anchor/deploy_day/engaged_counts`,
  `BattleCharge.move/impacting/consume`, `BattleTaskSystem.deploy_flank`,
  `BattleSystem.join/_start/_fight/_exits/_end/call_off/step_battle`,
  `BattleMerge.mergeable/_merge`, `TickEngine._resolve_battles`; guides
  `battle_groups.md`, `battle_charge.md`, `battle_merge.md`,
  `battle_deployment.md` and `battle_ranged.md` under `scripts/engine/guide/`.

These are actual incompatibilities, not completed integration:

1. Frozen main MARCH/placement validate version 1; TIME requires version 2.
   #206 LOCO-MARCH is unaccepted at this source. No open patch was consumed.
   Its actual accepted result must be checked before product registration.
   Explicit v2 placement completion support is a separate prerequisite below;
   do not assume #199 or #203 supplies it.
2. TIME's nonempty boundary is exactly `{version,abs_day,substep}`, for MARCH.
   It cannot validate CONTACT, decision, lifecycle or pending battle rounds.
   Deleting `day_resolution`, relabeling a frozen v1 receipt, or calling a
   weaker structural transfer on an unvalidated world would bypass admission.
3. `_body_stage` combines march intent generation, gait payment, reservation and
   settlement. Existing battle writers independently spend deployment distance;
   `translate` writes the anchor first and `follow_anchor` shifts all paths.
   Sequential march then battle commits would spend two slice allowances and
   certify different relative sweeps. They cannot be composed as-is.
4. `_exits` removes members, `step_battle/call_off` delete fields, and `_merge`
   folds dictionaries then deletes the absorbed field. Candidate rows must
   transfer before any of those deletions. Transfer currently copies a source
   side when moving between battles; a merge needs explicit validated allegiance
   remapping, including reversed sides and bilateral source parties.
5. Actual radii are infantry 927, archers 932, cavalry 804, artillery 875,
   royal 749 metres. Legacy centre-distance contact at
   `battle_group_contact_m=100` is impossible for nonoverlapping such circles.
   Contact must be defined at their surfaces below. This does not increase
   ranged reach, reduce any radius, or certify installed animation.
6. TIME successor admission requires every saved move identity/path endpoint to
   still exist (`_loco_saved_endpoints`). Round losses retire rows, so keeping an
   active movement receipt through casualty reconciliation would block the next
   slice. Explicit end-of-slice receipt closure is a separate prerequisite below;
   deleting it informally or rehashing a shorter move list is forbidden.
7. `_fight` freezes an RNG draw, actions, costs and loss plan before personnel
   commit; ordinary refresh freezes pending rounds. GameState also has a legacy
   numeric/value decoder. A candidate round needs raw-preserving admission and
   immutable physical-contact provenance, not an ordinary round rerun over new
   positions. CF05 must stop at a round-ready boundary until CF06 is accepted.

## Public candidate API and results

All new classes are typed engine-pure `RefCounted`. Ordinary public signatures,
production callers, save versions 7/6 and old v1/v2 protocols remain unchanged.
New entries are explicit; no flag, fallback, renderer callback or second clock.

```gdscript
# TickEngine, using its existing data repository.
func begin_body_battle_candidate(source: GameState) -> Dictionary
func step_body_battle_candidate(source: GameState) -> Dictionary
# BodyBattle: query then independently revalidated detached transaction.
static func plan_candidate(repo: DataRepository, source: GameState,
        request: Dictionary, boundary: Dictionary) -> Dictionary
static func commit_candidate(repo: DataRepository, source: GameState,
        proposed: Dictionary, boundary: Dictionary) -> Dictionary
# Validation only, using the foundation's real physical/count/owner validators.
UnitBodies.validate_battle_candidate(repo: DataRepository, source: GameState,
        boundary: Dictionary) -> Dictionary
DayResolution.body_battle_incompatibility_reason(tx: Dictionary) -> String
# Separate explicit TIME entrances; existing MARCH entrances remain closed.
BodyMotion.plan_battle_locomotion_candidate(repo: DataRepository, source: GameState,
        intents: Array, boundary: Dictionary) -> Dictionary
BodyMotion.commit_battle_locomotion_candidate(repo: DataRepository, source: GameState,
        proposed: Dictionary, boundary: Dictionary) -> Dictionary
# Read-only contact output for CF06; no personnel/RNG/supply mutation.
BodyBattleContact.query_candidate(repo: DataRepository, source: GameState,
        battle_id: int, unit: String, enemies: Array,
        boundary: Dictionary) -> Dictionary
```

Transaction results are exactly
`{status:String,reason:String,error:String,candidate:GameState,plan:Dictionary}`.
Status is `complete`, `deferred`, `blocked` or `error`. Error has nonempty error;
other statuses have empty error. Deferred/error have null candidate and `{}`
plan. Successful planning has null candidate; successful begin has empty plan;
commit/step success carries a detached candidate and accepted plan. A waiting
legal motion is complete with per-body reasons, not a transaction error.
Blocked is a valid detached encounter or round-ready boundary, with no implicit
acknowledgement, damage or continued movement. It is not product acceptance.
Every result leaves source, its nested arrays, RNG and source file unchanged.
UnitBodies retains its existing five-field result, not this transaction shape.
Contact query has its own closed result defined below.

Begin accepts only complete current bodies on an unfrozen source, after raw
validation. It freezes an effective daily budget for every non-naval unit,
including battle-owned and holding peers, in the existing march_budgets table;
received march_entries retain their existing route meaning. No separate tactical
budget ledger is created. It freezes routes with the accepted march setup
calculation on a private clone. It does not run couriers, AI, works, base food,
economy or calendar. It creates a new candidate day, never converts a persisted
MARCH/day/round protocol. Begin on an existing valid frozen transaction defers;
malformed input errors before deferral. A pending legacy round remains on its
original route until its safe boundary; no candidate adopts its outcome.

Step executes exactly one control transition: `move`, contact discovery, current
encounter acknowledgement wait, one battle's round-ready handoff, or next-slice
advance. It never calls ordinary `_resolve_battles`, `_fight`, anchor movers or
refresh as a repair. Once all writers are accepted, deterministic providers
produce one world move. Until then the assembled driver is not registered.
No provider may silently substitute hold for an unimplemented writer.

## Closed raw controls, plan and replay

All new dictionaries below reject unknown/missing keys. Raw numbers must be
finite exact integral JSON numbers (abs <= 2^53-1), excluding bool; coordinates,
local arithmetic and products also satisfy TIME's bounds. Saved control integers
are canonical nonnegative decimal strings, with checked range, no signs/leading
zeroes except `"0"`. IDs with prefixes are literal strings, not legacy encoded
numbers. Lowercase SHA256 uses sorted-key canonical hashing. Integral JSON floats
canonicalize only after validation; fractions, numeric strings and nonfinite
values never become valid through rounding or value decoding.

The v4 day phase/order header and existing frozen march tables/journal persist.
New `day_resolution.body_battle` is exactly:

```text
{version:"1",abs_day:String,sequence:String,next_substep:String,
 substep_count:String,stage:"move"|"contact"|"round"|"advance"|"complete",
 battle_ids:[String],battle_index:String}
```

Day phase is FIXED_TACTICAL_SUBSTEPS. Existing `battle_step`, `battle_ids`,
`battle_index`, `pending_decision`, consumed tokens and journal remain the real
DayResolution fields; the new battle_ids/index must agree with them, not form an
independent queue. IDs are canonical positive decimal strings, sorted once after
contact/merge. `next_substep` agrees with the existing substep index; count agrees
with frozen count, initially stage move and index zero. Sequence is the next
outer operation number, zero if no prior outer receipt, otherwise its sequence+1;
it never resets on a new candidate day. Final stage
complete has index=count, no current decision/round, and retains the day.
Ordinary `incompatibility_reason` rejects this marker before any mutation, just
as it rejects body_march. Both markers together are corruption. No daily phase
or substep order is relabeled. The explicit consumer executes the movement work
of MARCH as a union with tactical movement, then existing logical contact order.

Boundary is exactly
`{version:1,kind:"battle",abs_day:String,substep:String,sequence:String,stage:String}`.
It must equal the saved control and actual day cursor. Only move admits motion;
contact admits discovery/enter/merge; round admits round-ready/acknowledge;
advance admits withdrawal/end/cancel and advancing the cursor. Terminal operations
may also run at an unfrozen safe boundary, exactly
`{version:1,kind:"safe",abs_day:String,sequence:String}`, with no day or pending
round and sequence equal to the next outer operation number.
Raw validation always precedes deciding that a valid operation is deferred.

Exact transitions: move requires battle_step empty/no decision and publishes
contact with the same substep. Contacts closes the timeline, performs lawful
start/join/merge, freezes sorted live canonical IDs, sets battle_step=fighting,
battle_index=0 and stage=round; substep_battle_ids contains only new starts.
At round, an unacknowledged new encounter uses the existing decision token and
blocks; acknowledgement consumes only that token and preserves the queue.
round_ready operates only on battle_ids[battle_index]. CF06 settlement records
that ID once in processed_battle_ids and increments the shared/mirrored index.
Already processed IDs are skipped without another round; index==queue size
sets advance. Advance resolves valid exit/terminal requests, clears both queues,
resets battle_step/index/substep_battle_ids and increments substep once, then
sets move or complete at count. It neither pays base food nor runs tomorrow.
Every other stage/request combination defers unchanged, after raw validation.

Requests are one of these exact tagged shapes (no free-form state patches):

```text
{kind:"move"} | {kind:"contacts"} | {kind:"advance"}
{kind:"enter",unit:String,battle_id:String,side:"att"|"def"}
{kind:"merge",first_id:String,second_id:String}
{kind:"withdraw",unit:String,battle_id:String,reason:String}
{kind:"end"|"cancel",battle_id:String,reason:String}
{kind:"round_ready",battle_id:String}
{kind:"acknowledge",token:String,choice:String}
```

Discovery chooses new field ID/sides using existing stable rules and received
intent, then atomically transfers both founders; enter only joins an existing
canonical field. Client-supplied side never overrides `_side_for`/hostility.
End/cancel/withdraw reasons are nonempty; request is not military authorization.
Step generates these requests; tests may call them explicitly at legal stages.
Only delivered task cancellation changes execution; a queued cancel stays queued.

Plan is exactly:

```text
{version:1,request:Dictionary,boundary:Dictionary,
 basis:{source:String,result:String},motion:Dictionary,contacts:Array}
```

Only move has nonempty motion: the full TIME v2 plan, unchanged move/op schema,
with its cursor.boundary equal to this explicit battle boundary. Other operations
have `{}` motion. Contacts are the canonical pair records below, recomputed for
discovery/merge/round-ready; other operations have `[]`. No second set of saved
body poses, proposed arbitrary GameState or generic patch grammar is added.
Commit replans request from the original source, compares the whole canonical
plan and applies only its independently computed result to a private clone.

New explicit TIME entrances reuse the single timing/reservation core, extend
its boundary validation to this tagged battle protocol and preserve version-2
operation semantics. Old MARCH entrances still reject a battle boundary. Saved
`military_migration.body_motion` retains its exact v2 control/plan shape; only
the new boundary variant is added and validated by the battle entrance. No v1
receipt acquires v2 timing; no duplicate tactical motion receipt is invented.
The foundation admission runs for source, reconstructed starts and final world.

Before contact processing can retire any row, explicitly close the just-finished
movement at Q. New `BodyMotion.close_battle_locomotion_candidate(repo:
DataRepository, source:GameState, boundary:Dictionary) -> Dictionary` returns
exactly `{status,reason,candidate}` (complete/error, null candidate on error).
It admits only contact stage, validates the full active v2 plan, endpoints,
terrain, policies and sweep, then moves its digest/cursor/priority into
body_battle.closed_motion and removes the active body_motion atomically on its
clone. It changes no pose, count, money, RNG or stage. Contact transaction calls
this helper before lifecycle; no closed cursor is manufactured without proof.
Repeated original outer plans use outer replay, not a new closure of absent
geometry. New motion must be strictly later than both active and closed cursors,
uses the closed priority restricted to surviving identities (new identities
then follow stable unit/slot order) if no active plan exists, and cannot reopen
a closed slice. Unrelated v1/v2 APIs do not gain battle-boundary admission. The shared
standalone march source validator also rejects same/older closed movement cursors.
The renderer may consume an active timeline only; closure is an explicit Q
boundary, not an early animation-completion signal. Round-ready/CF06 losses then
operate on stationary authoritative rows without falsifying old motion identity.
Closed descriptors bind final contact/round provenance and remain saved through
JSON; no saved shadow poses, movement replay or additional slice budget exists.

One outer receipt control persists across safe lifecycle and candidate day
operations at `military_migration.body_battle`, exactly
`{version:"1",sequence:String,receipt:String,closed_motion:Dictionary}`.
closed_motion is empty before a timeline is closed, otherwise exactly
`{version:"2",abs_day:String,substep:String,receipt:String,priority:Array}`.
Priority uses TIME's canonical saved `{unit:String,slot:String}` identities.
This is the last completed timeline digest/ordering cursor, not a second plan.
Absence means no prior operation;
present empty/null/future controls error. It stores no poses, costs or plan.
While the current timeline is active, the previous closed cursor may remain, but must be strictly older than it.
A safe-boundary operation uses the same monotonically increasing sequence and
receipt authority; it does not manufacture a day transaction.

Outer source digest binds the complete raw canonical save, request/boundary,
footprints, all relevant balance/policy/certificate/diplomacy/received law and
party records, and actual terrain pixels/bounds. Result digest binds expected
endpoint save and that same context, replacing only
`military_migration.body_battle.receipt` with the empty string to break its
self-reference; it retains version, sequence, stage, queue, people, costs, RNG,
inner motion plan and all other state. It cannot omit all day/round state.
The outer receipt is SHA256 of the whole plan. Every successful transition
records its consumed sequence/receipt in that control and increments the day
next sequence if present, including transitions with no motion. Same latest plan
retry first validates the actual endpoint using its derived current boundary;
the proposed boundary must name the just-consumed sequence, not be relabeled
as current. It validates raw state/context and result digest, then returns
a detached no-op before payment/planning. Changed state, terrain, radius, law, parties,
policy or certificate invalidates even a retry. Older/skipped/conflicting plans
error. Convenience step reads current stage; it never reconstructs a past plan.
There is no durable intermediate state between inner and outer publication.

GameState must preserve both new raw controls and candidate round envelope from
both import provenance branches, before `_whole`/`_decode_values`. Only their
validated integral JSON numbers canonicalize. `"i42"`, `"f3ff0000000000000"`,
fractions and malformed future versions stay malformed. This is a separately
registered loader seam, not a new save version or loader activation. Rejected
candidate admission never overwrites a legitimate old save or live state.

## One budget, one sweep, existing costs

For the candidate union slice, freeze one effective **daily** walk allowance per
unit using the existing terrain/injury/supply/gait formulas; slice shares use
accepted MARCH quotient/remainder. Tactical intents are capped additionally by
the existing daily `battle_deploy_step_m` share, not given that share on top.
For count N and daily D, share i is floor(D/N)+(1 if i<D mod N else 0).
The last slice cannot refund metres/time spent in earlier sidesteps or pivots.
Running payment and step conversion use existing UnitGait exactly once per
unit slice; reserve the existing base meal. No new fatigue or morale speed factor.

Deterministic exclusive writer selection per unit is: actual authorized
withdrawal/rout; received bounded pursuit/withdrawal march; received flank;
received charge; ordinary deployment; nonbattle received march; otherwise hold.
Legality/incapacity/packing checks can turn the selected writer into a reasoned
hold; they cannot fall through to a second writer. A contradictory source/task
fails validation. All members of all fields and nonmoving non-naval peers
participate in the same TIME call. The raw intent remains exactly
`{unit,slot,path_m,budget_m,hostile}`; no presentation-facing override is added.
Provider contracts are pure:

```gdscript
# New BodyBattleMotion; caller alone stages/commits costs and motion.
static func collect_candidate(repo: DataRepository, source: GameState,
        boundary: Dictionary) -> Dictionary
static func plan_candidate(repo: DataRepository, source: GameState,
        boundary: Dictionary) -> Dictionary
# Each provider below returns the same closed contribution, never moves.
BattleGroups.deployment_intent_candidate(repo: DataRepository, source: GameState,
        battle_id: int, unit: String, budget_m: int) -> Dictionary
BattleCharge.intent_candidate(repo: DataRepository, source: GameState,
        battle_id: int, unit: String, budget_m: int) -> Dictionary
BattleTaskSystem.flank_intent_candidate(repo: DataRepository, source: GameState,
        battle_id: int, unit: String, budget_m: int) -> Dictionary
BattleSystem.retreat_intent_candidate(repo: DataRepository, source: GameState,
        battle_id: int, unit: String, budget_m: int) -> Dictionary
ArmySystem.march_intent_candidate(repo: DataRepository, source: GameState,
        unit: String, budget_m: int) -> Dictionary
```

Contribution is exactly `{status,reason,error,unit,path_m}`; status complete/error,
path is desired anchor polyline starting at actual anchor. Complete hold has one
point and nonempty reason. Collector result is exactly
`{status,reason,error,intents,units}`; each sorted units row is
`{unit,writer,budget_m,anchor_path_m}` (writer one of the seven names above).
On error intents/units are empty. Collector derives budget, costs and permitted
routes; caller cannot supply a favorable budget or hostile classification.
BodyBattleMotion.plan_candidate returns the transaction result shape above,
with null candidate and the exact move plan (request={kind:"move"}) on success.
Planning recomputes cost staging on a clone, then calls the single TIME core.
Provider/collector planning leaves source and RNG unchanged.

Actual body paths start at owner rows, with stable slot/home identities. Use
accepted minimum reached ordered route prefix for anchor/remaining-route credit;
unit used_m is max of body polyline lengths, never their sum or endpoint chord.
Each body's translation plus pivot durations fits Q. Stationary peers and tails
are holds, no free interval for deployment after march. Terrain checks include
full measured swept discs, bounds, water, closed cells and scarps, on every
sidestep and stationary pivot. A protected enemy is still a physical obstacle;
a legal empty gap may be routed, not a solid unit rectangle. No final snapping,
teleporting through opponents, trimming a proved plan or unsafe route fallback.

Charge credit uses only its own actually committed continuous approach to its
lawful target. Pivots/sidesteps/wait/enemy movement grant no run-up; changing
heading/target or external displacement resets unfinished credit. One impact
requires existing run-up, actual surface contact and direction. Failure cannot
slide out through enemies. Existing disengage gap plus run-up and a real saved
regroup day are required before another impact. Successful personnel settlement
alone consumes impact. Same-cursor retries cannot add metres, pursuit credit,
flank progress, preparation, run-up or supply consumption.

Existing OrderCosts/warrant filing and courier charges remain in their existing
ledgers, not charged by candidate providers. Candidate gait/run cost is staged
with motion once. Attack extra supplies remain frozen round costs, paid after
successful atomic personnel settlement, not per body/slice/contact. Base food
remains SUPPLY_AND_CONDUCT. No extra RNG stream/draw is used by CF05 motion,
contact, transfer, lifecycle or round-ready.

## Contact, law and exact output for CF06

Physical circles cannot overlap; tangency is legal. Candidate melee contact is
**surface gap**, not legacy front/reserve or centre overlap: with radii rA,rB,
integer centre distance satisfies
`(rA+rB)^2 <= distance_squared <= (rA+rB+C)^2`, C the existing
`battle_group_contact_m` nonnegative whole metres. Terrain must permit the
connecting contact segment; no water/wall contact through a closed cell. Use
checked differences/products and conservative integer comparisons, not narrowed
Vector2i/float32 world coordinates. Real radii remain unchanged. This is the
necessary explicit melee interpretation of physical bodies, not a new ranged
reach formula; ranged centre reach/cone stay unchanged for CF06 to validate.

Query result is exactly `{status,reason,error,battle_id,unit,fit,engaged,pairs}`.
Error returns fit=engaged=0,pairs=[]; complete includes fit from the real ledger
and rows, and counts each own row once if any legal opposing pair qualifies.
Each sorted pair is exactly
`{unit:String,slot:int,target_unit:String,target_slot:int,count:int,
 target_count:int,kind:"melee",reason:String}`.
Pair order is (unit,slot,target_unit,target_slot), duplicates rejected. Multiple
targets do not multiply a row's count; final partial row contributes its exact
count, never a full 100. No role label or missing-store fallback grants contact.
BodyBattle.contacts is the union of these records. Query takes canonical battle
ID (aliases resolved), a real member and unique sorted opposing enemies; absent,
duplicate, wrong-side, hidden target or malformed owner errors rather than
inventing contact. A valid opposing member barred by law/protection is filtered
from outgoing pairs with a reason, not treated as a malformed request. A legal query with no contacts is complete with zero.

Received own laws and `BattleRules.legal_actions(...,unit,target)` plus both
source fields' bilateral protections gate each offensive pair, pursuit and
merge. Protected withdrawal/ceasefire prevents attack but not occupancy;
nonparty C does not inherit A↔B terms after merging. Physical defensive exposure
is distinct from offensive eligibility: CF06 must permit legal incoming damage
and defence without giving a protected/barred attacker outgoing damage. Source
snapshot/party membership survives merge; reinforcement joins only the terms
it actually accepts by existing rules. No general/local plan grants pursuit.

Discovery and merge use actual physical legal contacts, never friendly frames
or anchor range alone. Existing direct-fire merge remains required: an attacking
ranged-equipped unit must have positive actual firing count through the
accepted CF06 ranged query, original sight/task/facing, lawful target, terrain
and blockers from both fields. Before that CF06 query exists, the CF05 driver
must report `deferred: direct_fire_dependency` for ranged merge evaluation;
no centre-range guess, blanket false or claim of complete ranged acceptance.
CF06 integration supplies it after CF05 melee/lifecycle outputs are accepted.
Every cross-field allegiance pair must remain compatible; two towns or any
pending round cannot merge. Survivor selection/aliases/commander union and
warrant remapping retain existing semantics.

CF06-CONTRACT binds this exact query and round-ready envelope; its future
`BattleGroups.melee_counts(repo,state,battle,unit,enemies)` retains the original
`{engaged,fit,reason}` contract by adapting the admitted output. It must count
only lawful actual personnel and make zero-contact outgoing melee exactly zero
before category clamps; reserve organisation cannot become reserve damage.
Its ranged contract retains inclusive reach ±1 metre, facing, actual terrain,
friendly horse/cannon envelopes, target-scoped exposure and no indirect fire.
No duplicate charge/flank/formation factor or hidden range compensation.

## Ownership and lifecycle atomicity

Owner zero means regiment/foe `body_groups`; live battle ID means its
`groups[unit]`. Membership, facing/anchor metadata and rows move together;
there is exactly one owner before and after every published result. Stable
slot/home/count/position/path/facing/counter are preserved by transfer. The
explicit future helper is:

```gdscript
UnitBodies.transfer_battle_candidate(repo: DataRepository, source: GameState,
        unit: String, from_battle_id: int, to_battle_id: int,
        to_side: String, boundary: Dictionary) -> Dictionary
```

It uses the same raw/physical validators, validates destination allegiance and
stage, retains foundation's result shape and performs no movement/personnel
operation. to_side is empty for owner zero, otherwise att/def. Existing
transfer_candidate remains unchanged and frozen-deferred. Sequential internal
transfers are private staging only; a full multi-unit lifecycle has one outer
receipt/publication and one final whole-world validation.

- Enter/start/join: validate full world, snapshot parties before reinforcement,
  create a current empty destination skeleton privately, transfer exact rows,
  then publish enrollment, halt/command metadata and report event. No refresh
  creates new rows or changes pose/facing; turning waits for a later timed move.
- Withdraw/rout: received/legal retreat selects desired route; no removal while
  still physically engaged or lacking a valid departure. Actual motion uses the
  union sweep. Once existing separation/exit law is satisfied, transfer to owner
  zero **before** erasing membership or group metadata; then journal departure.
  No safe destination retains exposed bodies and reason, not a teleport.
- Merge: validate all relations and stage; retain immutable source parties,
  explicitly map each absorbed unit to the survivor side by allegiance; transfer
  every row and snapshot before deleting absorbed field. Fold tasks, reserves,
  reports, supplies, commander history and warrants exactly once. Preserve IDs,
  paths, charge and max already-resolved day so no unit fights twice today.
- End/call-off/cancel: transfer all extant rows to owner zero before report
  snapshot/removing field; retain appropriate task/fee/charge terminal receipts.
  A user task cancellation does not cancel a battle or move its rows. No-repo
  ordinary call_off cannot certify a candidate; explicit candidate requires repo.
- Zero fit/capture: reconcile through the accepted exact personnel transaction,
  retire only required rows, preserve next-slot high water, then transfer the
  valid empty store before removing owner. Never delete a roster entry still
  referenced by an owner. CF05 does not invent death, capture or loss settlement.

All lifecycle operations defer for a valid pending round/decision except that
exact expected acknowledgement and CF06 settlement may advance their own stage.
Malformed frozen records error. Error after any internal transfer discards the
entire clone, including aliases, reports, counters and supply changes.

## Round-ready and frozen personnel settlement seam

At stage round, existing daily processed IDs/order still prohibit a second daily
round. CF05 `round_ready` saves `battle.body_round`, exactly:

```text
{version:"1",token:String,abs_day:String,round:String,motion_receipt:String,
 contact_digest:String,basis:String,contacts:Array,unit_actions:Dictionary}
```

Token is `bodyround:<canonical battle id>:<absolute day>:<next round>`.
Contacts are canonical pair records above; contact_digest hashes them.
motion_receipt names this slice's closed full TIME plan (including holds), whose
digest is in body_battle.closed_motion; a missing/wrong-slice closure rejects.
Unit actions are detached existing BattleSystem action records, including task
IDs/target/reason. Basis is the canonical hash of the exact projection
`[all sole-owner rows and per-unit counters, military_rosters, military_cohorts,
army_roster, regiments, foes, all battle records except body_round/pending_round,
battle_aliases, unit_tasks, received laws, diplomacy, closed_motion, terrain and
footprint/balance/policy/certificate context]`. Administrative outer sequence/
receipt is excluded, so publishing readiness cannot invalidate its own basis;
physical/personnel/task/law/party changes cannot be hidden by that exclusion.
Aliases must resolve consistently. This is immutable provenance, not
another body owner or a speculative damage result. Same ready token is a no-op
only on identical basis; changed basis errors. CF05 returns blocked round-ready
without drawing RNG or calling ordinary damage. It cannot advance past an
unsettled nonempty body_round.

The following future seam belongs to CF06, not CF05 implementation:

```gdscript
BodyBattleRounds.plan_candidate(repo: DataRepository, source: GameState,
        battle_id: int, boundary: Dictionary) -> Dictionary
BodyBattleRounds.commit_candidate(repo: DataRepository, source: GameState,
        proposed: Dictionary, boundary: Dictionary) -> Dictionary
```

It must freeze the existing pending_round payload keys
`day,round,att,def,tier,att_power,def_power,odds,roll,eff,contexts,reason,costs,unit_actions`
and add exactly `body_round_receipt` (SHA256 of body_round). Existing tier/action
extension records keep their existing schemas; no new loss formula is specified
here. CF06-CONTRACT defines its exact plan wrapper/derived rates before product
registration. A ready result is not a pending personnel result.

The first CF06 planning success returns a detached state with pending_round and
one advanced engine RNG state, published atomically together. All subsequent
failed personnel commits retain that same frozen pending payload/draw/costs in
that candidate; they never redraw, move, refit, or replace actions. Source remains
unchanged on each call. Commit verifies its original receipt and current endpoint
basis, uses existing stable military event IDs and grouped personnel transfer,
reconciles surviving body counts without relocation, pays frozen attack supplies
once and consumes impact only on full success. It clears body_round/pending_round
and advances processed/day cursors together. Already settled retries consult the
same full outcome receipt, including zero-loss morale effects; tampering errors.
A changed command after readiness applies to the next unprocessed round only.
Legitimate legacy pending_round without body provenance is not silently upgraded.

## Independently reviewable future steps and exact ownership

These are proposed IDs/files, **not registrations or dispatch**. Every product
step waits for this accepted document, actual accepted LOCO-MARCH, accepted
placement and all actual new prerequisites it consumes. Reconcile actual main
interfaces then; any necessary extra literal path is registered before editing.
Do not append these scopes to #206 or any active immutable task. Shared paths
below force serial execution even where mathematical dependencies permit more.
New `.gd` files own their same-named `.gd.uid`; those pairs are listed explicitly.
Each step below has a distinct rejection boundary, not one PR per method:
placement v2 completion; raw admission; paid timed movement; timeline closure;
physical/lawful contact; entry ownership; deployment route; earned impact;
received flank route; exposed retreat/exit; bilateral union; terminal release;
and frozen round-ready/day continuation. Each exposes the tested interface
described above and can fail its own invariants while its neighbors pass.
Only the driver waits for every provider; pure provider APIs are actual
read-only results tested without publishing an incomplete day.
Each new test is appended to engine-military in tests/categories.json in its own
PR, without altering precedence, old assertions or expensive-suite gates.

1. **B-PV2 — placement completion seam.** Own
   `scripts/engine/unit_bodies.gd`, `tests/engine/test_body_placement.gd`,
   `tests/engine/test_unit_bodies.gd`, `scripts/engine/guide/body_placement.md`.
   Accept the actual merged v2 completed MARCH boundary/inner receipt explicitly;
   retain metadata-only operations, v1 behavior, frozen payload and costs.
   Do not initialize missing rows or silently upgrade v1. Independently rejectable
   even with no battle implementation; prerequisite of B-BOUNDARY.
2. **B-BOUNDARY — raw battle admission/transfer/save seam.** Own
   `scripts/engine/unit_bodies.gd`, `scripts/engine/day_resolution.gd`,
   `scripts/engine/game_state.gd`, `scripts/engine/guide/cluster_formations.md`,
   `tests/engine/test_body_battle_boundary.gd`,
   `tests/engine/test_body_battle_boundary.gd.uid`, `tests/categories.json`.
   Implement exact validator/marker/raw loader and transfer helper only; no
   movement/day driver. Depends B-PV2. Validate private empty destination staging
   without exposing an owner-incomplete candidate or relaxing final validation.
3. **B-TIME — one paid/budgeted tactical timeline.** Own
   `scripts/engine/army_system.gd`, `scripts/engine/body_motion.gd`,
   `scripts/engine/body_battle_motion.gd`,
   `scripts/engine/body_battle_motion.gd.uid`,
   `scripts/engine/guide/body_marches.md`,
   `tests/engine/test_body_battle_budget.gd`,
   `tests/engine/test_body_battle_budget.gd.uid`,
   `tests/engine/test_body_battle_timeline.gd`,
   `tests/engine/test_body_battle_timeline.gd.uid`, `tests/categories.json`.
   Depends B-BOUNDARY; reuse march contribution and existing timing core for
   one complete staged-cost/move transaction, including terrain and replay.
   Collector extraction is part of this deliverable, not a scaffold PR. Pure
   tests use explicit provider contributions; absent tactical providers reject.
   Independently reject if a union move spends twice, clips time incorrectly or
   accepts forbidden terrain, even if subsequent lifecycle writers are correct.
4. **B-CLOSE — completed timeline retirement.** Own
   `scripts/engine/body_motion.gd`, `scripts/engine/unit_bodies.gd`,
   `scripts/engine/army_system.gd`, `scripts/engine/guide/body_marches.md`,
   `tests/engine/test_body_battle_closure.gd`,
   `tests/engine/test_body_battle_closure.gd.uid`, `tests/categories.json`.
   Depends B-TIME; explicit Q closure, raw closed-control admission and shared
   cursor/priority handoff, no casualties, lifecycle or renderer changes.
5. **B-CONTACT — physical/lawful pair query.** Own
   `scripts/engine/body_battle_contact.gd`,
   `scripts/engine/body_battle_contact.gd.uid`,
   `scripts/engine/guide/battle_groups.md`,
   `tests/engine/test_body_battle_contact.gd`,
   `tests/engine/test_body_battle_contact.gd.uid`, `tests/categories.json`.
   Depends B-BOUNDARY; implements query only, no old melee damage replacement.
6. **B-ENTER — start/join ownership.** Own `scripts/engine/body_battle.gd`,
   `scripts/engine/body_battle.gd.uid`, `scripts/engine/battle_system.gd`,
   `scripts/engine/guide/battle_groups.md`,
   `tests/engine/test_body_battle_enter.gd`,
   `tests/engine/test_body_battle_enter.gd.uid`, `tests/categories.json`.
   Depends B-CLOSE+B-CONTACT. Implement plan/commit for contacts/enter only;
   unimplemented request kinds reject, no incomplete public day driver.
7. **B-DEPLOY — deployment provider.** Own `scripts/engine/battle_groups.gd`,
   `scripts/engine/body_battle_motion.gd`, `scripts/engine/guide/battle_groups.md`,
   `tests/engine/test_body_battle_deploy.gd`,
   `tests/engine/test_body_battle_deploy.gd.uid`, `tests/categories.json`.
   Depends B-ENTER. Preserve ordinary translate/follow_anchor entry points until
   activation; candidate provider never invokes them or refreshes missing rows.
8. **B-CHARGE — earned approach/impact.** Own `scripts/engine/battle_charge.gd`,
   `scripts/engine/body_battle_motion.gd`, `scripts/engine/guide/battle_charge.md`,
   `tests/engine/test_body_battle_charge.gd`,
   `tests/engine/test_body_battle_charge.gd.uid`, `tests/categories.json`.
   Depends B-DEPLOY; provider plus settlement of actual credit, no personnel damage.
9. **B-FLANK — received real route provider.** Own
   `scripts/engine/battle_task_system.gd`, `scripts/engine/body_battle_motion.gd`,
   `scripts/engine/guide/battle_deployment.md`,
   `tests/engine/test_body_battle_flank.gd`,
   `tests/engine/test_body_battle_flank.gd.uid`, `tests/categories.json`.
   Depends B-CHARGE; actual received snapshot/path, bounded pursuit and contact
   phase from committed legal movement, no instantaneous side/rear bonus.
10. **B-WITHDRAW — retreat/rout transfer.** Own
    `scripts/engine/battle_system.gd`, `scripts/engine/body_battle.gd`,
    `scripts/engine/body_battle_motion.gd`, `scripts/engine/guide/battle_groups.md`,
    `tests/engine/test_body_battle_withdraw.gd`,
    `tests/engine/test_body_battle_withdraw.gd.uid`, `tests/categories.json`.
    Depends B-FLANK; route contribution and separated exit only, blocked remains
    exposed. No end/cancel/merge or general destruction added here.
11. **B-MERGE — field union.** Own `scripts/engine/battle_merge.gd`,
    `scripts/engine/body_battle.gd`, `scripts/engine/guide/battle_merge.md`,
    `tests/engine/test_body_battle_merge.gd`,
    `tests/engine/test_body_battle_merge.gd.uid`, `tests/categories.json`.
    Depends B-WITHDRAW; transfer-before-delete, side map, aliases/parties/tasks.
    Ranged branch remains explicit dependency until CF06; no false complete claim.
12. **B-END — end/cancel/call-off release.** Own
    `scripts/engine/battle_system.gd`, `scripts/engine/body_battle.gd`,
    `scripts/engine/guide/battle_groups.md`,
    `tests/engine/test_body_battle_end.gd`,
    `tests/engine/test_body_battle_end.gd.uid`, `tests/categories.json`.
    Depends B-MERGE; all units transfer before deletion, empty/zero-fit/capture
    post-reconciliation cases, terminal receipts and report preservation.
13. **B-ROUND — round-ready and resumable candidate driver.** Own
    `scripts/engine/body_battle.gd`, `scripts/engine/battle_system.gd`,
    `scripts/engine/tick_engine.gd`, `scripts/engine/day_resolution.gd`,
    `scripts/engine/guide/battle_groups.md`,
    `tests/engine/test_body_battle_motion.gd`,
    `tests/engine/test_body_battle_motion.gd.uid`, `tests/categories.json`.
    Depends B-END plus all B steps; implement step/begin/acknowledge/advance and
    readiness only. CF06 damage/round settlement remains separately contracted.
    No ordinary resolve_day caller, boot or render change.

No fixture file is implicitly owned: use SuiteData copies, existing personnel
helpers and local test setup; shared `tests/fixtures/battle_scenario.gd` and old
road/defeat fixtures remain unchanged. If meaningful setup needs a common new
fixture, propose its exact path first. Guides are existing paths; no nested
CLAUDE size bypass or speculative current-behavior rule before implementation.

DAG: accepted contract + actual engine predecessors → B-PV2 → B-BOUNDARY →
B-TIME → B-CLOSE; B-BOUNDARY → B-CONTACT; B-CLOSE+B-CONTACT → B-ENTER →
B-DEPLOY → B-CHARGE → B-FLANK → B-WITHDRAW → B-MERGE → B-END → B-ROUND.
Because categories/guides overlap, dispatch these product steps serially.
CF06-CONTRACT follows this accepted document without waiting for art; CF06
products wait their contract and actual accepted B-ROUND and required B outputs.
CF06 then completes direct-fire discovery/merge and pending settlement before
candidate battle acceptance is whole. There is no CF05-product→CF06→CF05-start
cycle: the pending direct-fire edge is a completion gate, never assumed supplied
by B-MERGE. Later cluster writers and render/art branches converge at activation.

## Executable future tests and hand calculations

For **each** B step: write its named failing GUT test, run the bounded command
and observe the intended missing behavior; implement only owned scope; run the
same command green plus named regressions; inspect selector; commit/PR with
frozen input hashes and original failure evidence. No formula body is prescribed
by this document. Future command for a named file is
`./run_tests.sh --test tests/engine/<file>.gd` (substitute the literal name below).
Pure document checks here do not execute these future game tests.

- B-PV2 `test_body_placement.gd::test_v2_completed_metadata_preserves_receipts`:
  accepted v2 final cursor permits leave/camp metadata, exact frozen transaction,
  rows/cost/RNG unchanged; incomplete, wrong receipt, v1-as-v2 and future/mixed
  controls reject. Run old placement and unit_bodies files in full as well.
- B-BOUNDARY `test_body_battle_boundary.gd::test_raw_roundtrip_and_transfer`:
  transfer 901 fit rows counts [100×9,1], source battle 8 to destination 3 with
  reversed side; ten identities/poses/paths retained, sole owner=3, next-slot
  unchanged. Duplicate owners, missing groups, invalid side, unfinished
  reconciliation and raw booleans/fractions/unknown keys/future controls fail.
  JSON test both import provenance branches and encoded-looking strings above;
  no decoder launders corruption. Legacy v6/v7 and frozen v1 remain untouched.
- B-TIME `test_body_battle_budget.gd::test_one_share_and_writer`:
  test-injected daily effective D=25,N=10 yields [3,3,3,3,3,2,2,2,2,2], sum25.
  Deploy cap=20 gives [2×10]; a unit offered both march and charge receives one
  writer, budget min(share,cap), never sum. Real tables remain unchanged. A day
  with 10 bodies charges per-unit supply once, not ten times. Waiting after paid
  run follows existing pays_run semantics; final validation error rolls it back.
- B-TIME `test_body_battle_timeline.gd::test_pivot_consumes_same_slice`:
  explicit pure-math policy turn_q=1,000,000, B=100, yaw0=0, path (0,0)→(0,50),
  final facing0: pivot +90 250,000q, move50 500,000q, pivot -90 250,000q,
  used=50, no hold. Request 51 along the same axis cannot fit the required final
  turn; returned prefix <=50. Reuse TIME axis/diagonal/180/wrap tests, continuous
  crossing and stationary-pivot holds; JSON sample equality at boundaries.
  Separate real-radius bodies on a valid injected terrain grid test closed-cell
  corner/edge/out-of-bounds/scarp crossings, including detours. Endpoints legal
  with forbidden middle must reject the whole slice without paid cost/RNG drift.
- B-CLOSE `test_body_battle_closure.gd::test_close_then_loss_does_not_replay`:
  close active movement at Q with all identities verified; delete no pose during
  closure, transfer priority/digest exactly. Reopening the same/older cursor or
  forging closed control fails. After a separately staged valid tail-row loss
  at the round boundary, next slice admits surviving rows without replaying the
  retired plan; original movement retry is stale. JSON before/after closure gives
  identical next priority/budget; early closure, changed endpoint/policy/grid or
  unknown descriptor field rejects atomically. No supply or RNG change.
- B-CONTACT `test_body_battle_contact.gd::test_real_radius_surface_edge`:
  infantry927+cavalry804 → separation1731 tangent, upper melee edge1831 with
  current C100; 1831 contact, 1832 zero; 1730 rejects overlap. Test last counts
  [100,1]: only last row contacting yields engaged1; row touching two opponents
  counts once. Protected target, closed contact segment and reserve not touching
  give zero outgoing pairs; friendly frame overlap never discovers/merges a field.
- B-ENTER `test_body_battle_enter.gd::test_founders_and_join_do_not_reseed`:
  two real-radius lawful touching founders keep all exact rows; joining ten-row
  member moves owner0→field once. Enemy pending decision/round defers, malformed
  one errors; friendly overlapping frames give no start event or spent cost.
- B-DEPLOY `test_body_battle_deploy.gd::test_union_sweep_and_open_gap`:
  opposing/three-way relative paths are checked for entire Q; hold/blocked reasons
  stable under input permutation. A real-radius empty corridor can pass, a
  narrower one cannot. All returned body legs <= one allowance; repeated cursor
  adds zero anchor, preparation or metre credit. Preserve translate/follow_anchor
  production regressions without weakening them.
- B-CHARGE `test_body_battle_charge.gd::test_runup_replay_and_regroup`:
  with current required run-up300, committed straight approach299 has no impact;
  300 plus actual lawful contact may impact. Same full receipt twice remains300,
  not600; target/heading change resets unfinished credit. Short blocked charge
  cannot emerge inside/beyond enemy; no impact consumption on failed personnel.
  Run `test_charge_runup.gd` unchanged.
- B-FLANK `test_body_battle_flank.gd::test_waypoints_and_received_cancel`:
  real detour A→B→C must reach B before C; no corner shortcut or side/rear credit
  before actual contact. Pending cancel does not stop old received task; delivered
  cancel holds next unprocessed action without refund/double filing. Blocked wing
  waits without falsely completing both wings. Bound pursuit retains route budget.
- B-WITHDRAW `test_body_battle_withdraw.gd::test_blocked_retreat_keeps_owner`:
  blocked withdrawal remains exposed battle-owned; swept legal separation then
  transfers exact rows to owner0 before membership removal. No safe destination
  retains pose/reason. Protected bodies block hostile movement without granting
  illegal attack. Run `test_battle_task_retreat.gd` and terms scope unchanged.
- B-MERGE `test_body_battle_merge.gd::test_bilateral_parties_and_side_swap`:
  A↔B ceasefire does not protect unrelated C; after compatible side swap the
  original party sets, ten-row slots/paths/charge/task and alias survive verbatim.
  Pending round, two towns, friendly contact and incompatible allegiance union
  do not merge. Ranged query unavailable returns explicit dependency, never PASS.
  Run `test_battle_merge_warrants.gd`, `test_battle_terms_scope.gd` unchanged.
- B-END `test_body_battle_end.gd::test_release_before_delete_and_rollback`:
  end/cancel frees each of three units' stores exactly once with report/terminal
  receipt; zero-fit empty store still has a valid owner until transfer. Failure
  on last transfer publishes none of earlier two/aliases/reports/costs. Direct
  and JSON exact retries preserve source file and state hash. No-repo candidate
  call errors without deleting a field; pending round defers unchanged.
- B-ROUND `test_body_battle_motion.gd::test_mid_slice_round_ready_json_retry`:
  save after every transition, including encounter block and readiness; compare
  endpoint save, queue, all receipts, personnel, costs and RNG to uninterrupted
  candidates. Retry changed terrain/policy/radius/diplomacy/law/party/row/route/
  budget errors with exact input hash unchanged. Ready contact100/fit1000 freezes
  engaged100, leaves900 unengaged; no damage or RNG yet. Round absent CF06 stays
  blocked. No unit resolves twice through aliases/merged already-processed IDs.

CF06 required executable follow-through (its contract assigns exact test files):
fit1000/engaged100 uses100 outgoing melee, other900 contribute0; engaged0 gives0
before clamps; final1 contributes1. First round planning draws once; failed
personnel transfer and JSON retry retain exact roll/losses/actions/costs/charge;
commit/retry conserves fit+wounded+dead+captured and charges once. Fire inclusive
reach r-1/r versus r+1, facing/cone, friendly horse/cannon/own-front blockers and
terrain determine actual firing; moving out of range stops fire and can prevent
ranged merge. Run original `test_group_contact_strength.gd`,
`test_ranged_fire_geometry.gd`, `test_ranged_contact_merge.gd`,
`test_battle_conservation.gd` without weakened assertions. Readiness is not proof
these future formulas or round/performance acceptance have passed.

## Preserved gates, activation and document acceptance

All twelve spec §9 gates remain: (1) 1000/901/900/1/0 exact personnel and ten
bodies with fixed footprint; (2) full-radius opposing/three-way/narrow/turn/reload
sweeps; (3) two-versus-three selection and all eight eligibility sets; (4) own
speeds, assembled slowest speed, terrain/injury/supply/local budgets; (5) actual
courier receipt/version and actual king presence; (6) vulnerable assembly and
stable old line; (7) expansion/reform/partial selection/one membership; (8) each
of eight normal/blocked/member-loss cases; (9) actual melee/direct fire/occlusion
and explained nonduplicated bonuses; (10) pause/1x/4x/camera/save deterministic
cost/personnel behavior; (11) reproducible equal-input formation-versus-none and
countered outcomes; (12) unique 3D map real-window visual/performance acceptance.

Original CF05/CF06 assertions and military law, bilateral parties, existing cost,
run-up, personnel, save and determinism regressions survive. Inherited frozen
input `19bd7a5b9deb50a1bb1820aac2348e9e20adb8400484d1e3ab6e0729da2fbfb5`
remains **55 failures and 6 risky/pending**; this doc neither reruns nor clears
one. Actual unchanged road-contact/defeat day-continuation, fresh real campaign
placement/boot/roundtrip, military reorganization, valid old-save preservation,
corrupt/future-save rejection without overwrite and final runtime gates remain
activation requirements. No fixture resize, assertion/range/R/scale compensation,
new physics, threshold/CI waiver, production flag or permanent fallback.

Policy injected into SuiteData copies proves pure candidate math only. Real
production radii are retained in body contact/terrain tests; small math examples
do not prove a campaign, installed policy or all-arm continuous animation.
CF01's seventeen sampled poses and artillery-infantry substitute remain limits.
All five arms need full continuous contact/envelope certification, then actual
near/far pause/1x/4x/different-FPS native-window visual-review and performance on
final inputs. No headless 3D/screenshot/numeric-circle substitute.

Final activation switches ALL writers atomically: opening/AI spawn, growth/
recruit/split, settlement/arrival/march, enter/merge/withdraw/end/cancel, damage
reconciliation, load publication and live render bridges. Candidate battle and
old production damage cannot be mixed in a live world. Render/art/policy and
engine branches converge before this barrier; no partial battle activation.
PR201 remains active with its original owners and preserved R1 FAILED; specific
terminal authorization is pending. This contract changes no registry, active
owners/dependencies/acceptance, claims or terminal status.

This PR owns only this document. Verify exact source references, schema/type and
DAG consistency, arithmetic, links/scope/requirement coverage, whitespace and
workflow-native Python hook/selector/runner/timeout, shell/config/guide checks;
selector must explicitly choose no GUT. Unique independent Review checks those
results plus required current-HEAD `harness-checks`/`gut-tests` and only then
merges. No Godot/Blender/game tests/visual/performance pass is claimed here.
Implementation makes any review fixes in this same PR; this pair ends after
merge. Only the original dispatcher registers later steps, one bounded PR each.
