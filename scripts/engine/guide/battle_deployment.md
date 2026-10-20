## Formations and per-clause agreements

`BattleRules.freeze` snapshots each side's received laws once at contact, using the first unit in sorted code order as the saved representative. `LawSystem.received` reads the newer town/unit version; foreign columns carry independent `received_laws`, seeded from declared defaults, never crown decrees. Legacy columns without that map read defaults. Existing battles without a snapshot acquire one at the first resumed day. Semantic proposals compare all conditions, scopes and deadlines independently, with both proposals and a reason preserved on rejection. The saved `parley` remains bound to the battle through new laws, commanders, reinforcements and JSON saves. `legal_actions(…, unit, target)` applies live own laws plus shared obligations scoped per agreement: `parley.parties` (`{att, def}`: the sides at contact, a joining reinforcement appended, an old save defaulting to the current members) names who an agreement binds; the battle's own parley and every `sources[*].parley` count; an agreement applies to a unit that is its party when the `target` is a party on its other side (no target: the object cannot be confirmed, so the possibly breaching action is held). A merge never adds one battle's units to the other's parties, so a new opponent from another source gets no bilateral treatment; `BattleTaskSystem` passes the task's target; protected withdrawal/ceasefire overrides pursuit, and accepting surrender prohibits a red refusal flag without prohibiting one's own surrender. There is no king renegotiation action. `parley_clauses.csv` maps each clause to its law; prisoner treatment, wounded evacuation, safe withdrawal, permitted tactics and own surrender are separate military policies.

`BattleFormation` owns deployment independently of stance/action. `formations.csv` declares four shapes, frontage, terrain/arm/morale/training suitability, centre requirements, factors and reforming costs. A diamond's positive protection requires an actual nearby king or wounded personnel; absent a centre its penalties remain. `BATTLE_FORMATION` is a paid typed order through `ActionSystem` and the existing local/courier path; delivery revalidates membership and suitability, uses a separate side order id and saved within-courier sequence, and expires with the battle. Same-target requests do nothing; retargeting preserves the longest disorder deadline. Saved current/previous/target, progress and last-progress day advance once per completed day using fit-personnel discipline. During reforming only current deployment plus disorder applies; each factor has one source and reason; combat merges the formation/terrain category before one integer truncation. WAR ROOM and map share its shape; narrow lines fold into extra ranks instead of overlapping figures. Figure-count tiers remain `army_formations.csv`'s responsibility.

`BattleFormation.request/refusal/context/effects` accept an optional unit for internal
received deployment integration. A valid first unit request copies its side's full
current deployment into saved `battle.unit_formations`; later side defaults never
rewrite it. Duplicate targets preserve progress/exposure; retargeting retains the
longest disorder deadline. Unit overrides progress once per day in sorted code order
using only their recipient's fit discipline; departed/incapacitated/captured recipients
do not progress. Suitability and factors use that recipient's terrain, arms and
personnel. Unit strength and shape lookup read the same current override and
recipient terrain context, including the map's narrow-line frontage; legacy
battles and unassigned units retain side deployment and side context. This internal
API does not issue a warrant or pay costs. Internal task receipt uses this API;
public formation parameters still require integration before player use.

## Unit task warrants

`BattleTaskSystem.issue_task/deliver_task` are internal warrant operations, with
dispatch, payment and physical arrival owned by their caller. They do not move
units or advance time. `GameState.unit_tasks` is the sole unit-task ledger:
per-unit pending orders, current ID, issued/received sequence and terminal
receipts. A valid delivery replaces the current task; a late lower sequence is
superseded within its authority. A separate received-player high-water mark
prevents a general's later deployment from making the only in-flight royal task
stale. The overall received high-water mark never decreases. Exact request replays preserve the receipt; conflicting IDs are
refused across all units. Requests and returned snapshots are independent copies.
Every transition retains world day, source and reason. Old saves start empty.

