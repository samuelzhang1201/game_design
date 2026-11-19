# Player siege: besiege, storm and take an enemy town — design

- Date: 2026-11-18
- Status: draft for the owner's review. Nothing is built.
- Builds on: `2026-10-16-battle-system-design.md` §13.5 and §14 (approved; the five tactics, blockade by
  real routes, the deadline contract, no unordered assault), its plan
  `plans/2026-10-16-battle-system/06-area-tasks-and-sieges.md` P6.2–P6.3, and
  `2026-10-07-enemy-ai-and-battle-design.md` §5 (the siege on `main` today). Where they differ, this
  spec rules for the siege; everything else in them stands.
- Engine facts it relies on: `scripts/engine/guide/siege.md`, `battle_and_ai.md`,
  `raid_and_defeat.md`, `regiments.md` (area tasks P6.1).

## 1. Intent

Today siege runs one way. An enemy host can besiege, storm, take and lose the crown's towns. The
crown cannot besiege or storm an enemy town. A column sent at one halts in front of its standing
units, which have no state and are never fought. Most enemy towns hold no troops at all, because
only a town where a regiment is quartered has a seat. The owner wants the player's own armies to
besiege, storm and take enemy towns.

**Owner rulings (2026-11-18):**

1. **Scope: all five tactics before release.** The player's siege ships with mining, bombardment,
   escalade, terms and blockade (§14.2 of the battle design) all working, not a progress bar first.
2. **One siege system for both sides.** The enemy's siege and the player's are the same records and
   the same rules.
3. **Militia on both sides.** A besieged town with no garrison raises a militia from its population
   and works, whoever holds it. The tuned invasion changes as a result and is re-tuned in its own
   step.
4. **A capture is an occupation, on both sides.** The town's manors move to the taker's ruling house,
   and the province, border and capital do not. Occupation lasts while the taker holds the town and
   ends when the town is taken back or the taker leaves. `MapOwnership` is never touched.

**Goals**

- The player orders a siege of a known enemy town, assigns men to the five tactics, orders the assault
  when the walls allow it, offers terms, and takes the town. Every one of these is an order with a
  cost that rides by courier.
- The enemy besieges the player's towns with the same tactics, and answers a siege of its own town
  with relief.
- Every figure is whole and comes from `data/`, and every move carries a reason. No random number
  enters except the seeded draws of existing battle events.

**Non-goals**: conquest of provinces, peace treaties, occupied towns as supply depots or recruiting
grounds, new enemy hosts raised to relieve a town, naval sieges or blockade by sea, sorties by the
garrison, a separate siege battlefield.

**Anti-goals**: two siege rule sets that drift apart; a siege won by a timer, so that standing
outside long enough takes the town; an assault the commander starts on his own; a militia that is a
bare number with no people behind it (it would break the battle design's conservation of people,
§15.2); a player who can sweep a string of empty towns by marching.

## 2. Approaches

| | Approach | Verdict |
|---|---|---|
| **A** | **One shared siege record per town** (`GameState.sieges`) and one rule set for both sides. The hosts' siege figures are migrated into it, the progress bar is replaced by the five tactics, and militia are raised as real units. | **Chosen.** It is the only approach that holds rulings 1–2, and P6.2's plan already names this record. |
| B | Keep the enemy's `SiegeSystem` as it is and add a separate crown-side siege with the tactics. | Rejected: it breaks ruling 2, and the two rule sets would drift. |
| C | Militia as a defence figure inside the town's power, with no units. | Rejected: assault casualties, prisoners and surrender need people (§15.2). |

## 3. The siege record

`GameState.sieges[id]`. `id` is `"s<n>"` from a saved `siege_next_id`. Every field is whole and is
saved, and absent keys load empty. **One siege per town**: a second besieger at the same town joins
the existing record.

