# Passive unit bodies

The route to switching this feature on, and the owner rulings that override earlier contracts (contact bounds, skin diagnostic, sampled certification, Gram predicate, ownership), are `docs/superpowers/plans/2026-11-10-cluster-activation.md` and `docs/reviews/cluster-formations/owner-rulings-2026-11-10.md`.

`UnitBodies` is an engine-pure, opt-in candidate API. Its authoritative contract
is `docs/reviews/cluster-formations/cf02-foundation-contract.md`. It has no
production lifecycle, load, march, damage or render callers.

- `rows` returns detached existing rows from the sole live battle owner or the
  unit's nonbattle `body_groups`; absent, malformed or ambiguous data yields no
  rows. It never materializes bodies. `footprint` and `home_slots` read
  `data/army/unit_footprints.csv`, calibrated from CF01 measured circles: ten
  local homes and fixed width/depth independent of personnel. Artillery is the
  accepted infantry substitute; the finite animation samples remain a limit.
- `migrate_candidate` validates supported save provenance, ownership, raw integral
  numbers, paths, versions, count partitions, identities and measured circles.
  Circle checks reject wrapped coordinate differences and exclude distant axes
  before squaring; whole-metre int64 positions remain valid and tangency is legal.
  It deep-copies the entire state without load-time normalization or RNG use.
  Complete worlds receive `military_migration.body_version`; partial legacy
  worlds request placement without inventing a point. Converted battle markers
  describe row schema. Safe legacy regroup consumes saved slots in order,
  retaining the first survivor's point/path/role and never reusing retired IDs.
- `reconcile_candidate(repo, source, unit, previous_fit: Variant)` requires an
  otherwise complete world whose named unit alone has staged personnel. Raw
  previous and target fit must be finite whole numbers, excluding booleans.
  Surviving rows keep their homes and every field except canonical counts. Tail
  rows retire; counters do not decrease. Growth requiring new rows saves the
  closed unit descriptor `body_reconciliation={version,basis_fit,target_fit}`.
  Only this validated pending prefix may disagree with ledger totals. Its
  missing homes are the lowest unused layout identifiers. Direct/JSON retries
  use migration, never repeat the personnel operation or allocate new slots.
- `transfer_candidate` is repo-free and structural: callers first obtain a
  repo-validated complete world and preserve its poses/configuration. It moves
  exact rows, membership and per-unit body metadata in a detached candidate,
  preserving other records and personnel. Growth after exit reads the saved
  sole-owner `group_facing`, with explicit unit `facing_deg` taking precedence.
  Pending descriptors are prohibited.
  It cannot certify geometric validity or publish live state.
- Results have exactly `status,reason,error,candidate,placement_requests`.
  `complete` and `needs_placement` carry detached candidates; `error` and
  `deferred` carry none. Frozen day/round transactions are validated before
  deferral, retaining all rows/cursors/costs until the safe boundary. Legal
  legacy twenty-row size-50 worlds are not judged as current ten-row worlds.

Body-opted saves preserve invalid raw cohort fit for candidate rejection before
legacy rounding; unopted saves retain their existing normalization.
Passive serialization preserves present fields and creates no bodies or
pending defaults. Save constants stay 7/6. Placement, production activation,
physical movement, visuals and performance remain separate accepted steps.

Present nonbattle arrays use the current required fields even without the global
completion marker. A legacy battle with a present groups map must include each
member; only an absent whole map is missing placement. Safe conversion canonicalizes
legacy partial counts and makes known group-size metadata explicit, including
empty battles, without adding a point. Unit-facing/anchor snapshots follow their
sole body owner. Retained battle records cannot hide unsupported control versions.

## Candidate body motion (`BodyMotion`)

`plan(repo,state,intents,abs_day,substep)` is a pure query over an explicitly
initialized, complete, unfrozen current-body candidate. It rejects missing,
pending, deferred or invalid bodies instead of initializing them. Each closed
intent is `{unit,slot,path_m,budget_m,hostile}`; the integer polyline starts at
the sole authoritative row. Duplicate identities, negative budgets, fractional
coordinates and malformed control fields fail closed. Only this candidate API
calls `BodyMotion`; ordinary movement, lifecycle, damage and rendering remain
unchanged until activation.