`behaviors.csv` lists the seven primary tasks and their legal battle actions;
formation is an independent field referencing `formations.csv`. Receipt checks
live unit/target membership, current received law and battlefield obligations.
Unit-scoped law checks affect only the receiving unit; army-wide warrants retain
their intersection across the side. The current eligible battlefield general
may task unassigned units but cannot replace a delivered player task, even when
his pending warrant has a newer sequence. A local commander cannot issue a new
primary task. Risk and formation preparation do not veto lawful receipt;
routing and incapacity remain facts that prevent resuming a line.
Until contact-plan delivery is integrated, pursuit requires an explicit player
task; a general's deployment warrant alone cannot authorize it.

`BATTLE_TASK` is the paid player dispatch path for a single battlefield unit.
It accepts `request_id`, `regiment`, `battle_id`, `task` and optional
`target_unit` and `formation`; source/issuer are not action parameters. The
OrderCosts filing charge applies once per new request, plus a courier fee only
for a new courier. Pending co-carried tasks pay independent filing charges.
Reserved reward gold is unavailable. Exact retries return the saved original
outcome before costs, history or current eligibility; conflicting reuse fails.
Local king command range delivers immediately through CourierSystem; remote
warrants remain pending until arrival. Delivery checks recipient identity,
current realm control, membership and law. Lost/expired couriers invalidate
pending tasks with a reason without refunding spent fees. A formation rides in
the same warrant (below): no extra filing or courier fee, refused before any
mutation when unknown or unsuitable, and reuse of a request id with another
formation fails.

`BATTLE_TASK_CANCEL` accepts only `request_id`, `regiment` and `battle_id`,
pays its own filing row and uses the same local/courier path. Its internal
`task=cancel` warrant is a control record, never a behavior or current task.
Until receipt the old task remains current. Receipt rechecks live crown control
and battlefield membership, marks the old task cancelled with a reason, clears
the current ID and advances both sequence barriers. A cancellation with no
current task still establishes that barrier; a newer assignment can follow it.
Cancellation does not execute a combat action, so ceasefire and routing do not
forbid it. Pending cancellations lapse with their courier. Exact retries return
the saved outcome without mutation, including after JSON; request IDs cannot be
reused across assignment and cancellation actions. The player issues both from
the WAR ROOM's docked folio, which reads `BattlePresentation.task_view` (status)
and sends exactly `task_quote`'s params (`scripts/war_room/CLAUDE.md`).

Internal task warrants with a nonempty formation validate the recipient against
`BattleFormation.refusal` at issue and receipt, including its CSV suitability.
After law, authority and sequence validation, receipt starts that unit's existing
reforming state atomically with task replacement. Pending, failed, stale and
repeated receipts cannot reform a unit. A new task with the same formation keeps
progress; a different explicit formation retargets with the longest disorder
deadline. An empty formation or task cancellation leaves the received physical
deployment and its progress/disorder intact; neither refunds preparation costs.
The side default and other units are unaffected. These internal operations do
not add a second filing charge or courier fee.

## Delivered unit attack and hold

`BattleTaskSystem.combat_action` resolves only received tasks for this battle:
advance/flank/charge reuse attack, defend/guard_flank reuse hold. Charge retains
its own live legality check; there is no positional/flanking bonus. Pending,
replaced and cancelled warrants do not execute. Unassigned units retain their existing side action; actual withdrawal/rout wins. Live unit
law, shared terms, crown control and designated enemy availability constrain
execution. A barred or depleted task holds without altering its saved receipt.

`BattleSystem.unit_action` feeds each unit's existing strength and morale
factors, engagement, attack context and extra supply consumption. Shock counts
only mounted personnel actually attacking; task attack alone grants no pursuit. Explicit
unit tasks are excluded from the legacy side-wide supply veto; each attacking
task pays its own existing extra bite, once alongside the daily personnel
commit. A successful task attack clears its recipient’s reserve flag; a failed
round preserves it until the saved round commits. Normal meals/equipment retain their existing writers. The saved
`pending_round.unit_actions` freezes actual actions and reasons with the loss
plan, RNG draw and costs; failed personnel writes and JSON retries reuse it. Legacy pending plans without
unit actions retain their side effects until that round completes.
Cancellation/replacement changes the next unprocessed round only on receipt.

