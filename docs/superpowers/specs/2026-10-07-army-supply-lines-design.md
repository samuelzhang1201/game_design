# Army supply: carried days, town stores, supply lines — design

Owner request 2026-10-07 (items 1–7 of a fourteen-item brief; the rest are
sub-projects of their own, §9):

> 1. 军队最多携带30天的战略物资补给，一般10 - 30天，玩家需要在军队出发前需要决定携带多少补给。
> 2. 军队除了自带补给，还可以从指定的己方定居点获取补给，补给线路需要走地图上的道路，如果己方军队有补给，则会显示一个淡淡的虚化的补给线，前提是补给线没有被敌方军队截断。
> 3. 定居点补给为战略物资补给，从定居点每日扣减，同时每日消耗金币，默认补给速度等于军队消耗速度，但是可以调节 0.8x 或者1.2x的补给速度，但是会相应每日减少或增加一定金币消耗量。
> 4. 右键点击军队新增'增加补给点'按钮以选择补给点和补给速度，周边可供选择补给点为高亮显示
> 5. 城市周边的manor以税收/和交易的方式供养城镇
> 6. 军队补给信息很重要，要反映在missive上
> 7. 军队补给低于5天则会影响士气

**Status: design APPROVED in chat 2026-10-07 (owner, section by section); this
written spec awaits the owner's review.** The owner's answers, in order:
town stores A (each town holds its own stores), catchment A (nearest town in
the province), tax-and-trade A (tax in kind, house stock bought for gold),
the daily gold is a CARTAGE fee ("运输费理解正确"), interception A (cut on
contact, no rerouting), carried supplies A (a standing order, a heavier load
marches slower; the supply-speeds-the-march weight becomes a below-5-days
drag — "可以"), supply points A (one per regiment, by courier to the town).

**Build order.** This is war-system work ahead of its PRD §6 place; the
owner asked for it directly on 2026-10-07. It replaces the monthly
capital resupply of `2026-09-30-ledger-supply-design.md` §3.

## 1. What changes

| Today | After |
|---|---|
| Supplies counted in months; every land regiment refilled monthly to `army_supply_target_months` (4) of its use, from the capital, automatically | Supplies shown in DAYS, capped at 30; a regiment eats what it carries; only a regiment the player gives a SUPPLY POINT, or one standing in a town of its realm, is refilled |
| Strategic goods are two realm pools (`metrics.strategic`, `lord_strategic`) | Every town holds its own stores; the two metrics are the SUM of the towns' stores |
| A regiment in a controlled province draws through the province capital, no loss | Removed |
| More supplies = faster march (`army_speed_w_supply`) | A heavier carried load = slower march; supplies below 5 days drag the pace |
| No interception | A supply line is CUT on any day an enemy regiment stands near its road |
| Morale reads the stores once a month | Unchanged above 5 days; below 5 days and at 0 days morale falls every day |

## 2. Ontology and state

### 2.1 State (`GameState`, saved)

| Field | Shape | Meaning |
|---|---|---|
| `town_stock` | `burg -> {crown, lord, house}` | strategic goods held in the town, in the same measure as `metrics.strategic` (gold value). `crown` = the crown's tax in kind, `lord` = the player-lord's own goods, `house` = the holding house's goods, which the crown may BUY (§3.3) |
| `regiments[code].supplies` | int | unchanged: whole supply units (`supply_use` per month). DAYS in hand = `supplies × 30 / supply_use`, derived, never saved |
| `regiments[code].carry_days` | int | the standing carried-load order, one of `data/army_carry_loads.csv`'s rows (10/15/20/25/30) |
| `supply_lines` | `code -> {town, rate_permille, courier_id, state, ready_day, cut_at_m, fee_milli}` | one line per regiment at most, created when the order is given. `state` ∈ `ordered` (the courier is on the road), `riding` (the first wagons are), `flowing`, `cut`. `fee_milli` carries the cartage remainder (§3.4) |

`metrics.strategic` / `lord_strategic` stay as the top bar and every reader
sees them, but are written only as the sum of `town_stock[*].crown` /
`[*].lord` (one function, `TownStores.sync_metrics`), so nothing that reads
them changes.