| Field | Meaning |
|---|---|
| `town` | burg code |
| `attacker`, `defender` | kingdom codes. `defender` is the town's holder when the siege opened (the occupier for an occupied town). |
| `units` | besieging unit codes physically stationed at the town (crown codes or foe codes) |
| `hosts` | the AI hosts in it ([] for the crown) |
| `task_id` | the crown's `ARMY_TASK` id ("" for the AI) |
| `opened_day`, `days` | absolute day the deployment completed; days of siege so far |
| `integrity` | works intact, 0..1000; 1000 at open for walls or a citadel; an open town (works `town`) has none and keeps 0 |
| `entries` | entry id → `{x_m, y_m, inflow_share, closed_by}` (§4.1) |
| `stores` | the defender's food in supply units (§4.1) |
| `alloc` | tactic → men, the last plan the commander received (§4) |
| `mine`, `ladders`, `engines_built`, `engine_work` | tactic progress (§4.2–4.4) |
| `breach` | 1 when a section is down (`integrity` ≤ `siege_breach_integrity`, or a finished mine) |
| `assault_battle` | int battle id of a running assault, else -1 |
| `terms` | the standing offer and the agreement (§4.5) |
| `militia` | militia unit codes raised for it (§5) |
| `history` | reasoned day lines, the source of the letters (§9) |

The hosts' minds keep only `siege_id`. The old figures (`siege_progress`, `siege_days`,
`siege_town`, `assault`, `assault_due`, `starved`) move into the record. An old save converts once:
`integrity` = 1000 − `siege_progress` for a walled town, and `days` and the pending assault are kept.
The conversion is logged with its reason, and running it again changes nothing.