## Delivered unit pursuit

A received royal pursuit task reuses attack strength, engagement and extra supply
only while an available opposing unit is withdrawing (side retreat or actual
unit withdrawal). A designated target must itself be available and withdrawing;
an unspecified task may pursue available withdrawing opponents. Without one it
holds, retaining its receipt. Live legality, control, capacity and carried supply
checks still apply. A normal unit attack never supplies pursuit authorization.
Legacy side attack retains its existing lawful pursuit context for unassigned
attacking units; a unit task overrides that recipient's side action.

Actual lawful attacking pursuers determine each withdrawing enemy's existing
pursuit/withdrawal context. A targeted task does not increase another withdrawing
unit's casualty rate. Withdrawing sides save per-unit rates even when all members
withdraw, using the existing CSV scales and grouped integer casualty writer.
The frozen action retains its pursuit target with the pending loss plan; failed
commits, cancellation after planning and JSON retries do not change that plan,
repeat its RNG draw or charge attack costs twice. Pursuit movement and the lost-sight
search are the target tracking below.

**Pursuit bounds.** A pursuit task may carry `max_route_m` (whole metres, 0 = none)
and `region` (province codes joined by `|`, sorted, de-duplicated, "" = none); on any
other task they are refused. The received record saves `pursuit = {start_x_m,
start_y_m, route_m}` at delivery; a same-meaning reissue (battle, target, bounds)
keeps it, any other task starts fresh. `ArmySystem.march_day_saved` credits the
metres a substep really walked (detours included) through
`BattleTaskSystem.credit_pursuit`, which checks route metres and the unit's centre
province (also at 0 metres). The first bound reached sets status `bounded` with its
reason, halts a marching unit where it stands (today's saved walk included) and
leaves `current_id` on it: `combat_action` then answers `hold` for that battle, so it
defends but never advances or starts a withdrawal; only a new received task replaces it.

**Target tracking and the limited search.** A crown unit in no battle whose current
received task is a `flank` or a pursuit with a `target_unit` marches at the target as
its OWN sight knows it (`BattleTaskSystem.track_day`, once a day at the top of
`MARCH_ORDERS_AND_ROUTE_SETUP`, idempotent by `track.done_day`): the target with men
under arms is seen within `player_sight_km` of the recipient's position (inclusive,
squared whole metres; never `GameState.sightings`, crown-wide sight or a scouting
sector). The record saves `track = {x_m, y_m, day, phase, search_until_day, done_day}`
(absent = none; an old save has none). Seen: the snapshot is the target's true point,
phase `follow`, and the unit is aimed there (a marching unit is re-aimed in place by
`ArmySystem.aim_entry`, so camp packing is not restarted; a standing one gets
`set_march_m`). Not seen in `follow`: it marches at the saved point and, standing on it,
turns to `search` until `today + battle_search_days`, holding there. In `search` a
sighting within `battle_search_range_m` of the saved point resumes `follow`; a farther
one changes nothing; past `search_until_day` the record becomes `search_failed` and the
unit halts (`BattleSystem._halt`). `search_failed`, `bounded`, `replaced` and
`cancelled` are never tracked again, and a later sighting revives nothing. Contact
puts the unit in a battle, which pauses tracking; the task stays received.

## Delivered unit retreat

A received retreat resolves through `combat_action` and the existing `_exits`
withdrawal path for that recipient only. Pending tasks are inert; current law,
control, membership and incapacity checks still apply before execution. A frozen
pending round retains its saved actions until commit, including legacy plans.
`_start_retreat` keeps reachable held-town routing, full camp packing deadlines,
contact membership and its one-time morale/store losses. A failed route leaves
the unit exposed and retries on the next unresolved day; actual separation alone
removes it. Cancelling or replacing the warrant before execution prevents its
start; afterwards it changes only the task ledger, never reverses the physical
withdrawal or grants immunity. Existing side-wide withdrawal/rout takes priority.