### 2.2 Derived (never saved)

- **Catchment**: every manor of a province belongs to the NEAREST burg of
  the same province (straight-line from the manor's cell centre to the
  burg, ties to the burg code that sorts first). A province with no burg
  sends its goods to the nearest burg of its kingdom. Built once per load
  (`TownStores.catchment`), rebuilt when `manor_province`, `manor_owner` or
  `province_owner` changes (the same trigger `RealmEconomy`'s index uses).
- **A town of the realm** is a burg whose province the player's kingdom
  holds now (`MapOwnership`), whatever house holds it.

### 2.3 The LEDGER

```
manor ──stocks──▶ town ──dispatches──▶ supply_line ──supplies──▶ regiment
                   ▲
     house ──sells_to── town        (the house stock, bought for gold)
```

`data/ledger_link_types.csv`:

- NEW `stocks` (manor → town, `flow`, economy|war|all): the manor's monthly
  strategic goods landing in its catchment town.
- NEW `dispatches` (town → supply_line, `flow`, war|all, governor
  `marshal`): replaces `supplies_in`.
- NEW `sells_to` (house → town, `flow`, economy|war|all): drawn only when
  the month bought from that house (§3.3).
- RETIRED `supplies_in` (strategic_goods → supply_line): the goods now come
  from a named town, not the pool.
- `supplies_out`, `governs_supply`, `skims_supply` unchanged.

`data/ledger_object_types.csv`: a `supply_line` instance exists only for a
regiment that HAS a supply point (it was one per land regiment). A `town`'s
card gains its stores and its lines (§5.4).

## 3. The rules

### 3.1 The month: goods into the towns

At the month's settlement (`TickEngine._settle_economy`), each manor's
strategic gold (`ManorEconomy.line_of`'s `strategic`) lands in its catchment
town instead of a realm pool, split by the purse rule of
`MANOR_SYSTEM.md` §5c:

- a manor in a province the crown CONTROLS: all of it to `lord`;
- any other manor of the realm: `crown_share_permille` of it to `crown`
  (the tax in kind), the rest to `house`.

Every other strategic inflow (the war workshop's output, an order that adds
strategic goods) lands in the town of its manor, or in the capital's
stores when it has no manor. Every outflow that today debits a pool
(GOODS_SELL, building inputs) debits the towns in burg-code order, crown
before lord as today's pool rule. After the settlement `sync_metrics`
rewrites the two metrics. Regression guard: the sum of the towns'
`crown + lord` after a month equals what the two pools would have held.

`house` stock is capped at `town_house_stock_months` months of its own
inflow so it does not grow without bound (the house sells the rest
elsewhere).

### 3.2 The day

Inside `TickEngine.advance_day`, after the columns march and the couriers
ride, BEFORE the host eats:

1. **Line states.** An `ordered` line whose courier delivered today becomes `riding`
   with `ready_day` = today + the wagons' road days
   (`CourierSystem.days_for` at `supply_wagon_km_per_day`). A `riding`
   line whose `ready_day` has come becomes `flowing`.
2. **Interception.** For each `flowing` or `cut` line: walk its road route
   (§3.5); if any point lies within `supply_cut_reach_m` of a regiment of a
   kingdom whose stance toward the player is `Enemy` (`diplomacy.csv`; a
   later war state joins the same test), the line is `cut` today and
   `cut_at_m` is that point; otherwise `flowing`. A cut line draws
   nothing and pays nothing. No rerouting.
3. **Delivery** (each `flowing` line): `send = day_use × rate_permille / 1000`,
   capped so the regiment ends no higher than 30 days after the day's
   meal. It is drawn from the town (§3.3); what arrives is
   `drawn × (1000 − loss_permille) / 1000` (`SupplySystem.loss_of`, the
   road's length, unchanged rule). Cartage is charged (§3.4).
4. **Town refill.** A land regiment standing in a town of the realm
   (`ArmySystem.town_of` + held) is topped up to its `carry_days` from that
   town, drawn as §3.3, with NO cartage and no road loss. A regiment both
   in a town and with a line takes the town first.
5. The host eats (`ArmySystem.eat_day`, unchanged).

A regiment in the field with no line eats what it carries. Nothing else
refills it.

### 3.3 Drawing from a town

Draw order: `crown`, then `lord`, then BUY from `house` at its gold value ×
(1000 + `supply_buy_markup_permille`) / 1000, paid from the treasury, the
holding house named in the reason (`"bought supplies from House X at Y"`).
When the treasury cannot pay, the purchase stops there. A town that runs
dry delivers what it has.

### 3.4 Cartage

Each day a `flowing` line accrues
`drawn_units × length_km × supply_cart_fee_permille` milligold into
`fee_milli`; whole gold is taken from the treasury the day it crosses a
whole number, the remainder carried (one rounding, invariant 11). So 1.2×
costs a fifth more than 1.0× and 0.8× a fifth less, and a longer road costs
more. The courier that sets up the line is charged as any courier is.

### 3.5 The line's road

The route is the road path from the town to the regiment's position today
(`SupplySystem._path_from_ctx`, one shortest-path tree per day for all
lines), re-aimed every day as the column moves, as a courier's last leg is.
A supply point is ELIGIBLE when the town is a town of the realm and the
wagons' road days to the regiment are ≤ `supply_point_max_days`. A line
whose regiment marches out of range stays, its cartage and loss growing
with the road; a line whose town leaves the realm is CANCELLED that day.

### 3.6 Carried load and pace

`data/army_carry_loads.csv`: `days, pace_permille, label` (10 … 30; the
heavier, the slower; 30 days ≈ −15%). `ArmySystem.speed_km_per_day`
multiplies its row in. `army_speed_w_supply` is redefined: the supply term
is 1000 at ≥ `army_supply_low_days` (5) days in hand and falls linearly to
0 at 0 days, so only a hungry column is slowed by hunger.

### 3.7 Morale

Above `army_supply_low_days` days the monthly drift stays as it is
(`morale_mark` reads days: `army_morale_fed` at ≥ 5 days). Below it, every
day: morale −`army_morale_hungry_day`; at 0 days −`army_morale_starving_day`
instead, each with a reason line. `host_hungry` reads days < 5.

## 4. Orders

Ordinary actions with signatures and `order_costs.csv` rows (the courier
fee is the explicit cost):

| Action | Params | The courier rides to | Takes effect |
|---|---|---|---|
| `SUPPLY_POINT_SET` | regiment, town, rate (800/1000/1200) | the town | on delivery the line goes from `ordered` to `riding`; it flows when the wagons arrive. Replacing a point cancels the old line on delivery |
| `SUPPLY_POINT_CLEAR` | regiment | the town | the line ends on delivery |
| `SUPPLY_CARRY_SET` | regiment, days | the regiment | on delivery |

Refused: an ineligible town, a fleet, a regiment of another kingdom. All
three are paused-clock orders on the map, as a march is
(`army_route_orders.csv` `paused_only`).

## 5. What the player sees

### 5.1 The right-click menu (`ArmyOrderMenu`)

New rows from a new table `data/army_supply_orders.csv` (same shape as
`army_route_orders.csv`): **Add supply point…** (**Change supply point…**
when it has one), **Withdraw supply point**, **Carry ▸ 10 / 15 / 20 / 25 /
30 days** (the current one ticked).

### 5.2 Picking the point

Pick mode: eligible towns lit; ineligible ones greyed with the reason on
hover ("wagons need 13 days, the most is 10"). Hovering a lit town previews
the road route (dashed) with its length, wagon days, road loss, the 1.0×
daily cartage and how many days of this regiment the town's stores hold.
A click opens the confirm menu: the three rates, each with its daily
cartage, and the courier's days → Confirm / Cancel. Esc leaves pick mode.

### 5.3 The line on the map

A new layer `scripts/map3d/map3d_supply_lines.gd`: for each of the
player's regiments with a `flowing` line, a thin, translucent, desaturated
ribbon along the road from the town to the column. `ordered`, `riding` and `cut` lines
are not drawn (the regiment card and the missives say why). Its look is a
`.tres` material with `@export`ed fields, built and judged through the
`visual-review` skill. The WAR ROOM's supply ink (`war_intel_ink.gd`)
reads the same lines.

### 5.4 Cards

- **Regiment card**: a supply block — days in hand against the carried
  load (bar), and "Supply point: X · 1.2× · 3 gold a day" / "No supply
  point" / "Wagons arrive in 2 days" / "Cut near Y".
- **Town card**: its stores (crown / lord / house), the lines it
  dispatches, and how many days its stores hold at today's draw.

### 5.5 Missives (`MissiveLog`, a new `supply` kind)

- **Dispatches** (one letter a day gathering every event of that day):
  line opened, line cut (where, by whom), line restored, a supply town
  holds under `supply_warn_town_days` days of its lines' draw, a regiment
  under 5 days, a regiment out of supplies, a line cancelled because its
  town was lost.
- **The marshal's monthly report**: one row per regiment — days in hand,
  carried load, point, rate, road km, the month's cartage, road loss,
  goods bought and from whom. It is the marshal's CLAIM (skimming and the
  audit as `2026-09-30-ledger-governors-design.md`).

## 6. Data

`balance.csv` new keys: `army_start_supply_days`, `army_supply_low_days`
(5), `army_supply_max_days` (30), `army_morale_hungry_day`,
`army_morale_starving_day`, `supply_wagon_km_per_day`,
`supply_point_max_days`, `supply_cut_reach_m`, `supply_cart_fee_permille`,
`supply_buy_markup_permille`, `supply_warn_town_days`,
`town_house_stock_months`, `army_carry_default_days` (20).
Retired: `army_start_supply_months`, `army_supply_target_months`,
`army_speed_supply_full_months`. `army_supply_gold_permille` stays (a supply
unit's gold value). New tables: `army_carry_loads.csv`,
`army_supply_orders.csv`. Values are tuned in the plan, not here.

**Old saves** load with no supply lines, `carry_days` =
`army_carry_default_days`, supplies clamped to 30 days, and the two pool
metrics split into the towns by each town's share of last month's inflow
(the capital takes the rounding).

## 7. Code

- NEW `scripts/engine/town_stores.gd` (`TownStores`): catchment, the
  month's deposit, `draw(town, units)`, `sync_metrics`.
- `scripts/engine/supply_system.gd`: `plan()` / `settle_month()` become the
  daily `day_step()` and a read-only `plan()` for the cards and the LEDGER;
  `stronghold_of` retired.
- `scripts/engine/army_system.gd`: carried load in the pace, the supply term
  in days, the daily morale penalty.
- `scripts/engine/action_system.gd` + signatures: the three orders;
  `CourierSystem` gains the town as a destination.
- `scripts/engine/missive_writer.gd`: the dispatches and the monthly report.
- LEDGER resolvers: `stocks`, `dispatches`, `sells_to`.
- UI: `army_order_menu.gd` rows and pick mode, the regiment and town cards,
  the new map3d layer, `war_intel_ink.gd`.

## 8. Tests

GUT, expected values hand-computed first (root `CLAUDE.md`):
catchment (nearest burg, ties, a burgless province, rebuild on a move); the
month's deposit and the regression of the pool sums; the draw order and a
house purchase's gold; cartage accrual and its carried remainder; road loss;
the 30-day cap; the line states `riding → flowing`, cut and restored, and
cancellation when the town is lost; the carried load's pace and the
below-5-days drag; the daily morale penalties; a save round-trip of the new
state, and an old save's migration. UI through real input: right-click →
Add supply point → lit towns → click → confirm.

## 9. Not in this spec (the brief's other items)

- **D** — split the starting army into ~40 units of 300–1000 men (item 14).
- **C** — the LAWS tab (economy / politics / military), each law sent by
  courier, the military code and chivalry (items 10–13).
- **B** — foraging and plunder in enemy land, desertion at home (items 8–9).
