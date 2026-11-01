# CF06 candidate damage contract

Date: 2026-11-01. Step `CF06-CONTRACT`; implementation
`01a196f8-6afa-7eb1-ac45-08f05a8e6658`; dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`. Unique document Review is assigned by
that dispatcher before handoff. This is a document-only interface and scope
contract, not a product implementation, registration or acceptance result.

## Authority and admitted predecessors

Frozen source is `35c7db3d24112fea5f9d83f55567987b2b6fad12`, accepted #209.
Read the [CF05 contract](cf05-battle-contract.md), the accepted
[#208 boundary](candidate-engine-dag-boundary.md), the
[original plan CF06](../../superpowers/plans/2026-10-25-cluster-formations.md)
and [approved spec §3, §7–9](../../superpowers/specs/2026-10-25-cluster-formations-design.md)
together. The original assertions and all twelve gates remain binding.
#209 supplies a physical-contact and round-ready **contract**, not those product
APIs on main. CF06 product starts only after actual accepted B-ROUND and every
required B output, including actual accepted LOCO-MARCH and its raw/save,
placement, timeline closure, lawful ownership/lifecycle and budget predecessors.
Neither unmerged #206/#207 nor render/art completion is substituted for those
engine prerequisites. This document does not create or replace any CF05 step.

Inspected current consumers are `BattleSystem.unit_strength`, `side_power`,
`combat_context`, `_fight`, `apply_round`, `BattleRanged.counts`,
`active_permille`, `incoming_permille`, `BattleGroups.engaged_counts`,
`engaged_permille`, `BattleMerge._ranged_contact`, `MilitaryRoster.transfer_units`
and `UnitBodies.reconcile_candidate`. The military groups, ranged, charge and
cluster-formations guides explain their current limits. Product guides change
only when the corresponding implementation lands.

Two concrete constraints must remain visible:

- `engaged_permille` currently gives noncontact personnel
  `battle_reserve_permille`, and the ranged incoming helper gives non-ranged
  personnel full threat. Neither is an eligible candidate damage fallback.
  `BattleStrength.combine` clamps categories; a zero contact multiplier alone
  must never be the only guarantee of zero outgoing damage.
- Production centre reach is `battle_ranged_reach_m=400`; accepted physical
  radii are 749–932 metres. Two nonoverlapping current bodies cannot have their
  centres within 400 metres. Thus the unchanged reach currently yields zero
  actual direct fire in a valid production-radius world. This contract preserves
  that failure explicitly. It does not add radii to reach, shrink bodies, move
  muzzle origins or tune a CSV. An approved resolution in the original owning
  pair is necessary before claiming real ranged acceptance/activation. Synthetic
  geometry tests cannot resolve this production incompatibility.

## Proposed read-only eligibility interfaces

These signatures are future explicit candidate entrances. Ordinary callers and
legacy pending saves remain unchanged until the final all-writer activation.
All new classes are typed engine-pure `RefCounted`; planning mutates no source,
RNG, task, terrain cache, personnel, supplies or body row.

```gdscript
BattleGroups.melee_counts(repo: DataRepository, state: GameState,
        battle: Dictionary, unit: String, enemies: Array) -> Dictionary
BodyBattleContact.exposure_candidate(repo: DataRepository, source: GameState,
        battle_id: int, unit: String, enemies: Array,
        boundary: Dictionary) -> Dictionary
BattleRanged.counts_candidate(repo: DataRepository, source: GameState,
        battle_id: int, unit: String, target: String,
        opposing_battle_id: int, boundary: Dictionary) -> Dictionary
BodyBattleRounds.plan_candidate(repo: DataRepository, source: GameState,
        battle_id: int, boundary: Dictionary) -> Dictionary
BodyBattleRounds.commit_candidate(repo: DataRepository, source: GameState,
        proposed: Dictionary, boundary: Dictionary) -> Dictionary
