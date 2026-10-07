# LEDGER M1 + M2 — supply lines, morale and the war workshop — design

> §3's monthly capital resupply is replaced by 2026-10-07-army-supply-lines.

Status: built 2026-09-30 (branch ledger-supply). Designed 2026-09-30
overnight under the owner's standing order ("完成游戏本体论的设计…plan和
implementation，补全缺少的部分。根据你自己的判断行动，不用问我了"). Every
choice below that the owner has not ruled on is marked **Default** with
what it costs if wrong. Charter: `2026-09-30-ledger-ontology-design.md` §8
(M1, M2). These two milestones land together because a supply line needs a
source of strategic goods and a workshop needs somewhere its goods go.

Three rulings were made during the build, none by the owner (asleep,
autonomous): **a war workshop works for the lord only while the crown's
own house holds its manor** — sold or seized away, it stands idle
(`WorkshopSystem.cells(repo, state)` filters by `MapManors.is_crowns`;
`WORKSHOP_RATE` refuses a manor the crown does not hold) — rather than
letting a foreign workshop go on converting or taking orders. **The road's
supply line walks its first leg**, from the depot to the road network,
the same way `CourierSystem.need_along` walks a courier's road, rather
than the original code's start at the first waypoint (a review found it
dropped that leg entirely whenever a route left the depot's own road
node); `plan()` also builds one shortest-path tree per call, shared by
every regiment, rather than one Dijkstra run per regiment. **The LEDGER's
property gauges moved here from L0**: `2026-09-30-ledger-ontology-design.md`
§6.3 left them for M1 without settling their shape, and its own §7.2's
`{key, text, accounts}` sketch was never built; this plan's Task 5 instead
draws `{key, label, value, max}` rings over a sphere's name — a regiment's
supplies and morale, a goods pool's stock against 12 months of intake —
the shape that spec's §12 now records as built.

## 1. What changes for the player

Today the chain *grain → strategic goods → regiment → morale* is broken in
three places: nothing turns civil goods into strategic goods except buying
them with gold, nothing resupplies a regiment (its `supplies` only fall),
and morale never moves. After M1 + M2:

- **A war workshop** is a building. Each month it turns up to its capacity
  of the LORD's civil goods into the lord's strategic goods, at a loss.
  The player sets each workshop's rate — off, half, full — so civil goods
  must be split between feeding the villages, raising buildings and arming
  the host (charter rule 2).
- **Every regiment of the realm is supplied along a supply line** from the
  realm's depot (the capital, `CourierSystem.origin`) over the road
  network to where the regiment stands NOW. Each month the crown ships
  what the regiment is short of; the longer the road, the more is lost on
  the way (charter rule 6). A regiment in garrison inside a province the
  crown controls draws its stores through its town: no road, no loss (the
  crown still pays for them).
- **Morale follows the stores.** A fed regiment's morale climbs toward a
  high mark, a hungry one's sinks, a garrison's a little higher. Morale
  already scales power and readiness (`ArmySystem.power`,
  `readiness_permille`), so hunger now costs fights and pace.
- The LEDGER lights `converts_in`, `converts_out`, `supplies_in`,
  `supplies_out` and `garrisons`; the famine loop gains its armed twin, a
  vicious "hungry host" loop.

## 2. The war workshop (M2)

- A row in `data/manor_buildings.csv`: `war_workshop`, tier 2, land `town`,
  prereq `smithy`, `civil_cost` 180, `build_days` 50, no produce, notes
  "turns the lord's civil goods into strategic goods". Built with the
  existing `MANOR_BUILD`; its slot, icon (`bld_war_workshop`, a
  `resource_icons.csv` row naming NO texture until art exists — the icon
  test holds only named textures) and tooltip come for free.
  **Default**: prereq smithy and land town — costs a data edit if the
  owner wants it anywhere.