**Activation is unchanged** (`SiegeSystem.active`): a completed deployment and at least one live, fit,
non-disengaging column stationed at the town. Presence is computed when read. The same gate now
applies to a crown besieger. Only units actually stationed contribute men, and later arrivals add
men from the day they arrive and get no back pay (P6.2's staggered-arrival cases hold as written).

## 4. The five tactics

**The men pool.** Each day the pool is the fit personnel of the stationed besieging units. Wounded,
captives, guards of prisoners, and men in a field battle elsewhere are excluded. `alloc` assigns
whole men to `blockade`, `mine`, `bombard`, `ladders` and `engines` (building engines). The sum
never exceeds the pool. When the pool shrinks, allocations are cut in the fixed order engines →
ladders → mine → bombard → blockade, and each cut is logged with its reason. A crown plan comes by
`SIEGE_PLAN` (§6). An AI plan comes from its doctrine's per-tactic per-mille columns
(`ai_doctrines.csv`, new columns). The fixture of 300 men (mine 120 + engines 100 + blockade 80 legal, plus
ladders 1 refused with the plan kept) is P6.2's and stands. Every rate below is a key in
`battle/balance.csv` or a row in `data/battle/siege_tactics.csv` (new, by works).

### 4.1 Blockade and the town's food

- **Entries**: one per pack route (`geography/routes.csv`) whose `from_burg` or `to_burg` is the town,
  placed on the route at `siege_entry_km` from the town, plus one "countryside" entry. A town with no
  route has the countryside entry alone. `inflow_share` comes from the route group (`siege_tactics.csv`
  `entry_share` by `roads`, `trails` and `searoutes`). Shares are normalised over the town's entries.
  A `searoutes` entry never closes, since naval blockade is a non-goal: a port keeps its sea share
  of food. This is accepted, and a port is slower to starve.
- **Closing**: entries close in descending share, and each needs `siege_blockade_men_per_entry`
  blockade men. The units carrying those men camp at the entry (`ArmyGround.settle` near its point).
  An entry counts as closed only while a besieging unit with fit men stands within `siege_entry_reach_m`
  of it (`closed_by`). A relief column that fights it off reopens the entry. So 100 men do not seal a
  great town: it has more entries than they can close.
- **Stores**: for a crown town, the existing `TownStores` (crown + lord + house). For any other town
  they are set at open as `need × siege_tactics.csv stores_days` by works. Each day:
  `stores' = max(0, stores − need + need × open_share / 1000)`, where `need` is the garrison's and
  militia's daily ration plus `population × siege_civil_need_permille / 1000`, and `open_share` is the
  per-mille share of the open entries. With every entry open, the town loses nothing. The P6.2 fixture
  holds: stores 100, need 10, open inflow 4 → 94 on day 1 and 40 on day 10; fully closed, 0 on
  day 10.
- **The besieged's supply lines**: for a crown town, `SupplyLines.siege_cut` cuts only the lines whose
  route passes a closed entry. It no longer cuts every line at once.
- **Hunger**: at 0 stores, the existing `hunger_day` morale loss falls on the garrison and militia.
  A garrison whose mean morale falls below `siege_yield_morale` yields if its laws let it (§4.5).
  Otherwise it holds and keeps losing men to desertion by the existing rules.
  - A yield with no terms is a hand-over (§7). It needs the besieger's `quarter` law at `give`: the
    garrison and militia become the besieger's captives (`PrisonerSystem.capture`). Under `refuse`
    no yield is accepted, and the town holds on, starving.
  - For a crown town, the blockade gates the inflows that already exist instead of adding one. The
    catchment's manor deliveries and the supply-line deliveries into the town arrive at `open_share`
    per mille. The garrison and militia eat from the three pools in `TownStores`' existing order.
    The formula above, with its own inflow term, is for a town that has no `TownStores` (any foreign
    town).

### 4.2 Bombardment

- **Engines**: the stationed artillery units' fit guns count, plus `engines_built`. Building an
  engine takes `siege_engine_man_days` of `engines` men (work carried in `engine_work`) and
  `siege_engine_gold` from the besieger's chest (the crown's treasury through `WorldLedger`, with a
  reason; an AI host's plunder). Each engine needs `siege_engine_crew` of `bombard` men, so men
  short of a full crew idle an engine.
- **Damage**: `integrity −= crewed_engines × siege_tactics.csv bombard_damage` by works (a citadel's
  is smaller). It is never below 0.
- **Repair**: the defender's militia and garrison mend `siege_repair_per_100_men` a day while
  `integrity` > 0, and never above 1000. While the besiegers out-damage the repair, the walls fall.
- **Wear**: every `siege_engine_wear_days` of firing, one built engine is lost (and logged). Guns are
  never lost to wear; they die in battle as now.

### 4.3 Mining

- **Progress**: `mine += mine_men × siege_mine_rate / 1000` a day. The mine finishes at
  `siege_tactics.csv mine_need` by works, and it is not offered for an open town. P6.2's fixture
  holds: 100 men at a rate of 2000 (2 a man) and a need of 1000 finish in 5 whole days, and a
  same-day re-entry adds nothing.
- **Cost**: `siege_mine_gold_per_100_men` a day, paid as in §4.2.
- **Risk**: the existing battle event `ev_36` (`tunnel`, `battle_events.csv`, P4) is offered each day
  the mine has men, through its own seeded chance and cooldown. Its choices (shore, stop, reroute,
  report) act on the real mine: `progress_loss` sets `mine` back.
  - Step 9 adds a `collapse` outcome row that kills its share of the mine men through the personnel
    batch, and a defender-side countermine row.
  - **Who chooses**: the crown, when the crown is the besieger or the defender, as with any battle
    event. An AI side takes the doctrine's fixed choice (`ai_doctrines.csv` `tunnel_choice`), never a
    random one.
- **Finish**: `breach` = 1 and `integrity` drops by `mine_breach_damage`. The mine then resets to 0
  for a second one.

### 4.4 Escalade and the assault

- **Ladders**: `ladders += ladder_men × siege_ladder_rate / 1000`, ready at `siege_ladder_need`.
- **When an assault is allowed**: an open town always; a walled town or citadel only with `breach` or
  ladders ready. Otherwise `SIEGE_ASSAULT` is refused with words, and the AI does not try.
- **No assault without an order**: the periodic `siege_assault_days` timer is retired. For the crown,
  an assault happens only through a received `SIEGE_ASSAULT` (§6). The commander reports a breach or
  ready ladders as an opportunity and waits. For the AI, a doctrine rule decides: it storms when the
  assault is allowed and its odds against the defenders reach the doctrine's `storm_odds_permille`,
  or when the defenders are starving. The odds are `BattleSystem.odds_permille` over
  `BattleStrength` figures, which include integrity, not over the old `ArmySystem.power`.
- **The assault is the existing town battle**: one battle per town (`BattleSystem`), the besiegers
  attacking and the garrison and militia holding the works. The assault flag that lets the walls be
  fought is now the record's `assault_battle`. The rule that an outer-camp victory cannot breach the
  walls stays.
- **What the works give in the assault**: the defender's works factor becomes
  `1000 + (defend_permille − 1000) × integrity / 1000`. A breach counts its section as
  `integrity` = 0 for this factor. An open town keeps its `town` row as today.
  - The factor is a new `BattleStrength` factor, "siege works", applied to every unit the siege
    record lists as a defender (garrison, woken units, militia). A foe never holds a seat, so the
    pinned `ArmySystem.terrain_factor` gives it no works. A crown seat unit already gets the full works
    there, so for it the factor is the scaled figure divided by the full one, which is never above
    1000. Each defender counts the works once.
  - `EnemyAi.score` / `defenders_of` and `SiegeSystem.defend_power` keep reading the old `power`
    (pinned), so the AI judges a target's walls at full strength. This is accepted: it makes the AI
    more cautious.
- **What the attacker gets** (the storming bonus, the axemen spec's step 3, here for every arm and
  both sides): a new `BattleStrength` factor gives each attacking unit its arm's
  `army_town_defence.csv` `attack_permille` for the town's works, with a reason such as
  `storming the walls of <town> (axemen 1200)`. It lives in `BattleStrength`, never in the pinned
  `army_system.gd`. Every arm but axemen is 1000 today, so the factor changes nothing until a table
  row differs.
- **The result**: the assault ending with the besiegers holding the field means capture (§7). A
  repulse sets `ladders` to 0 (the ladders are thrown down) and keeps the integrity, the mine and
  the engines. Each round's casualties are the battle's only, with none taken again at day's end
  (P6.2).

### 4.5 Terms

- **Offer** (`SIEGE_TERMS` for the crown; AI doctrine `terms_day` and `terms_morale`): clauses from
  `data/battle/siege_terms.csv` (new): `deadline_day` (an absolute day for relief, 0 for none),
  `garrison` (`march_out_armed` / `march_out_unarmed` / `captive`), `civilians` (`protect` / none),
  `no_sack`, and `gold` (whole, paid to the town). An offer that breaks the besieger's own laws is
  refused before it rides (for example, `no_sack` with `plunder` forbidden is redundant, not illegal;
  `protect` is forced under `protect_women`).
- **Answer, made by laws and never by the player in a window** (§14.3): a crown garrison answers by
  its delivered `own_surrender` law. Under `forbid` it never yields; under `allow` it yields when the
  acceptance score below passes the threshold. A foreign garrison answers by the score alone.
  The score is
  `days_of_stores_left × w_food + morale × w_morale + (1000 − integrity) × w_works − relief_hope × w_relief + clause bonuses`,
  every weight and each clause's bonus in `siege_terms.csv`, all whole. `relief_hope` is 1000 when a
  host of the defender's kingdom has the town as a relief target within `siege_relief_hope_days`
  (§8), else 0. An offer is answered on the day it arrives, and an unchanged offer is not answered
  again.
- **Accepted with a deadline**: fighting stops at the town (no assault, mining or bombardment, with
  repair also halted). The blockade holds or lifts as the clause says. On `deadline_day` the town is
  handed over unless it has been **relieved**: relief means a relief force has actually reopened an
  entry, since flags on the horizon do not count (§14.3, `SiegeTerms.relieved`). If relieved, the
  agreement is void and the siege goes on.
- **Accepted with no deadline**: the town is handed over the next day.
- **Handing over** is a capture (§7), with the garrison treated as the clause says
  (`BattleSystem.march_out`, or `PrisonerSystem.capture`).

## 5. Militia and the town's defenders

- **Who defends a besieged town**: the defender's land units on its seat and in its camp (today's
  `ArmyGround.garrison_town` for a crown town). For a foreign town, its standing roster units seated
  or camped there are **woken** into `GameState.foes` at open, with their `ArmySystem.starting_state`,
  `host` "" and `garrison_of` set to the town. From then on they are ordinary foes that eat, fight and
  can be captured.
