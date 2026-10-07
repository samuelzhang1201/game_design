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

**Status: BUILT 2026-10-07 on feat/army-supply-lines (not yet merged); the look of the line awaits the owner's ruling.** Design APPROVED in chat 2026-10-07 (owner, section by section). The owner's answers, in order:
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
| `town_stock` | `burg -> {crown, lord, house}` | strategic goods held in the town, in whole SUPPLY UNITS (`army_supply_gold_permille` is a unit's gold). `crown` = the crown's tax in kind, `lord` = the player-lord's own goods, `house` = the holding house's goods, which the crown may BUY (§3.3) |
| `regiments[code].supplies` | int | unchanged: whole supply units (`supply_use` per month). DAYS in hand = `supplies × 30 / supply_use`, derived, never saved |
| `regiments[code].carry_days` | int | the standing carried-load order, one of `data/army_carry_loads.csv`'s rows (10/15/20/25/30) |
| `supply_lines` | `code -> {town, rate, state, order_id, ready_day, cut_x_m, cut_y_m, cut_by, fee_milli, buy_milli, arrive_milli, claim_milli, skim_milli, m_* month counters, pending?}` | one line per regiment at most, created when the order is given. `state` ∈ `ordered` (the courier is on the road), `riding` (the first wagons are), `flowing`, `cut`. The `*_milli` fields carry the cartage, purchase, road, efficiency and skim remainders (§3.4); `pending` holds a replacing point still on its way |

`metrics.strategic` / `lord_strategic` stay as the top bar and every reader
sees them, but are written only as the gold of the sum of `town_stock[*].crown` /
`[*].lord` units (one function, `TownStores.sync_metrics`; a writer that moves a metric elsewhere is absorbed by `TownStores.reconcile`), so nothing that reads
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
(GOODS_SELL, building inputs) still moves the metric, and `reconcile` takes the fall from the towns in proportion to their stock. After the settlement `reconcile` and `sync_metrics`
rewrite the two metrics. Regression guard: the sum of the towns'
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
`drawn_units × length_km × supply_cart_milligold_per_unit_km` milligold into
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
instead (`ArmySystem.hunger_day`, after the host eats). The dispatch of the day says which regiments ran low or empty; a regiment's morale has no reason log of its own (see the rulings below). `host_hungry` reads days < 5.

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

Pick mode: eligible towns lit; ineligible ones greyed, and a click on one
says why in the news bar ("wagons need 13 days, the most is 10"). A click on
a lit town previews the road route (dashed) and opens the confirm menu: the
three rates, each with its daily cartage, and on each row's tooltip the road's
length, road loss, wagon days, how many days of this regiment the town's stores
hold, and the courier's days → Cancel. Esc leaves pick mode.

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
- Supply letters keep their own count (`missive_keep_supply`) so they never evict a spy's report or a receipt.
- **The marshal's monthly report**: one row per regiment — days in hand,
  carried load, point, rate, road km, the month's cartage, road loss,
  goods bought and from whom. It is the marshal's CLAIM (skimming and the
  audit as `2026-09-30-ledger-governors-design.md`).

## 6. Data

`balance.csv` new keys: `army_start_supply_days`, `army_supply_low_days`
(5), `army_supply_max_days` (30), `army_morale_hungry_day`,
`army_morale_starving_day`, `supply_wagon_km_per_day`,
`supply_point_max_days`, `supply_cut_reach_m`, `supply_cart_milligold_per_unit_km`,
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

## 8a. Implementation rulings

Made while building (2026-10-07); each is a default the owner may overturn, with what it costs if wrong.

The plan's three, approved with it:

- Stores are in supply UNITS, the pool's gold rounded down once over the whole pool. If wrong: the stores would be counted in gold and a unit's price could not move without rewriting every town.
- `reconcile` takes a fall in the metrics from the towns in proportion to their stock, not in burg-code order. If wrong: the first towns by code would drain first.
- The route preview shows on a CLICK of a lit town, not on hover. If wrong: a hover preview must be added to the pick mode.

From the build:

