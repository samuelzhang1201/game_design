## Formations and per-clause agreements

`BattleRules.freeze` snapshots each side's received laws once at contact, using the first unit in sorted code order as the saved representative. `LawSystem.received` reads the newer town/unit version; foreign columns carry independent `received_laws`, seeded from declared defaults, never crown decrees. Legacy columns without that map read defaults. Existing battles without a snapshot acquire one at the first resumed day. Semantic proposals compare all conditions, scopes and deadlines independently, with both proposals and a reason preserved on rejection. The saved `parley` remains bound to the battle through new laws, commanders, reinforcements and JSON saves. `legal_actions` applies live own laws plus shared obligations; protected withdrawal/ceasefire overrides pursuit, and accepting surrender prohibits a red refusal flag without prohibiting one's own surrender. There is no king renegotiation action. `parley_clauses.csv` maps each clause to its law; prisoner treatment, wounded evacuation, safe withdrawal, permitted tactics and own surrender are separate military policies.

`BattleFormation` owns deployment independently of stance/action. `formations.csv` declares four shapes, frontage, terrain/arm/morale/training suitability, centre requirements, factors and reforming costs. A diamond's positive protection requires an actual nearby king or wounded personnel; absent a centre its penalties remain. `BATTLE_FORMATION` is a paid typed order through `ActionSystem` and the existing local/courier path; delivery revalidates membership and suitability, uses a separate side order id and saved within-courier sequence, and expires with the battle. Same-target requests do nothing; retargeting preserves the longest disorder deadline. Saved current/previous/target, progress and last-progress day advance once per completed day using fit-personnel discipline. During reforming only current deployment plus disorder applies; each factor has one source and reason; combat merges the formation/terrain category before one integer truncation. WAR ROOM and map share its shape; narrow lines fold into extra ranks instead of overlapping figures. Figure-count tiers remain `army_formations.csv`'s responsibility.

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
primary task. Risk, morale and formation preparation do not veto lawful receipt;
routing and incapacity remain facts that prevent resuming a line.
Until contact-plan delivery is integrated, pursuit requires an explicit player
task; a general's deployment warrant alone cannot authorize it.

`BATTLE_TASK` is the paid player dispatch path for a single battlefield unit.
It accepts `request_id`, `regiment`, `battle_id`, `task` and optional
`target_unit`; source/issuer and formation are not action parameters. The
OrderCosts filing charge applies once per new request, plus a courier fee only
for a new courier. Pending co-carried tasks pay independent filing charges.
Reserved reward gold is unavailable. Exact retries return the saved original
outcome before costs, history or current eligibility; conflicting reuse fails.
Local king command range delivers immediately through CourierSystem; remote
warrants remain pending until arrival. Delivery checks recipient identity,
current realm control, membership and law. Lost/expired couriers invalidate
pending tasks with a reason without refunding spent fees. Formation and pursuit execution require their own integration steps.
The dispatch path changes only the canonical primary-task ledger.

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
reused across assignment and cancellation actions.

## Delivered unit attack and hold

`BattleTaskSystem.combat_action` resolves only received tasks for this battle:
advance/flank/charge reuse attack, defend/guard_flank reuse hold. Charge retains
its own live legality check; there is no positional/flanking bonus. Pending,
replaced and cancelled warrants do not execute. Unassigned units and pursuit
tasks retain their existing side action; actual withdrawal/rout wins. Live unit
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
their own combat context and event exposure. All groups enter the same atomic
personnel commit. Failed writes and JSON retries reuse those saved rates, actions
and random draw without repeating departure costs, daily meals or attack costs.

## Costly orders and daily resolution

`BattleOrders` saves canonical warrants in `GameState.battle_orders`, retaining terminal receipts after battle removal. `BATTLE_ORDER` needs a stable request ID; exact replay returns before costs/history, conflicting reuse fails. Ownership, live membership and military law are checked at send and delivery. Continuing actions are mutually exclusive; the last lawful actual delivery wins regardless of dispatch order. Inspiration preserves the continuing action. A warrant carries immutable issued targets and beneficiary counts; new arrivals do not enlarge its award. Bounty is the ceiling of living recipients times `orders.csv`'s per-thousand price; delivery caps recipients to issued counts. Dispatch reserves the promise, delivery pays current survivors and releases the rest; cancellation, lost/fused couriers, missing targets and battle endings release unused gold. Courier fees remain spent. `available_gold` is the voluntary-spending boundary in ActionSystem and recruitment; involuntary losses may consume a promise, so execution checks again and invalidates an unfunded reward. Inspiration has saved cooldown/resistance deadlines, bounded morale and a real king-presence bonus. Affordability checks gate positive costs only, so an underfunded reward promise cannot block a free local surrender. Surrender pays through personnel and equipment, without a fictitious local fee; refusal preserves the previous action. Accepted surrender atomically creates source-preserving prisoner batches for every fit and wounded survivor, retains equipment/commander evidence, and resolves the surrendering holders’ existing custody before removing their control. The nearest capable opposing battlefield receiver takes custody; the king independently requests safe departure and never enters the personnel roster. A failed refuge search is recorded without cancelling the troops’ surrender.

`BattleStrength` constructs equipment/identity once, then orders categories training, morale, discipline, supply, formation/terrain and action. Same-category deviations merge around neutral before the CSV clamp and one truncation. Every source is unique with its reason; duplicated sources fail. The old `ArmySystem.power` chain is not wrapped or multiplied again. Each engaged day saves its RNG draw and complete pending casualty plan before the atomic personnel writer. Retry/read-load repeats neither RNG nor costs; same-day settlement is inert. Standoffs draw nothing. Actual attack uses carried supply and exposes defence; depleted forces fall back with reasons. A round retains context, costs and loss reasons. Morale breaks at the CSV threshold; no counter forces a draw. Withdrawing units march under the existing camp deadline while still in the battle, and leave only after real separation. No safe route means no escape. Reinforcements retain the same battle and frozen terms. Duration benchmarks record contact/end days, casualties, food and causes, with no duration-specific branch.