- **No fight before the assault, both ways.** Today `BattleSystem.siege_town_of` keeps a host's
  columns from contacting a crown garrison, and `town_contact` builds the town battle with the foes
  attacking. Step 3 mirrors both:
  - A unit stationed in a siege, on either side, makes no contact with that town's defenders until
    `assault_battle` is raised.
  - The town battle can then be built with the crown attacking and the foes on the works.
  - A relief column, or a besieger outside the record, still fights in the field as today. They go back to standing roster units only if the siege lifts with them alive and
  in place, carrying over their losses (the roster row's men less the dead).
- **Militia**: a besieged town with no garrison when the siege opens raises militia. A town that has
  a garrison does not. Strength is `population × town_militia.csv men_permille / 1000` by works,
  capped at `men_cap`. The arm mix also comes from that table, with an infantry-and-archers first
  draft. The unit lands on the defender's side: in `regiments` for a crown town and in `foes` for any
  other. It carries `militia_town` and is placed on the seat. Militia never march: every movement
  order on a militia unit is refused, and the AI and the folio offer none. They do eat from the
  town's stores and fight the assault from the works.
- **The people behind them**: militia are enlisted and released through the existing personnel
  model, with no direct population debit.
  - The town's province reserves the men with `MilitaryRoster.mobilize`, and the unit gets a
    generated `army_roster` row with its equipment and cohorts, so `MilitaryBootstrap`'s integrity
    check holds.
  - Population falls only when a man dies (`MilitaryRoster.transition`).
  - When the siege ends, the living are released with the reason `militia of <town> stood down`.
    Captured militia follow `PrisonerSystem` and are released as civilians later (§2).
  - The size cap is the militia table's `men_cap`, bounded by what the province can still mobilise.
    The recruitment panel's caps do not apply, since the militia is a levy, not a recruit.
- **The enemy's sight of defence** (`EnemyAi.defenders_of`, `score`): a town with no visible garrison
  counts the militia it would raise (from data) as its defence. So a host that sees an empty walled
  town weighs its militia, and RAID applies only to plain manors.

## 6. The crown's orders

Every order below is an `action_code` with a row in `action_signatures.csv` (opinion signature) and
`order_costs.csv` (cost). Each rides by courier to the siege's commander, the task's commander as in
P6.1, with the courier fee paid only beyond `king_command_radius_m`. A lost courier leaves the siege
as it was. Every order is validated and refused with words from `data/army/task_words.csv`.

| Order | What it does | Signature (first draft, the builder sets the axes) | Cost |
|---|---|---|---|
| `ARMY_TASK` kind `siege` (exists, P6.1b/c) | The units march to the town's camp slots, deploy, and open or join the siege. A task executor for `siege` is added beside search travel. | existing | existing |
| `SIEGE_PLAN {task_id, alloc}` | replaces `alloc` | none (militarism 0) | filing fee |
| `SIEGE_ASSAULT {task_id}` | the commander storms when it is allowed; refused when it is not | militarism and expansionism like `ARMY_MARCH` | filing fee, plus the assault day's extra rations (existing attack consumption) |
| `SIEGE_TERMS {task_id, clauses}` | sends the herald with the offer | leans to the conciliatory axes | filing fee, plus `gold` if accepted |
| `ARMY_TASK_CANCEL` (exists) | lifts the crown's siege | existing | existing |

**Which towns**: a town of the `{raider_realm}` only. The foes, hosts, doctrines and relief all
belong to that one realm today (`raid_hosts`, `resolve_realm("raider_realm")`). A siege of any other
kingdom's town is refused with words. Several enemy kingdoms are the PRD's post-MVP
"AI opponent kingdoms".

**Where the player gives them (the UI's look is made in the editor, never in code):**

- **WAR ROOM**: a drawn blue march arrow whose tip lands within reach of a **known** enemy town
  (`ArmyTasks.known_town`) offers **Besiege <town>** in the march confirm. Confirming pencils an
  `ARMY_TASK` siege draft whose circle is the town's reach and whose `known_target_id` is the town,
  so one task means one town (§13.5). It sits in the resolutions scroll and is deployed like any
  draft. The full circle-drawing tool for every area task is not part of this spec.
- **The folio's siege page** (`WarFolio`, for a unit in a crown siege): the five allocations with the
  pool and what each is buying (days to a mine, engine damage against repair, closed entries out of
  all, stores-days known), **Storm** (enabled only when allowed, with the reason when not), **Offer
  terms…**, and **Lift the siege**. Each pencils a draft.
- **The map card of a besieged town** (left column, facts): attacker, days, integrity as a word, how
  many entries are closed out of all, breach and ladders. It shows what the crown knows, fogged for a
  foreign town (§9).

## 7. Capture and occupation (both sides)

- **Capture** (`SiegeSystem.capture`, generalised from the host-only version): the town's manor and
  its province's manors within `siege_capture_radius_km` that are no other town's own manor
  (`taken_cells`, unchanged) go to the attacker's ruling house through `MapManors.set_owner`. The
  reason is `taken by <realm>'s <host or the crown's army>: siege of <town>`, and each one's house
  before is kept on the siege record. Province control (`MapManors.controller_of`) can pass as it does
  today. No province, border, capital or other town moves.
- **The occupiers**: the besiegers turn HOLD (a host), or the crown's units garrison the town (seat
  and camp, `ArmyGround`). `ArmyGround.holds` and `seated_in` learn that an occupier holds a town it
  occupies. Today `holds` asks for the province owner, so a crown unit could never seat in an enemy
  province.
- **Liberation is symmetric**: an occupation ends when the defender's house holds the town's manor
  again, or when no unit of the occupier is left in the town's reach. Each manor the occupier still
  holds goes back with the reason `liberated: <occupier> left <town>`. An occupied town can itself be
  besieged, with the occupier as `defender` and the old holder as `attacker`. That is how the crown
  wins its own towns back under the shared rules.
- **What a fall costs the crown** is `DefeatSystem.on_town_lost`, unchanged.
- **The crown's control stops at its own realm.** `MapManors.controlled_provinces` and every reader
  of it (the economy panel, BUILD, FOCUS, the model's "Your provinces" list) count only provinces of
  the player's realm. An occupied foreign province whose manors are mostly the crown house's is not
  a crown province: it gives no BUILD or FOCUS there and no world-delta path (inv. 1). Its manors'
  lines still pay their holder. The enemy's control of an occupied crown province is unchanged.
- **What a capture gives the crown** (new, mirroring it):
  - `TOWN_TAKEN` in `action_signatures.csv` (not an order) gives each seat
    +round(`battle_victory_opinion` (new key) × (1 + `OpinionDrift.weight`)), reason
    `took <town> from <realm> (supports, <axis>)`; a seat of opposed ideology feels it as a loss by
    the drift's own sign.
  - Under `plunder: allow` without `no_sack`, `siege_sack_permille` of the town's month worth goes
    into `metrics.strategic` (`WorldLedger`, source `sack`).
  - The occupied manors' lines go to the crown's house as any holder's do (inv. 11), with nothing
    extra.
  - Once per town per occupation (`GameState.town_takes`, saved).

## 8. The enemy's answer

- **Relief** (`EnemyAi`): a field host of the defender's kingdom (ADVANCE, RAID, or SIEGE elsewhere)
  gets the besieged town as a candidate of kind `relief`. Its score is the same form as `score`, with
  `value` replaced by the doctrine's `relief_bonus` plus the town's line value, and `defence` replaced
  by the besiegers it sees. It weighs that against what it is doing at its next think. A host that
  picks relief marches on the nearest closed entry and attacks the units there, which is an ordinary
  field battle. A host already in a siege leaves its own only through the existing WITHDRAW, so its
  progress is kept on the record for its reserve or lost.
- **Standing roster units** of the defender's kingdom elsewhere never move. No new host is raised.
  An empty field means no relief, and that is accepted.
- **Inside the town**: repair (§4.2), countermining (`ev_36`'s defender branch), the terms answer
  (§4.5). The garrison never sorties (unchanged).
- **The besieger lifts** for the existing reasons: beaten, hungry, morale, its main host gone, or a
  crown `ARMY_TASK_CANCEL`. The record then closes: militia stand down, woken units go back, and
  integrity is not kept for a later siege.

## 9. The besieger's supply, and the letters

- **Supply**: a crown besieger eats by the existing supply lines and foraging (`SupplyLines`,
  `Forage`). A line through hostile units is cut as now, and the deeper the siege, the longer
  and more exposed the line. No occupied-town depot (non-goal). An AI besieger lives on its stores
  and plunder as now.
- **The crown's own siege letters** come from the commander by `king_report` courier and publish
  when it arrives (`battle_and_ai.md`, the immutable remote facts). One letter is filed per
  `siege_report_days` and on every event: `siege_ours_begin` (entries, stores-days if known),
  `siege_ours_breach` / `siege_ours_ladders` ("awaiting your order to storm"), `siege_ours_mine_lost`,
  `siege_ours_terms` (accepted / refused / void), `siege_ours_relief` (enemy columns reach an entry),
  `siege_ours_taken`, `siege_ours_lifted`, `siege_ours_liberated` (the occupation lost). Fixed prose
  in `templates.csv` with the realm slots, and the figures are the commander's own (men, engines,
  integrity as a word). The defender's stores and morale are an estimate by the town's
  `Intel.level`, never the truth.
- **The enemy's siege of a crown town** keeps its letters (`SiegeSystem.news`). The lines the
  progress bar wrote (`siege_begin` gain) become entries closed, integrity and breach.
- No model sees a siege letter or a number. A typed order about a siege goes through the existing
  `{narrative, impacts}` path and can only become the action codes above.

## 10. Constraints

- Inv. 1 to 11 of the root `CLAUDE.md`. In particular: engine-pure `RefCounted` code under
  `scripts/engine/`; one seeded stream, drawn only by the battle events that already draw; whole
  numbers in the save; reasons on every opinion, manor and population move; numbers in
  `battle/balance.csv`, `siege_tactics.csv`, `siege_terms.csv`, `town_militia.csv`, `ai_doctrines.csv`
  (each listed in `data/tables.csv`; `ai_doctrines.csv` exists and gains columns).
- Never edit the files `Map3DRoyalCarrierSource._SOURCES` pins (`unit_bodies`, `body_motion`,
  `army_system`, `march_path`, `war_front`). New rules go in `SiegeSystem`, `SiegeTactics`,
  `SiegeTerms`, `TownMilitia`, `BattleStrength` and `EnemyAi`.
- The day order stays `TickEngine.resolve_day`'s. Tactics and terms settle in the sieges phase after
  battles. Couriers land the plans as today.
- Old saves load: the conversion in §3, with no woken units and no militia for a siege already
  running. Militia rise only for a siege that opens after loading.

## 11. Build steps (one PR each, in order)

Each step is playable and leaves the enemy's siege of the crown working. The player's entry
(steps 12–13) lands only after all five tactics, per ruling 1. Each step's hand-computed GUT fixture
is named, and each step updates `scripts/engine/guide/siege.md` (or its new topic guides).

| # | Step | Done when |
|---|---|---|
| 1 | **Siege record**: `GameState.sieges`, the migration from `ai_hosts`, `SiegeSystem` reads and writes it; behaviour identical | the existing siege, raid and invasion tests pass unchanged; an old save converts once; JSON round-trip |
| 2 | **Storming factor** in `BattleStrength` from `army_town_defence.csv` attack, both sides | fixture: axemen attacking walls 1200 with a reason, infantry 1000 unchanged |
| 3 | **Sides generalised**: `attacker` / `defender` on the record; garrison, capture, HOLD, liberation and `ArmyGround.holds` read the record, not "the crown"; the mirrored no-contact rule and the crown-attacking town battle (§5); the crown's control stopping at its realm; the capture-gains block (§7) | a fixture where a foe-held occupied town is retaken through the shared path; occupation and liberation reasons |
| 4 | **Militia and woken garrisons** (`TownMilitia`, `town_militia.csv`), the population ledger lines, `EnemyAi` defence counts militia | fixtures: militia size by works and population; people conserved over raise → dead → stand down; the woken unit returns with its losses |
| 5 | **Re-tune the invasion** for militia: `ai_*` / `siege_*` keys, `test_raid`'s run, `test_invasion_end_to_end`, `tools/sim_invasion.gd` | the no-orders run is described in the key notes the way `raid_supply_permille`'s is; the owner sees the new day-by-day run |
| 6 | **Blockade by entries and stores** (§4.1), `SupplyLines.siege_cut` per entry, yielding by hunger under laws | P6.2's stores fixture; 100 men cannot close a town with more entries; `test_relief_requires_an_open_route` |
| 7 | **Men pool and allocation** (`SiegeTactics.allocate`), AI doctrine columns | P6.2's 300-men fixture; the cut order on loss; staggered arrival |
| 8 | **Bombardment, engines, repair, the "siege works" factor in `BattleStrength`** | fixture: engines × damage against repair, day by day, to a breach |
| 9 | **Mining** with `ev_36` on the real mine | P6.2's 100-men fixture; a collapse sets the mine back and its dead come through the batch |
| 10 | **Escalade, the assault rule, the timer retired**; AI storm doctrine; the progress bar removed | no assault without an order or a doctrine; repulse throws down the ladders; capture only by assault or terms |
| 11 | **Terms** (`SiegeTerms`, `siege_terms.csv`, the score, the deadline, `relieved`) | before, on and after the deadline; relieved by a reopened entry only; `own_surrender: forbid` never yields |
| 12 | **The crown's orders**: the `ARMY_TASK` siege executor, `SIEGE_PLAN` / `SIEGE_ASSAULT` / `SIEGE_TERMS`, costs and signatures, couriers, the crown's siege letters | a crown column takes an enemy town end to end, deterministic over a mid-run save |
| 13 | **WAR ROOM and the card**: Besiege on the drawn arrow, the folio siege page, the town card's siege facts (editor-made look, `visual-review`) | real-window review through real input |
| 14 | **Relief AI** (§8) | a host leaves a raid to relieve a besieged town and reopens an entry |
| 15 | **The siege on the 3D map** (P6.3's staging: engine positions, ladders, tunnel spoil, breach, blockade camps at the entries) | `visual-review`; nothing shown before its real progress |
| 16 | **The 40-day benchmark** both ways, across a month end | P6.2's release condition: five tactics separately and combined, real blockade, terms, relief, cross-month |

Steps 2 and 14 do not depend on the steps before them and may land earlier. Art for step 15
(trebuchet, ladders, tunnel) follows the asset rules in `tools/CLAUDE.md`: Tripo on the paid plan, no
Hunyuan, and ask before queuing generation.

## 12. Where it sits in the build order and the MVP

- PRD §6 Step 8 is now the battle system. This spec is its plan's **P6.2–P6.3** with the player's side
  made explicit. PRD §6 is strict, and Steps 3–7 (council politics, the chapter framework, stages
  4–6) are still unbuilt ahead of it. Building this now runs ahead of them, which is the owner's call
  when the plan is approved. The 3D look route is unaffected.
- The MVP is the prologue (`docs/design/CHAPTER_0.md`). The siege serves PRD §7's
  *Spears in the West* arc: the player can now answer the raid by striking back at the
  `{raider_realm}`'s towns. No chapter beat reads a crown capture yet. A beat on `town_takes` belongs
  to Step 9's event chains and is not part of this spec.

## 13. Left to the builder

- Every first-draft value in the new tables, set by the hand fixtures and then by step 5 and step 16's
  runs.
- The exact opinion axes of `SIEGE_PLAN` / `SIEGE_ASSAULT` / `SIEGE_TERMS` / `TOWN_TAKEN`.
- How the existing assault and `siege_*` event names map to the new ones in the news.
- The topic guide split once `guide/siege.md` nears its size cap (`test_claude_md_size.gd`).

## 14. Implementer's calls for the owner to check

These calls were made while writing this spec and after its builder check. None of them is an owner
ruling.

- The order entry is a drawn WAR ROOM arrow onto a known town (§6). The full circle tool is not part
  of this spec.
- Only towns of the `{raider_realm}` can be besieged (§6).
- The crown's province control stops at its own realm. Occupied foreign manors pay their lines, with
  no BUILD or FOCUS there (§7).
- A garrison raises no militia. Militia are enlisted and released through `mobilize`, and stand
  down when the siege ends (§5).
- A yield with no terms makes the garrison captives, and needs the besieger's `quarter` at `give`
  (§4.1).
- The AI reads the walls at full strength, while the battle reads the damaged ones (§4.4).
- Sea entries never close, so a port starves more slowly (§4.1).
- No relief host is newly raised (§8). Integrity is not carried over to a later siege (§8).