```

`melee_counts` returns exactly `{engaged:int,fit:int,reason:String}`. It adapts
CF05 `BodyBattleContact.query_candidate` using the actual saved boundary; invalid
or absent boundary is rejection, never legacy front/reserve fallback. Upstream
candidate admission must succeed before this three-field adapter is consumed;
errors from the full query cannot be converted to a legitimate zero result.
No new adapter error field changes the original CF06 signature.

`exposure_candidate` has exactly CF05's closed query result and sorted melee
pair schema. Its `engaged` counts physically contactable own personnel, once
per identity, independently of that unit's outgoing attack permission. It checks
the same admitted whole world, owner, positive counts, terrain segment and
surface-gap inequality. It is defensive evidence, not permission to attack.
To inflict damage on unit B, A must additionally have an eligible outgoing
A→B pair and actual lawful action. B being exposed does not authorize B→A.
Filtering a protected pair cannot erase B's exposure to a different lawful C.
Malformed membership/owner/duplicate enemies errors; legal no contact is zero.

Surface contact remains exactly CF05:
`(rA+rB)^2 <= d² <= (rA+rB+battle_group_contact_m)^2`.
Deduplicate own `(unit,slot)` across targets; a partial final row counts its
actual personnel. No `role==front` requirement and no inferred missing rows.
Physical defensive exposure may support existing defence/organization without
creating outgoing personnel. Future CF21 conditional support is not a damage
allowance and CF06 introduces no permanent formation factor.

`counts_candidate` returns exactly
`{status,reason,error,battle_id,unit,fit,firing,melee,pairs}`; status is
`complete` or `error`. Error has nonempty error, zero counts and empty pairs;
complete has empty error and nonempty readable reason. IDs are int arguments
resolved to canonical live fields before validation; `opposing_battle_id=0`
means the same field, `target=""` means all admitted opposing members.
Pairs are exactly `{unit:String,slot:int,target_unit:String,target_slot:int,
count:int,target_count:int,kind:"fire"|"melee",reason:String}`, sorted by
unit/slot/target_unit/target_slot/kind, unique. Counts are unions of identities,
not sums across pairs. Firing and melee sets are disjoint; local close defence
uses physical surface contact, never front labels or 100-metre centre contact.
`fit` is real fit agreeing with owner rows, not equipment capacity or ten models.

The query retains original task/action/reserve/close-defence rules, received
designated target, local sight (`player_sight_km`/`ai_sight_km`), bounded pursuit,
actual saved facing and cone. A received retreat stays retreat; reserve status
cannot manufacture fire. Current bilateral party protections, lawful actions,
withdrawal and capture apply per ordered source/target pair, from **both fields**
and retained absorbed sources. A↔B terms never become A↔C terms. Local defence
against an actual attacker is not unlimited pursuit or a hidden sight bypass.

Fire uses unchanged saved **centre** reach, inclusive squared distance, original
positive forward dot and inclusive cross/dot cone threshold. The old close
centre exclusion remains; physical contact also suppresses firing in favour of
close defence. Every segment is checked against actual terrain/water/closed
cells; no indirect trajectory or overhead allowance. Positive-count friends
from both fields, including the shooter's own front, horse and cannon bodies,
block using their measured physical circles. Only the shooter identity is
excluded, never every body at the same point. Tangency to an interior open
segment blocks; an endpoint-only tangent does not, while a disc intersecting
the segment near an endpoint does. Checked integer/local arithmetic must reject
overflow, fractions and ambiguous tangency rather than narrow to float32.
No new smaller `battle_ranged_block_radius_m` substitute certifies body clearance.

The ordinary `counts/clear_shot` signatures remain available to legacy callers.
Candidate implementation may share geometry internals but cannot weaken their
existing tests or admit missing candidate geometry through legacy adapters.
Cross-field discovery/merge consumes positive **firing**, with original attacking
ranged-equipped source action; mere reach, melee count or an error is insufficient.
Until the accepted query is wired, CF05 retains `direct_fire_dependency`.

## Existing arithmetic and target-scoped damage

No new outcome table, combat variance, wounded share, charge/flank multiplier,
fatigue, range compensation or tuning decision is authorized. Equipment,
quality, training, morale, discipline, supply, terrain/height/camp, order and
existing event factors retain their sources and rounding order. Duplicate
source IDs remain an error. Existing category order is training, morale,
discipline, supply, formation_terrain, contact, action; category deviations add
before one clamp and integer truncation per category.

Candidate outgoing melee uses only eligible engaged personnel; unengaged
personnel contribute exactly zero. The original fit=1000/engaged=100 assertion
means the personnel input to the melee equipment pipeline is 100, not 1000 with
900 reserve personnel. For mixed equipment, retain `BattleRanged.share`'s
crew-weighted share and existing arm-development/quality arithmetic; separate
eligible melee and direct-fire personnel before the factor clamps. A component
with zero eligible personnel returns zero power before clamps. Defence and
organization retain their own personnel/evidence path. Do not replace defence
with outgoing attack power or make exposed rearranging bodies invulnerable.
Exact mixed-arm allocation and partial-row rounding are defined in
[CF06 physical power §1–2](cf06-power-contract.md): proportional crew numerators,
disjoint physical melee/fire unions, one existing rounding chain per arm, then
quality/category factors once. This document-only prerequisite requires its
unique Review's accepted merge before D-POWER registration; no product owner or
implementation is created by the clarification.

For each specific receiving unit, incoming exposure derives only from opponents
that can actually lawfully damage that target: melee contact or actual firing.
A reaching B does not expose remote C. Replace the non-ranged full-threat
fallback on the candidate path; retain the existing incoming context order:
withdrawal/pursuit or ranged/shock/melee classification, existing context scale,
actual target exposure, then authored event exposure. Existing shock counts only
actual mounted impacting personnel against that opponent, once; earned charge
is consumed only after complete settlement. Existing side/rear sources cannot
also become a second cluster bonus. The exact simultaneous melee/fire weighting
is specified in
[CF06 physical power §3](cf06-power-contract.md): target-specific lawful source
unions, existing crew-weighted ranged share and fit weighting, zero for no
actual threat, then existing context/event order. The old ranged-only helper
does not already implement this candidate rule.

Unchanged downstream arithmetic is explicit:

- `odds = trunc(1000*A/(A+D))`, or 500 when both powers are zero.
- `eff = clamp(odds + trunc((roll-500)*battle_variance_permille/1000),0,1000)`;
  one engine `randi_range(0,999)`, existing half-open tier intervals (1000 last).
- Each unit's loss rate is `trunc(base tier loss * target context /1000)`;
  freeze `tier.unit_loss_permille` and `tier.unit_morale_permille` for **all**
  participants so no old conditional fallback can damage a remote melee unit.
- Group by identical loss rate before personnel allocation, retaining stable
  sorted unit order. Lost=`trunc(total fit*rate/1000)`; wounded=
  `trunc(lost*wounded_share/1000)`, dead=lost-wounded. Largest remainder allocates
  losses by fit, then wounds by allocated losses, ties by stable unit order.
- Negative morale uses frozen unit exposure then existing stance, received order
  and inspiration decay in their existing integer order; clamp final morale to
  0..100. Positive morale retains existing semantics. Freeze its resulting
  effect as well as the inputs so retries cannot re-read changed stance.
- Additional attack food is existing `ceil(day_bite*extra_supply_permille/1000)`
  once per actual attacking unit. Keep side/task de-duplication, reserve base
  meal and legal affordability. No cost per row, contact, failed commit or retry.

## Round plan, raw payload and atomic publication

Use CF05 transaction result exactly:
`{status:String,reason:String,error:String,candidate:GameState,plan:Dictionary}`.
Statuses complete/deferred/blocked/error retain CF05 meanings. Plan success is
the specified exception carrying a detached candidate with frozen pending and
one advanced RNG state. It is not a source mutation or personnel settlement.
Malformed inputs error before valid-stage deferral; error/deferred carry null
candidate and empty plan. A failed personnel commit returns blocked with the
unchanged detached **pending** candidate and identical plan, nonempty reason,
empty error; the caller retains this retryable state, never the pre-draw source.

Boundary is CF05's exact battle boundary, stage round, current queue entry,
acknowledged decision, unprocessed unit set and matching closed motion cursor.
Require the exact immutable `body_round` token, contact digest, actions, basis
and current outer endpoint proof. No motion/refresh, ordinary `_fight`, action
reselection, body reallocation or law repair may run inside damage admission.
Legacy pending without body provenance defers on its original safe route.

Proposed plan is closed:

```text
{version:1,battle_id:String,boundary:Dictionary,
 basis:{source:String},body_round_receipt:String,pending:Dictionary,
 effects:{personnel_orders:Array,unit_results:Dictionary,
          charge_units:Array,family_event_ids:Array}}