Mixed withdrawing/remaining sides save effective casualty rates per unit in the
pending tier. Rates use the existing contexts and CSV scales; equal rates share
one whole-number loss pool with the existing largest-remainder apportionment.
Protected withdrawal applies only to withdrawing members; remaining allies retain
their own combat context and event exposure. Each withdrawing unit checks every
opponent against all carried source agreements and their original parties, through
expiry. Its incoming context scale is multiplied by unbound opposing power / total
opposing power (the existing `side_power` inputs, one integer truncation); a fully
bound opposing side gives zero even at zero power, otherwise a zero denominator
keeps the ordinary scale. Unrelated allies and new opponents inherit no protection.
Pursuit legality checks the actual opposing unit pair, so a bound pursuer cannot
suppress an unrelated pursuer's context. All groups enter the same atomic
personnel commit. Failed writes and JSON retries reuse those saved rates, actions
and random draw without repeating departure costs, daily meals or attack costs.

## Walking and running

`UnitGait` is the integer contract for running (spec `2026-10-17-unit-behavior-and-battlefield-design` §5). `run_step_m` is the walk step of the same substep × `army_run_speed_permille`, after every walk modifier. `run_substep` pays one running substep's increment from `supplies`: the runners' share of today's base bite × (`army_run_supply_permille` − 1000), over 1000 × `battle_substeps`, in whole supplies with the fraction saved as the entry's `run_supply_rem` — never truncated away, so it costs the same per duration, not per kilometre. Today's whole base bite (still eaten by `eat_day`) is reserved first: below it, or when the charge would cut into it, the substep walks and nothing changes. Non-running personnel pay only their base.

**The saved gait** (`UnitGait.refresh`, per substep of `ArmySystem.march_day_saved` and again after it): `entry.gait = {mode: "run", reason, until[, battle_id]}` on the unit's own `regiments` / `foes` entry; no key is walking (an old save walks). The commander runs only for a reason the engine can see: `withdrawal` (until `march_end`: marching with `disengaging == 1`, any withdrawal march `BattleSystem` starts) or `pursuit` (until `task_end`: marching with a current received pursuit task — not a flank — whose `track.phase` is `follow`) or `join_battle` (until `battle_over`: marching, in no battle, its destination within `battle_contact_km` of the place of a live battle where a unit of its own table fights). A gait whose stop condition holds is dropped before a new reason is read; a fleet never runs. A substep that really marches (past camp packing, the saved order still a march) runs only when `UnitGait.pays_run` pays it — `run_bite` is the fit personnel's share of `day_bite(supply_use)`, the wounded and prisoners keeping their base — and then its step budget, after the last-substep catch-up, is `run_step_m` of it; otherwise it walks. The base meal stays `eat_day`'s. The commander's ability and personality do not weigh the choice yet.

## Costly orders and daily resolution

`BattleOrders` saves canonical warrants in `GameState.battle_orders`, retaining terminal receipts after battle removal. `BATTLE_ORDER` needs a stable request ID; exact replay returns before costs/history, conflicting reuse fails. Ownership, live membership and military law are checked at send and delivery. Continuing actions are mutually exclusive; the last lawful actual delivery wins regardless of dispatch order. Inspiration preserves the continuing action. A warrant carries immutable issued targets and beneficiary counts; new arrivals do not enlarge its award. Bounty is the ceiling of living recipients times `orders.csv`'s per-thousand price; delivery caps recipients to issued counts. Dispatch reserves the promise, delivery pays current survivors and releases the rest; cancellation, lost/fused couriers, missing targets and battle endings release unused gold. Courier fees remain spent. `available_gold` is the voluntary-spending boundary in ActionSystem and recruitment; involuntary losses may consume a promise, so execution checks again and invalidates an unfunded reward. Inspiration has saved cooldown/resistance deadlines, bounded morale and a real king-presence bonus. Affordability checks gate positive costs only, so an underfunded reward promise cannot block a free local surrender. Surrender pays through personnel and equipment, without a fictitious local fee; refusal preserves the previous action. Accepted surrender atomically creates source-preserving prisoner batches for every fit and wounded survivor, retains equipment/commander evidence, and resolves the surrendering holders’ existing custody before removing their control. The nearest capable opposing battlefield receiver takes custody; the king independently requests safe departure and never enters the personnel roster. A failed refuge search is recorded without cancelling the troops’ surrender.