A successful result has exactly `{moves,blocked,reasons,cursor}`. Move rows are
`{unit,slot,path_m,used_m,budget_m}`, including the original point and every
actually travelled integer waypoint. `used_m` is the sum of each segment's
Euclidean length rounded UP to whole metres; clipping never exceeds budget.
Integer-square correction prevents floating sqrt from undercounting a metre.
Motion traverses each segment for `segment_cost / budget_m` of a common substep,
then remains at its endpoint until substep end. Relative piecewise-linear sweep
checks the continuous minimum separation against measured CF01 circles; those
circles also conservatively cover rotation. Endpoints alone are insufficient.
Local arithmetic uses doubles after checked int64 subtraction, never float32
world vectors. Overlarge local paths/budgets/radii fail closed at the numerical
range boundary; whole int64 world positions are not narrowed. General grazing
within a floating-point error bound is conservatively blocked; exact constant
axis separation and exact monotone endpoints preserve integer tangency.

Reservations start stationary for ALL bodies, not unit deployment rectangles.
Saved progress priority then `(unit,slot)` selects each reservation once. Friendly
bodies can take bounded alternating lateral routes that rejoin the requested
polyline within the same budget. Enemy/hostile obstacles do not grant that
bypass. Otherwise the body advances a swept-clear integer prefix or waits with
a causal blocked reason. Search is finite (`cluster_motion_detour_attempts`,
`cluster_motion_clearance_m`), with no repeated reservation charge, sideways
retreat loop, instant relocation or fixed unit-rectangle wall. This is a local
conservative body planner, not terrain routing: candidate binding must validate
EVERY returned segment, including sidesteps, against terrain before publication.
Commit certifies body geometry only. No success claims production interception
or throughput.

Public cursor is closed:
`{version:1,abs_day,substep,basis,intents,priority}`. Intents are canonical sorted
requests; priority contains progressing friendly `{unit,slot}` identities. Basis
hashes canonical source save plus footprints and motion configuration.
`commit(repo,state,plan)` is only for the caller's EXPLICITLY ISOLATED candidate,
never live production state. It validates the source, replans and compares the
entire result, updates only sole-owner rows in a detached foundation candidate,
revalidates the whole physical world, then publishes rows/metadata to that
isolated argument. Other state and RNG stay unchanged. Result is
`{status:"complete"|"error",reason}`. Rejections publish nothing.

The only persisted motion control is `military_migration.body_motion`:
`{version:"1",abs_day:String,substep:String,receipt:String,priority:Array}`.
Day, substep and each priority identity's slot are canonical nonnegative decimal
STRINGS; receipt is the canonical full-plan SHA256, and each priority item is
`{unit:String,slot:String}`. Strings deliberately bypass the existing save
loader's legacy numeric rounding; malformed numeric controls must not become
valid by loading. Present empty/null/future/unknown fields fail; absence alone
means no receipt. The same cursor with the identical receipt is a lazy no-op
through direct/JSON retry. Changed receipts at that cursor and older cursors
error. This metadata contains no duplicate poses, personnel or paid-cost ledger.
CF01 finite animation samples/artillery substitute and later production,
visual and performance acceptance remain explicit limits.

`UnitBodies.validate_placement_candidate` validates raw placement controls and
safe/completed-MARCH boundaries without creating a row or removing frozen data.
Placement transactions and replay, and load classification (`BodyLoad`): `scripts/engine/guide/body_placement.md`.

## Candidate battle boundary

`UnitBodies.validate_battle_candidate` and `transfer_battle_candidate` implement
the raw admission/ownership seam of `docs/reviews/cluster-formations/cf05-battle-contract.md`.
They require complete current bodies and reject pending reconciliation, duplicate
owners, missing stores, unsafe JSON numbers, unknown control keys and versions.
Validation reuses the foundation's personnel, partition, identity and measured
circle checks without clearing a frozen day, allocating rows or repairing input.

`DayResolution.body_battle_incompatibility_reason` checks the closed v4 battle
marker, mirrored queue/index, processed prefix, stage and substep boundaries.
Admission also checks actual live canonical field IDs and the daily processed-unit
barrier. Ordinary day and MARCH consumers reject this marker; both markers
together are corruption. The frozen day must match the source calendar. Owner
anchors share the row coordinate bounds. Candidate round actions, supply costs,
parties, contexts and tier extensions retain their existing typed schemas and
reject malformed nested values before frozen deferral. Safe boundaries defer on valid frozen days/rounds only
after raw validation. Active battle movement requires the separate TIME consumer;
round envelopes remain frozen for their own readiness/settlement consumer.

GameState writes the new day control, outer receipt and candidate round envelopes
as plain JSON and preserves them before legacy value conversion in both import
branches. Exact safe integral JSON numbers canonicalize; encoded-looking strings,
booleans, fractions and future schemas remain visible to rejection. Legacy saves
and v1 MARCH receipts retain their existing codecs and save versions.