```

`source` binds pre-draw full save, request/boundary and CF05 outer context K.
`body_round_receipt=H(exact canonical body_round)`.
`pending` has exactly the existing keys
`day,round,att,def,tier,att_power,def_power,odds,roll,eff,contexts,reason,costs,unit_actions`
plus `body_round_receipt`. Tier/context/action/cost extensions retain existing
schemas; no generic patch payload. Effects are the exact existing grouped
personnel orders (`unit_code,from,to,count`), per-unit result records
(`dead,wounded,morale,reason`), sorted unique actual charge unit codes and stable
family-loss event IDs. Derive them through the existing personnel planner;
no second casualty algorithm or new identity namespace. Bind every side effect
needed by settlement, including zero-loss morale. Product registration must
name the existing family event-ID construction verbatim after accepted B-END;
it cannot infer that API from a stale contract source.

Persist the full frozen plan at `battle.body_round_plan`, exactly
`{version:"1",receipt:String,plan:Dictionary}`, receipt=H(the whole plan).
It is present together with pending_round and absent after settlement; no
placeholder/default is created. The plan records pre-draw source provenance,
not a self-referential hash of the save containing itself. CF05's body_round
basis projection must explicitly exclude this new wrapper along with
body_round/pending_round; the outer full endpoint projection retains all three.
This is a required explicit candidate admission extension, never an inferred
permission to exclude arbitrary saved fields.

Extend only the explicit candidate outer request union with exactly
`{kind:"round_pending"|"round_settle",battle_id:String,plan_receipt:String}`.
Both require stage round/current field and the CF06 independently validated
plan digest. They use CF05's existing outer plan shape, empty motion and the
ready contacts. The outer source basis binds the actual prepublication save;
its request references the already computed CF06 plan digest, avoiding a hash
cycle. Ordinary request admission does not accept either tag. D-PENDING owns
the first extension; D-SETTLE owns the second and plan-wrapper removal.

Saved pending is the exact plan.pending, not its decoded approximation. Existing
raw-save seam must preserve the plan/receipt and candidate envelope in both
GameState provenance branches before legacy `_whole/_decode_values`. Unknown or
missing keys/versions, bool integers, fractions, nonfinite/out-of-safe-range
numbers, malformed decimal cursor strings and legacy encoded numeric strings
remain invalid. SHA256 canonical hashing and integer/decimal controls use CF05
rules. Existing save versions remain 7/6; absence alone means no candidate data.

Durable full-outcome record uses the existing `military_events` dictionary at
`bodyround:<canonical battle id>:<absolute day>:<round>:settlement`, exactly
`{request:{kind:"body_round_settlement",plan:Dictionary},
  result:{pending:Dictionary,effects:Dictionary,personnel_event_id:String,
          round_event:Dictionary}}`.
Existing personnel event remains `battle:<id>:round:<n>` and its grouped transfer
suffix `:personnel`; no renaming or duplicate population write. The full receipt
retains plan.pending/effects even with no personnel orders and zero casualties.
The round event uses the existing authored round-event shape, with actual
contexts/results/costs/actions. Existing family/custody/report outcomes remain
inside the detached atomic settlement; a failure discards all intermediate work.
This record is a receipt, not a second body store or authoritative pose snapshot.

First planning success publishes pending, frozen effects/plan and one draw
**together** in a private candidate, sealing the CF05 outer sequence/receipt/
endpoint result by the same acyclic scheme. It must not leave the old endpoint
hash on changed RNG/pending. The plan has no result hash; outer endpoint hashing
clears only its own result field, retains receipt and all actual saved effects.
Pending admission verifies the saved whole plan digest, endpoint and immutable
body_round, not by rerunning RNG or recomputing from post-draw source.
Exact duplicate planning returns detached frozen pending unchanged. Tampered
pending/actions/costs/context/charge/body_round/RNG/terrain/config errors.

Commit independently validates that frozen plan against its admitted pending
endpoint, then works on a clone. Apply grouped personnel once, exact body count
reconciliation with stable survivor slot/home/pose/path/facing and high-water
counter, existing family/custody effects, frozen morale/costs and earned impact.
Do not call frozen-deferred `reconcile_candidate` directly or clear day controls
as a shortcut: D-RECONCILE below supplies the explicit round settlement seam.
Retire only necessary tail identities; 901→900 removes the last row, never
relocates nine survivors. Zero fit retains a valid empty owner until CF05's
transfer-before-delete lifecycle. Record full receipt and ordinary round event,
clear body_round/pending_round, mark processed battle/units and advance the
mirrored CF05 queue/index atomically, then seal the new outer endpoint.
Exit/rout/end requests go through accepted B lifecycle at the legal advance
boundary, never ordinary anchor movement or owner deletion inside damage.

Failure at any personnel, reconciliation, family or custody check returns the
original frozen pending clone: no partial morale, supplies, slot retirement,
impact consumption, event append or cursor advance. Direct/JSON retries retain
that one draw and exact payload. Settled retry requires exact full-plan receipt
and endpoint proof and returns detached no-op, even after field removal via the
accepted outer lifecycle. Changed/older/conflicting plans reject. A later
legitimate transition uses outer sequence authority; an old retry cannot roll
back current state. Issuing a command cannot replace frozen actions; it applies
to a later unprocessed round.

## Required hand-computed and adversarial evidence

These are future tests, not results of this document PR. Use SuiteData copies;
no DataRepository.load_all, shared fixture rewrite or weakened old assertion.

1. Pure melee fit 1000: one 100-person row at lawful surface contact gives
   engaged=100 and eligible personnel=100; nine remote rows contribute zero.
   No contacts gives outgoing zero under even a positive category floor, while
   incoming lawful contact still permits casualties/defence. One-person final
   row contributes 1 once against two targets. A→B protected, C→B lawful tests
   outgoing/defensive separation and bilateral nonparty scope.
2. With two infantry radii 927 and contact allowance 100, centre gaps 1854 and
   1954 qualify, 1955 does not; 1853 is invalid overlap, not stronger contact.
   Wall/water segment and raw overflow reject without mutation.
3. Pure geometry reach400: clear forward centres399 and400 qualify,401 does
   not; cone edge included, one metre beyond excluded; facing backwards fails.
   These small geometry fixtures are not admitted production body worlds.
   Actual radii at nonoverlapping positions must yield zero fire at reach400.
4. Interior tangent friendly horse/cannon blocks; move its disc one metre clear
   and an actual legal gap permits fire in a geometry fixture. Own front and
   both-field allies block. Shooter-only exclusion, endpoint tangent, terrain,
   pursuit bounds, sight, designated target, retreat/reserve and protected target
   have negative cases. Moving a target from400 to401 stops firing immediately.
5. Unchanged arithmetic: A100,D300 gives odds250; roll600,variance300 gives
   eff280. Tier rate125 × exposure400 /1000 gives50. Group fit[100,300] at
   rate50 loses20 allocated[5,15]; wounded share600 gives12 wounds allocated
   [3,9], dead[2,6]. Zero rate loses0 yet morale50 plus delta-5 becomes45 once.
   Mixed-equipment partial-row, guard/rounding and simultaneous incoming
   expected cases are [physical power P1–P7](cf06-power-contract.md); these
   additive future tests do not count as implemented or passing here.
6. Pending save immediately before/after draw and at failed commit; direct/JSON
   retry yields identical pending bytes/canonical hash, RNG, actions, contexts,
   costs, charge and body_round receipt. Inject a personnel-origin failure and
   later reconciliation/custody failure; no partial writes. Repair only the
   external failing prerequisite at an admitted boundary, never rewrite frozen
   payload. Changed relevant basis requires rejection, not an implicit repair.
7. Loss901→900,1→0; sums equal ledger, survivors preserve identities/positions,
   retired slots never reused, regroup/capture/end maintains sole owner. Duplicate
   success and zero-loss morale retry yield one round event, one cost, one impact,
   one family result and exactly one queue advancement. Tamper every raw control,
   full receipt, frozen effect and outer endpoint; reject without live/save change.

## Proposed small product DAG and literal ownership

These are unregistered proposals, not dispatches. Every step waits accepted
CF06-CONTRACT, actual accepted B-ROUND and all required B predecessors. Shared
files/categories force serial work in the order below. Each owns one independently
rejectable result; no step activates ordinary daily damage. Any extra path must
be registered before editing. Every new `.gd` below also owns the explicitly
listed `.gd.uid`; no implicit fixture or plan ownership.

- **D-QUERY**, after B-ROUND+B-CONTACT: physical defensive exposure and melee
  adapter only. Own `scripts/engine/body_battle_contact.gd`,
  `scripts/engine/battle_groups.gd`, `scripts/engine/guide/battle_groups.md`,
  `tests/engine/test_physical_damage.gd`,
  `tests/engine/test_physical_damage.gd.uid`, `tests/categories.json`.
  Acceptance is cases1–2; reject if outgoing permission erases defensive exposure.
- **D-FIRE**, after D-QUERY+B-MERGE: actual direct-fire query and cross-field
  discovery/merge dependency completion only. Own `scripts/engine/battle_ranged.gd`,
  `scripts/engine/body_battle.gd`, `scripts/engine/guide/battle_ranged.md`,
  `tests/engine/test_body_direct_fire.gd`,
  `tests/engine/test_body_direct_fire.gd.uid`, `tests/categories.json`.
  Acceptance is cases3–4 plus both-field party symmetry; preserve the explicit
  production reach blocker. No change to data/battle/balance.csv is authorized.
- **D-POWER**, after D-FIRE and accepted unique-Review merge of
  [CF06-POWER-CONTRACT](cf06-power-contract.md): separate outgoing personnel
  from defence,
  exact target contexts and frozen rate derivation only. Own
  `scripts/engine/battle_strength.gd`, `scripts/engine/battle_system.gd`,
  `scripts/engine/battle_ranged.gd`, `scripts/engine/guide/battle_groups.md`,
  `scripts/engine/guide/battle_ranged.md`,
  `tests/engine/test_body_damage_strength.gd`,
  `tests/engine/test_body_damage_strength.gd.uid`, `tests/categories.json`.
  Acceptance is cases1,5 and physical power P1–P7, zero before clamp,
  no reserve output and no duplicate flank/charge factors.
- **D-RECONCILE**, after D-POWER+B-BOUNDARY+B-END: explicit validated frozen-round
  body loss reconciliation only. Proposed API
  `UnitBodies.reconcile_round_candidate(repo: DataRepository, source: GameState,
  proposed: Dictionary, boundary: Dictionary) -> Dictionary` retains UnitBodies'
  five-field result shape, verifies frozen round provenance/personnel effects,
  and produces a private complete world without closing its caller's round.
  Own `scripts/engine/unit_bodies.gd`,
  `scripts/engine/guide/cluster_formations.md`,
  `tests/engine/test_body_round_reconcile.gd`,
  `tests/engine/test_body_round_reconcile.gd.uid`, `tests/categories.json`.
  Acceptance is case7 counts/identity plus refusal of unrelated staged changes;
  no round driver or arbitrary frozen-state bypass.
- **D-PENDING**, after D-RECONCILE and actual B raw-save seam: implement first
  detached pending planning, full raw envelope/receipt admission and RNG freeze;
  no personnel commit. Own `scripts/engine/body_battle_rounds.gd`,
  `scripts/engine/body_battle_rounds.gd.uid`, `scripts/engine/game_state.gd`,
  `scripts/engine/unit_bodies.gd`, `scripts/engine/body_battle.gd`,
  `scripts/engine/guide/cluster_formations.md`,
  `tests/engine/test_body_round_pending.gd`,
  `tests/engine/test_body_round_pending.gd.uid`, `tests/categories.json`.
  Acceptance is case6 draw/raw replay, exact plan/effects, outer endpoint closure.
- **D-SETTLE**, after D-PENDING: complete atomic personnel/cost/body/outcome
  settlement and full-receipt replay only. Own
  `scripts/engine/body_battle_rounds.gd`, `scripts/engine/battle_system.gd`,
  `scripts/engine/body_battle.gd`, `scripts/engine/guide/battle_groups.md`,
  `tests/engine/test_body_round_settlement.gd`,
  `tests/engine/test_body_round_settlement.gd.uid`, `tests/categories.json`.
  Acceptance is cases5–7 including failed late side effect rollback and zero-loss
  morale, stable ordinary event IDs, aliases, full receipt and processed units.
- **D-DRIVER**, after D-SETTLE+D-FIRE: wire one candidate round control transition
  into the accepted isolated-day consumer only. Own
  `scripts/engine/body_battle.gd`, `scripts/engine/tick_engine.gd`,
  `scripts/engine/day_resolution.gd`, `scripts/engine/guide/body_marches.md`,
  `tests/engine/test_body_damage_driver.gd`,
  `tests/engine/test_body_damage_driver.gd.uid`, `tests/categories.json`.
  Acceptance is exact round/advance queue prefix, no second daily round after
  merge/reinforcement and direct/JSON stage retry. No next-day shortcut.

DAG is B-ROUND → D-QUERY → D-FIRE → D-POWER → D-RECONCILE → D-PENDING →
D-SETTLE → D-DRIVER. Required B outputs above are already ancestors of B-ROUND;
no B step depends back on this DAG. The separately registered CF05 real daily
continuation predecessor follows accepted CF06 and the other actual daily
writers. Foundation never depends on activation. API reconciliation against
actual accepted B outputs precedes each registration; unresolved decisions stop
the affected step, not the entire unrelated contract branch.

## Verification and final activation gates retained

This document PR runs pure document/link/scope checks and current-HEAD required
CI with its unique independent Review. No Godot, Blender, model art, scene,
CSV or production caller changes. It proves no gameplay or visual acceptance.
Future products retain targeted `test_group_contact_strength.gd`,
`test_ranged_fire_geometry.gd`, `test_ranged_contact_merge.gd`,
`test_battle_conservation.gd`, relevant charge/formation/context/atomic personnel,
save/determinism checks and the affected selector/runtime gates on final inputs.
Preserve existing assertions; additive candidate tests are not replacements.

All spec §9 gates1–12 remain: ten bodies and loss boundaries; physical whole-path
clearance; selection/qualification; real shared and local speeds; delivered
commands; vulnerable assembly; reinforcement/single ownership; every formation's
normal/blocked/lost-member cases; actual melee/fire and source deduplication;
save/cost determinism; reproducible fair combat comparisons; native 3D windows.
The inherited **55 fail and 6 risky/pending** remain unresolved until individually
classified and fixed, without exclusions, reduced assertions or inherited PASS.
Keep real production-radius road contact and defeat continuation, fresh-campaign
roundtrip, military reorganization, personnel/slot/cost conservation and all
required current-HEAD CI. CF01's finite17 samples and artillery infantry
substitute do not certify installed full animation or performance.

Only final ALL-writer activation may switch production motion/damage/render
ownership together, after every actual predecessor, raw-save admission, lawful
real contact/fire resolution, next-day/month-end continuation, art certificates,
real-window visual-review and performance acceptance passes on final inputs.
Document acceptance, synthetic numerical checks and candidate fixtures never
count as any of those product or visual passes.