- **Capacity** `workshop_capacity_gold` 40 gold of civil goods a month per
  workshop; **ratio** `workshop_ratio_permille` 700 (100 civil → 70
  strategic). Both `balance.csv`.
- **Rate**: `GameState.workshop_rate: Dictionary` cell (String) → permille
  0 / 500 / 1000, holding only workshops set away from the default 1000
  (like `manor_focus`). Order `WORKSHOP_RATE {manor, rate}`: a new row in
  `policy_actions_court_additions.csv` (domain economy, target manor),
  `action_signatures.csv` (steward, no ideology swing), `order_costs.csv`
  (`opinion:steward:-1:the workshop's reeve re-set`), validated in
  `ActionSystem` (the manor holds a standing workshop and is the lord's;
  rate ∈ {0, 500, 1000}). Saved; an old save has none. (Final review: the
  rates, their words and the LEDGER's order labels are `data/workshop_rates.csv`
  — `rate_permille,word,ledger_label` — and validation reads that table; a
  rate is saved through `_encode_values` so it comes back a whole number,
  and it is forgotten when its workshop is demolished or its manor leaves
  the crown — `WorkshopSystem.rate_of` reads 1000 for a cell with no
  standing workshop.)
- **Settlement** `WorkshopSystem.settle_month(repo, state, r)` in
  `TickEngine.advance` right AFTER `_settle_economy` (so this month's civil
  goods are in) and BEFORE `ArmySystem.settle_month` (so this month's
  strategic goods can ship). Workshops in cell order; each takes
  `min(capacity × rate / 1000, lord_civil left)` whole gold, adds
  `take × ratio / 1000` (integer division) to `lord_strategic`; ledger
  lines "the war workshops take civil goods" / "the war workshops make
  strategic goods" (one pair per month, summed).
- `WorkshopSystem.plan(repo, state) -> Array[{cell, rate, take, make}]` is
  the pure function the tick and the LEDGER both read (the ration
  precedent). The LEDGER projects this month's flows from the pools AS THEY
  STAND NOW; the settlement runs the same function on the pools after the
  month's intake has landed, so the two agree whenever that intake does not
  change what the pools can cover.

## 3. Supply lines (M1)

- **Who pays.** Strategic goods are gold-valued like the pools they sit in.
  A supply unit costs `army_supply_gold_permille` gold per mille (Default
  100: ten units a gold, calibrated in the plan so that fully supplying the
  realm's regiments costs about half the crown's monthly strategic intake
  on the default pack). Shipments draw on the CROWN's `strategic` first,
  then the LORD's `lord_strategic` (**Default**: the king's own house arms
  the king's host; costs a one-line change if the owner wants the purses
  apart).
- **Need.** A regiment is shipped what brings it to
  `army_supply_target_months` (4; 3 until the final review — a regiment
  refilled to exactly `army_speed_supply_full_months` read a 2/3 supply
  score all month once its use was spent, so the target is that full mark
  plus the month about to be eaten; the steady cost is unchanged) months of
  its own use at the ground it stands on NOW
  (`ArmySystem.supply_use`, which already carries the height tier), plus
  what the road will lose: `ship = ceil(short × 1000 / (1000 − loss))`.
- **The line.** `SupplySystem.line_of(repo, state, code) -> {length_km,
  loss_permille, garrison: bool, stronghold: String}`: the road length from
  `CourierSystem.origin` to `ArmySystem.position_of` along
  `CourierSystem.path_between` (summed waypoint metres ÷ 1000); `loss =
  min(length_km × army_supply_loss_permille_per_100km / 100,
  army_supply_loss_cap_permille)` (60 per 100 km, cap 600). A regiment
  STANDING — standby or garrison, anything but a march — in a province the
  crown controls has `stronghold` = that province's `capital_burg`, length
  0, loss 0 (controller ruling, final review; before it only a GARRISON
  order drew through the town), and `garrison: true` only under an explicit
  GARRISON order (`SupplySystem.garrisoned_in`). A naval regiment (fleet) is skipped (fleets are
  exempt, as for couriers), and its morale does not drift.