Transfers explicitly validate destination side/allegiance and move sole-owner
rows, membership, facing and anchor snapshots together on a detached clone.
Enrollment and field-to-field transfers require contact; exits require advance
or a safe boundary. Completed v2 placement proofs use the existing full proof
validator before safe admission defers with the frozen day intact.
Complete empty destination skeletons are allowed; missing groups/markers are not.
Every resulting world passes the same physical/count/owner validation. Poses,
paths, slots, counts, next-slot high water, resources, personnel and RNG stay exact.
This helper returns private ownership staging for an enclosing lifecycle
transaction, which must seal its own outer plan/receipt/result before publication;
it does not create that transaction or certify battle law, departure or contact.
Saved outer endpoint digests are checked against the full save and the unchanged
terrain/footprint/balance/policy/diplomacy context before admission. No movement,
day driver, lifecycle, damage, production activation or visual acceptance is added.

## Candidate round reconciliation

`BodyRoundReconcile.reconcile_round_candidate(repo, source, {battle_id, round}, boundary)` (its own file: `unit_bodies.gd` is a SHA-256-pinned premise of the royal carrier proof, `Map3DRoyalCarrierSource._SOURCES`, so it stays unedited)
brings a frozen round's settled personnel losses to its bodies inside the CF06
settlement's private stage. It checks provenance first: the saved round-stage
boundary, a canonical live field, that round's `body_round` and `pending_round`
with the matching receipt, and the round's personnel event
(`battle:<id>:round:<n>:personnel`) touching only the round's participants.
Each participant whose rows exceed its fit keeps its first rows in stored order
(the order canonical counts follow) with their identity, home, position, path and
facing, and canonical counts, and no row ever holds more than before; the
rest retire, an empty store keeps its owner, and `group_next_slot` keeps its
high water so a retired slot is never reused. Growth, a non-participant in the
event, an unrelated staged personnel change (the whole-world body/fit check) or
an invalid world reject. The event must be the applied
`transfer_units` receipt moving fit personnel to wounded, dead or captured, on the
current queued field at the saved boundary; each participant's bodies must equal
its fit before that event (or already its fit: a retry is a no-op), so another
staged loss on a participant rejects unless it exactly offsets the round's own
numbers, which only the settlement's basis proof can catch. It returns UnitBodies' five-field result, leaves the round
open (the envelope and payload stay) and draws no RNG. Non-personnel staging
(rows, tasks, laws) is the caller's to prove: the settlement checks the round's
`body_round.basis` on its admitted pre-settlement world before applying the event.

## Candidate round planning

`BodyBattleRounds.plan_candidate(repo, source, battle_id, boundary)` plans the
current queued round-ready field once. It admits the frozen readiness (the
whole-world validator's frozen-round deferral after every raw and endpoint check),
requires an unchanged `body_round.basis` and its closed motion, then works on a
private probe without the envelope (resealed) so the physical queries can run.
Every participant's live `unit_action` must equal its frozen action (else error;
the queries never use a reselected one). Attacking units contribute
`BattleSystem.candidate_power` (an uncommitted reserve adds none, as in
`side_power`) and pay the attack food once each, the others the full defence chain, with the existing non-contact factors (height, defence stance and
camp, events, frozen order). One `rng.randi_range(0, 999)` gives the roll, then
`odds_permille`, `eff_permille` and `tier_of`; every participant's rate and
morale exposure come from `candidate_sources` / `candidate_context`. The
existing pending payload (plus `body_round_receipt`), the exact effects through
`BattleSystem._plan_side` (grouped orders, unit results, charge units, family
event IDs `battle:<id>:round:<n>:<unit>`) and the closed plan wrapper
`battle.body_round_plan` `{version:"1",receipt,plan}` publish with that one
draw under the outer `{kind:"round_pending"}` operation. A repeat re-checks the
basis, the wrapper, the pending equality and that outer receipt, then returns the
frozen state unchanged (no second draw); a changed basis or tampered payload
errors. The proofs are keyless: a forger who recomputes every digest is not
stopped (the RNG after the draw is not bound in the closed plan), and erasing
both the pending and the wrapper then resealing the endpoint plans afresh with a
second draw. Defence carries no contact participation factor
(cf06-power-contract §defence); production still applies it until ACT-CUTOVER. Readiness
(`BodyBattle` round_ready) first applies production's side fallback, so a
law-barred or unaffordable all-out attack is frozen as hold. `GameState` keeps the wrapper raw like the envelope, and the readiness
basis excludes it. No personnel, morale, cost, impact or cursor changes: that is
the settlement.

## Candidate round settlement