- Daily morale loss has no reason line: regiment morale has no reason log anywhere in the engine (invariant 4 covers opinions and owner moves); the day's dispatch letter says the regiment is low or empty. If wrong: a morale reason log added later.
- A lost town's stores are lost with it (reconcile erases entries that are no longer realm towns). If wrong: captured stores could instead be returned to the depot.
- A realm with no town keeps no strategic stores (a rise with no depot to land in is dropped). If wrong: an event's gold vanishes in that edge case, where the game has no realm left to play.
- An extra `TownStores.reconcile` runs after the workshops and the market in `TickEngine.advance`, so any other writer's move on the two metrics is settled into the towns. If wrong: one redundant call.
- `TownStores.seed` is named `seed_from_pools` (it shadowed GDScript's global `seed()`). If wrong: nothing.
- A CLEAR arriving while a NEWER SET is pending turns the line into that SET's ORDERED record instead of erasing it (the player's last order wins). If wrong: the newer order would be lost.
- `CourierSystem.pending_for` ignores SUPPLY_* couriers (it is the march / halt reader); headlines and the courier card name the town for a town-bound courier. If wrong: a supply courier is not shown as the regiment's pending order anywhere.
- A pending SET that replaces a running line carries the old line's month counters forward (the marshal's report is per regiment). If wrong: a replaced line's month would start from zero in the report.
- Per-day flooring of road loss, efficiency and skim is replaced by milli-unit carries on the line (`arrive_milli`, `claim_milli`, `skim_milli`), so the month's truth matches `plan()`. If wrong: nothing; it is more exact.
- Daily treasury debits (cartage, house purchases) stay DAILY, as the owner asked; their reason and record is the marshal's monthly report, and in-town refill purchases are counted on the regiment's entry. If wrong: the month's `TickReport` has no line for them; the owner may want monthly ledger lines.
- PARKED for the owner: cartage may push the treasury below zero (purchases stop at zero; salaries already do). If wrong: a broke crown keeps paying carters.
- An ORDERED line whose own courier is gone but whose pending SET courier rides is promoted, not purged. If wrong: none.
- The low and empty warnings move after the host eats (`SupplyLines.warn_day`, called by `TickEngine` after `eat_day` and `hunger_day`), so they read what the regiment really has left. If wrong: none.
- Supply letters (`supply`, `supply_month`) get their own keep count (`missive_keep_supply`) in the credible column and never evict other kinds, since spy reports and receipts feed Intel and `ManorBars`. If wrong: one balance key.
- The marshal's report adds road loss per cent to each row and a fact per house bought from (§5.5). If wrong: none.
- A line erased mid-month folds its month counters into the regiment's entry so its skim is banked and its cartage reported; the skim's sub-gold fraction carries over. If wrong: none.
- The burg card's stores sit in `fields` (no icon), because adding `stats` would hide every burg field in `map_detail_panel`. If wrong: an icon-less row on the town card.
- Supply rows are not offered in the war room (its orders are drafts, the spec asks for supply orders from the map). If wrong: the owner cannot pencil supply points in the war room.
- One formula for the daily cartage estimate (`SupplyLines.day_fee_estimate`) and the stock days (`TownStores.days_of_stock`), used by the rate menu and the regiment card. If wrong: none.
- The four looks `scenes/map3d/materials/lines/supply_{line,pick,pick_off,preview}.tres` were written by the engine (a one-off headless script), not hand-edited text or the editor. If wrong: the editor may re-save them once to settle UIDs.
- Accepted deviations of the map layer: the pick ring's radius is the town's click reach (not the cut reach); the line is snapped onto the drawn road; its end follows the drawn piece; `bind()` takes the units layer. If wrong: none.
- Route searches are cached per line per day, end-following redraws are throttled by `map3d_supply_follow_s`, and pick or preview changes redraw only the rings and the preview. If wrong: the line's end lags the piece by up to the throttle.
- OWNER TO RULE: the supply line's look (white, alpha 0.15, 22 px, fully soft; preview white dashes; gold lit rings reusing the selection gold; grey greyed rings). If wrong: the `.tres` values change, nothing else.
- Whole-unit supplies are rounded UP where a day count is promised (a new regiment's `army_start_supply_days`, a town refill to `carry_days`), so a fresh or topped-up regiment reads 20 days in hand of 20, never 19. If wrong: none.
- The Missive desk scrolls its facts (a `ScrollContainer` round `LetterFacts` in `missive_screen.tscn`): the marshal's report has a row per land regiment and ran off the window. The scene was patched as text, because the editor MCP drives the main checkout. If wrong: the editor may re-save the scene once.
- PARKED for the owner (tuning): at `supply_cart_milligold_per_unit_km` 1 the cartage of one regiment is under a gold a day, so the rate menu's rows (0.8 / 1.0 / 1.2) all read "0 gold a day" and the three speeds cost the same in whole gold. If wrong: raise the key (about 10 puts a 1,600-man regiment on a 140 km road near 7 gold a day).
- "Play it" was verified by real-window snapshots of the cards, the menu and the Missive board, not by clicking through the live game. If wrong: an interaction bug only a human click finds.
- main's marks and hazards (war-room P2) take their share of a supply line's road daily: `SupplyLines.day_step` reads `SupplySystem.road_loss` (brigands, pirates, active hazards on the town→regiment road) once a line a day and thins the delivery by `total_loss`; `line_of`, `plan()`, the rate menu and the marshal's report (which names the robbers) read the same loss. If wrong: none.

## 9. Not in this spec (the brief's other items)

- **D** — split the starting army into ~40 units of 300–1000 men (item 14).
- **C** — the LAWS tab (economy / politics / military), each law sent by
  courier, the military code and chivalry (items 10–13).
- **B** — foraging and plunder in enemy land, desertion at home (items 8–9).