`BattleStrength` constructs equipment/identity once, then orders categories training, morale, discipline, supply, formation/terrain and action. Same-category deviations merge around neutral before the CSV clamp and one truncation. Every source is unique with its reason; duplicated sources fail. The old `ArmySystem.power` chain is not wrapped or multiplied again. Each engaged day saves its RNG draw and complete pending casualty plan before the atomic personnel writer. Retry/read-load repeats neither RNG nor costs; same-day settlement is inert. Standoffs draw nothing. Actual attack uses carried supply and exposes defence; depleted forces fall back with reasons. A round retains context, costs and loss reasons. Morale breaks at the CSV threshold; no counter forces a draw. Withdrawing units march under the existing camp deadline while still in the battle, and leave only after real separation. No safe route means no escape. Reinforcements retain the same battle and frozen terms. Duration benchmarks record contact/end days, casualties, food and causes, with no duration-specific branch.

## Battle groups

`BattleGroups` splits each battle unit's fit personnel into representative groups of at most `battle_group_size` (the last group the remainder, units never pooled) and saves them as `battle.groups[unit] = [{count, role, x_m, y_m}]` with `battle.group_facing[unit]` (whole degrees, `WarFront.facing_deg` convention: 0 = +x, y down, toward the mean anchor of the other side's units, 0 when none). Positions are the unit's own `x_m/y_m` anchor plus `BattleFormation.slots` of its current formation scaled by `battle_group_spacing_m` across the front and `battle_group_depth_m` back (away from the enemy), rotated to the facing and rounded to whole metres once. Role is `front` for slots on the foremost rank, else `reserve`. `refresh` rebuilds everything from the fit counts (sums conserved, a group index is no identity, a unit that left loses its entry, an old save gains the fields) at `_start`, `join` and the top of each daily `prepare_day`. Deployment lines (`BattleGroups.deployment`, pure): the axis runs from the defenders' mean anchor toward the attackers' (+x when they coincide); each side's line centre is the battle place ± axis × `battle_line_gap_m` / 2 (att on the + side); a side's units stand abreast in sorted code order, each as wide as its front groups (front count × `battle_group_spacing_m`, at least one spacing), the side centred; a unit's target anchor is the centre of its width, rounded to whole metres once. `deploy_day` (top of `prepare_day`, before the refresh, once per absolute day via the saved `battle.deployed_day`) steps every unit's anchor `x_m/y_m` toward its target by at most `battle_deploy_step_m` whole metres, stopping exactly on it. It moves both sides, but not a captured unit, one with no fit man, or one seated in a town (its walls are its line), and the whole battle stops deploying once any side is ordered to retreat or any unit is withdrawing (`battle_retreat` or `disengaging`), so the winner never closes on a falling-back side; `_start` stamps `deployed_day` so the day of contact moves nothing. The march never moves a unit in a battle, and the groups refresh around the moved anchors. Contact (P4.4d4): `BattleGroups.engaged_permille` is (engaged x 1000 + (fit - engaged) x `battle_reserve_permille`) / fit, integer division, where engaged is the summed count of the unit's `front` groups within `battle_group_contact_m` (inclusive, squared whole metres) of any group of the other side; a reserve rank or a front still approaching counts only the reserve share; 1000 with no saved groups. `BattleSystem.unit_strength` lists it as `contact:engaged` (category `contact`, between `formation_terrain` and `action`, clamped like every category by `battle_strength_factor_min/max_permille`) with the reason "N of M in contact with the enemy line", so siege assaults, town battles and events inherit it.