`BodyBattleRounds.settle_candidate(repo, source, plan, boundary)` commits the
current field's frozen plan. It admits the round-stage boundary, the saved
wrapper equal to `plan`, the outer `round_pending` as the last operation and an
unchanged `body_round.basis`, then works on a clone in the ordinary round's
order: `BattleSystem.apply_round` (event `battle:<id>:round:<n>`, transfer
`:personnel`; its results must equal the frozen `unit_results`, zero-loss
morale included), `BodyRoundReconcile` for the bodies, `_settle_family_losses`
(the added IDs must equal the frozen ones; a refused ID fails), custody, the
frozen costs, committed reserves and the earned impact (must equal
`charge_units`). It writes the full receipt
`bodyround:<id>:<day>:<round>:settlement` `{request:{kind:"body_round_settlement",plan},
result:{pending,effects,personnel_event_id,round_event}}`, clears `body_round`,
`pending_round` and `body_round_plan`, marks the field and its units processed,
advances the queue (to `advance` when exhausted) and seals the outer
`round_settle`. A failed writer (personnel, bodies, family, custody) returns
blocked with the unchanged pending source and the same plan; the frozen draw
stays. A retry whose receipt exists with the same plan is a detached no-op; a
different plan errors. Exits, routs and ends are not run here: the advance
stage's lifecycle requests own them, and a tier's rout is only recorded in the
round event until ACT-CUTOVER. The ordinary round event (`left` empty) is
appended to the day's `journal.battles` and kept in the receipt's `round_event`.

## Candidate lifecycle adapter (ACT-LIFECYCLE)

`BodyLifecycle.commit_candidate(repo, source, plan, boundary)` (its own file, for the same
pinned-source reason) commits one lifecycle edge's `BodyBattle.plan_candidate` plan — `contacts`
(start, join or merge on discovery), `enter` (join), `merge`, `withdraw` (exit), `end`/`cancel` —
and then proves it a zero-delta ownership transfer; any other request kind errors. `snapshot`
keys every land unit's bodies by stable identity whichever container owns them (battle
`groups` or nonbattle `body_groups`): rows by slot, anchor, group and unit facing, slot high
water and owner battle. `continuity_error` requires every `(unit, slot)` to keep its exact row
(point, facing, count, home, role, path) in the same order, the same anchors, facings and next
slot, unchanged personnel and RNG, and the motion cursor either kept (with `closed_motion`
unchanged) or closed into exactly `body_battle.closed_motion`. Owners move only as the edge says: `enter` its unit in, `withdraw`
its unit out, `end`/`cancel` every member to owner zero, `contacts` may enroll nonbattle units,
and an absorbed field's units follow its alias to the survivor; a replay of the committed
receipt moves no one. A failed proof returns an error and no candidate, so nothing publishes.
Deferrals come from `BodyBattle` unchanged: a decision is lawfully pending only at the round
stage, where every lifecycle edge waits for its own stage; an ongoing field's `end` waits too.
Nothing in ordinary dispatch calls it: `BattleSystem`'s `_start`/`join`/`_exits`/`_end`,
`BattleMerge.day` and `BattleGroups.refresh` keep their behaviour until ACT-CUTOVER routes the
admitted world through this adapter together with the driver and the projection.

## Candidate day driver (ACT-DRIVER, part A)

`BodyDayDriver` (its own file, inactive like the adapter) is the one admission and driver every
ordinary writer of an admitted body world shares. `admit(repo, source, prepare)` copies the
source, runs the optional `prepare(repo, copy) -> {status, reason, candidate}` (the seam ACT-LOAD's
fresh initialization and legacy classification plug into; a refusal fails closed), then requires
`body_version`, no ordinary frozen day, a complete `validate_battle_candidate` at the safe boundary
or at a saved body day's boundary (a published frozen round admits as it stands) and every land
arm's installed policy. `tactical_day` admits, begins at the safe boundary, then takes
`BodyBattle.step_candidate` transitions (march and withdrawal on the budgets `begin` froze) until
the day completes, returns `blocked` at a pending encounter decision (`acknowledge` answers it), or
errors with no candidate; a step ceiling per slice bounds it. `BodyBattle._run` commits every
lifecycle edge (`BodyLifecycle.EDGES`) through `BodyLifecycle.commit_candidate`, so each is proved
zero-delta (a world with no land unit has an empty, valid snapshot). A malformed saved day is refused
before its boundary is read; a transition that changes nothing (a failed round settlement) returns
`blocked` on its frozen pending. The result carries one detached candidate; the source never changes, a saved candidate
resumes exactly and a completed one is a no-op. Part B (closing the frozen day into the ordinary
remaining phases, arrival and garrison at actual body positions, and the march staging the CF04c
visual review asks for: whole strides, front-first column order, facing written to the heading) and
the Game/TickEngine bridges are not here; nothing in ordinary dispatch calls the driver.