- **Short pools.** When the pools cannot cover every ship, each regiment
  gets `pool × its ship / total ships` (integer division, code order), so
  shortage is shared, not decided by alphabet.
- **Settlement** `SupplySystem.settle_month(repo, state, r)` inside
  `ArmySystem.settle_month`, before this month's use is spent: pay the
  gold, add the DELIVERED units to `supplies`. Ledger lines per pool: "supplies
  sent to the host" (and, when some was lost, the line names nothing extra —
  the loss is visible in the LEDGER's thread and the regiment's card).
- `SupplySystem.plan(repo, state) -> Array[{code, need, ship, paid,
  delivered, loss_permille, length_km, garrison, stronghold}]` is the one
  pure function the tick, the regiment card (`army_supply_line` row: "412
  km · 24% lost" / "at home", supplied through X / "in garrison" at X) and
  the LEDGER read (a supply line's card opens on "N km, X% lost on the way"
  or "through X, nothing lost").

## 4. Morale (M1)

Monthly, after this month's supplies have ARRIVED and before its use is
spent (the stores in hand as the month turns — computed after the spend, a
regiment refilled to three months would read two and never feel fed), each
regiment's morale moves
`army_morale_drift_per_month` (6) points toward its **mark**:
`mark = army_morale_starving + (army_morale_fed − army_morale_starving) ×
supply_score / 1000` (20 … 75), `+ army_morale_garrison_bonus` (5) under
an explicit GARRISON order in a controlled province (not for a regiment
merely standing by there), clamped 0..100 (the clamp `readiness_permille` already assumes).
Whole numbers. The regiment card's morale row gains the mark's reason
("well fed" / "on short rations" / "starving"; words from a new
`data/army_morale_words.csv` by supply-score floor).

## 5. The ontology

- `stronghold` is retired as a separate type: a garrison stands in a
  TOWN, so `garrisons` becomes regiment → town (live, M1). The type row
  goes; the spec's §2 table is amended.
- New live rows: `workshop` type (instances = standing war workshops,
  `workshop:<cell>`), `supply_line` type (instances `supply_line:<code>`, one
  per supplied regiment), links `converts_in` (civil_goods → workshop, flow
  `take`), `converts_out` (workshop → strategic_goods, flow `make`),
  `supplies_in` (strategic_goods → supply_line, flow `paid`), `supplies_out`
  (supply_line → regiment, flow `delivered` units), `garrisons` (regiment →
  town, an explicit GARRISON order only). Each reads the ONE plan function
  the tick settles, projected from the pools as they stand now (§2). Accounts are `full` (the crown's own depots) — M3 is where a
  governor starts to lie about them.
- Actions: `workshop` → `WORKSHOP_RATE` three rows (Off / Half / Full,
  `params rate=0|500|1000`, `manor=@cell`); `supply_line` → none in M1.
- Loop `hungry_host` = `supplies_in|supplies_out`, vicious: it runs when
  any regiment's supply score is under `army_supply_warn_permille` (500).
  No existing `TriggerDsl` clause can say that, so a new clause
  `host_hungry` (reads `ArmySystem.bars_of`) is added to `TriggerDsl`, with
  its test. (The virtuous `war_chest` loop still waits on M4's `attacks`.)

## 6. Tests (GUT, before code)

Hand-computed on small fixtures and on the real pack: a workshop's take
and make, the lord's civil limit, the rate order and its refusals; a
line's length and loss (a regiment at the capital loses 0), the ship
formula, proportional shortage, garrison lines, fleets skipped; morale's
mark and drift with clamps; determinism (two plans equal); the LEDGER's
new links read the plans; save round-trip of `workshop_rate`.

## 7. Out of scope

Delay on the road (a shipment arrives the same month; distance costs
loss only), interception of convoys (with sub-project C), a governor's
effect (M3), strongholds' own stores, fleets' supply.
