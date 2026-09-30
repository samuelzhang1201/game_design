# LEDGER M5 + M6 — raw materials, artisans, markets and trade routes — design

Status: designed 2026-09-30 overnight under the owner's standing order (see
`2026-09-30-ledger-supply-design.md`). Both are IN the MVP (owner
2026-09-30: "整个mvp必须要有全部游戏体验"). **Default** marks each choice the
owner has not ruled on, with its cost if wrong. Charter:
`2026-09-30-ledger-ontology-design.md` §8 (M5, M6). Needs M3 (a trade
route is a governed flow).

## M5 — buildings eat, artisans build

### What changes

Today a building makes goods out of nothing (`produce_good` /
`produce_units`), so a smithy forges tools with no iron. After M5 a
building that transforms goods EATS its inputs, and the chain the owner
sketched ("工人--修筑--》建筑") becomes real both ways: artisans raise
buildings faster, and a workshop building works only while it is fed.

### Inputs

`data/building_inputs.csv` — `building_code, good_code, units` (units a
month for one standing building). **Default** rows (only buildings whose
`notes` already say they transform something):

| building | eats | makes (existing) |
|---|---|---|
| smithy | iron 3 | tools 3 |
| armoury | tools 1, iron 2 | arms 3 |
| tannery | cattle 2 | leather 3 |
| loom | sheep 2 | cloth 4 |
| brewery | grain 4 | beer 5 |
| shipwright | wood 10, ropes 2 | ships 1 |
| war_workshop (M2) | none — it converts pools, not units | — |

### How a building is fed

- **From its own manor first.** In `ManorEconomy.line_of` — still THE only
  rounding (invariant 11) — a building's input is netted against the
  manor's own units of that good this month (a mine-shaft manor with a
  smithy feeds its own forge): `own = min(units[good], need)`, and
  `units[good] -= own`.
- **Then from the lord's stores.** What the manor cannot supply is bought
  from the LORD's pool of that good's `goods_economy.csv` pool (civil or
  strategic) at its `price_gold`, at the month's settlement
  (`IndustrySystem.settle_month`, right after `_settle_economy`, before the
  workshops). Ledger line: "the lord's workshops buy their iron".
- **In a fixed order.** Input buildings on one manor eat in SORTED
  building-code order (an armoury before a smithy), so a manor short of a
  good feeds the first in that order; `IndustrySystem.own_supply` walks the
  same order to estimate what an IDLE building's manor could give it, and a
  waking building is billed only that shortfall (fix round 1).
- **Only the lord's.** Only buildings on manors the crown's own house holds
  buy and idle through the lord (`IndustrySystem.buildings`, like
  `WorkshopSystem.cells`); one on another house's manor still eats its own
  manor's units in its line and works as the pack's economy counts it.
- **Unfed, it idles.** A building whose remaining need the pool cannot pay
  is IDLE next month: `GameState.idle_buildings` (cell → codes, saved,
  rebuilt every settlement) and `line_of` skips an idle building's output.
  The card's slot shows it ("idle: no iron"); the news bar says it once.
  An idle building gives NOTHING while idle — no goods and no bonus (its
  tax, output, defence and church bonuses and its *_per_tick effects lapse;
  controller ruling). The month's settlement reads the idle set of the
  month it settles, but the per-tick effects (church, contentment, unrest)
  are applied after the tick turns and so read the NEW month's idle set —
  accepted: they are the new month's effects.
- `IndustrySystem.plan(repo, state) -> Array[{cell, code, good, need,
  own, bought, gold, fed}]` is the pure function the tick and the LEDGER
  read.

### Artisans

- The artisans of a province are its URBAN population
  (`economy.provinces.<code>.urban_population`, the figure the ration
  already reads). A work in progress in a manor advances
  `1000 + min(artisan_speed_cap_permille, urban / artisan_per_step ×
  artisan_step_permille)` per mille of a day each day (**Default**: 500 cap,
  a step of 50‰ per 2,000 townsfolk) — whole permille accumulated in
  `manor_works` (saved), so `build_days` still states the time at no
  artisans. The card's works row says "artisans of X: +N%".
- The master of works governs `builds` (an M3 governed flow: efficiency
  scales the artisan bonus; a venal master's skim takes part of each build's
  civil cost — reported whole, found by audit).
- **Controller ruling 2026-09-30 (Task 2)**: the Master of Works seat is
  never filled by `GameState.new_campaign` (`data/founding_council.csv` and
  `data/roles.csv` name no one to it), so the flow reads VACANT on every
  fresh campaign. `work_speed_permille` reads `Governance.factors(repo,
  state, "works")["efficiency"]` exactly as every other governed flow does
  — an empty seat gives the row's `min_permille` (600), the same floor a
  seated governor's own efficiency is clamped to. This was implemented once
  as "unscaled (1000) while vacant" and then reversed: unscaled-while-vacant
  would let appointing a poor Master of Works (low skill, low opinion) make
  the artisans SLOWER than having no one in the office at all, which no
  appointment should ever do. `tests/engine/test_artisans.gd` holds this
  structurally (every skill/opinion combination clamps to at least the
  vacant seat's speed).

### The ontology

- `raw_material` is retired as a separate type: a raw material is just a
  GOOD. The link `consumes` becomes building → good_pool (civil_goods or
  strategic_goods, by the good's pool; flow = gold bought), plus a manor's
  own feed drawn on its card. `artisans` is a live type (instances
  `artisans:<province>` for controlled provinces), `builds` artisans →
  building (flow = the speed bonus in permille).

## M6 — markets and trade routes

### What changes

The pack already carries 27 markets and 10,815 trade flows (`deals.csv`:
seller market or town → buyer town or market, good, units, price, tax),
imported and read by nothing. After M6 they are the realm's **trade**:
goods flow across its borders along trade routes, the crown takes a toll,
and a route is a lever (open or close it) and a weak point (a hostile
neighbour's route can be closed on you — enemy AI waits for sub-project C).

### Markets

- A **market** is a pack market; the realm's markets are those whose
  `center_burg` lies in a province the realm holds NOW (live ownership).
- `GOODS_BUY` / `GOODS_SELL` gain an optional `market` param: trading at a
  realm market uses THAT market's price for the pool's basket
  (`MarketSystem.basket_price(market, pool)`: the stock-weighted mean of its
  `market_goods` prices over the goods of that pool, relative to their
  `price_gold`) instead of the flat spread. **Default**: without a market
  param the old flat trade stays (the order menus keep working).

### Trade routes

- A **trade route** is the aggregate of every deal between a realm market
  (or town) and a buyer outside the realm, grouped by the buyer's kingdom:
  `trade_route:<kingdom>`. `MarketSystem.routes(repo, state) -> Array[{kingdom,
  gold, deals}]` sums `units × price` a month (the export's units are a
  month's — **Default**, as its `production.csv` is) — cached by the
  ownership signature, since a conquest moves markets and buyers.
- **Toll**: the crown takes `trade_toll_permille` (50) of each open route's
  monthly value into the TREASURY at the settlement (ledger line "tolls on
  the trade with X"). Governed by the STEWARD (M3 flow type `trade_route`:
  efficiency scales the toll, a venal steward skims it, reports it whole).
- **Open / closed**: `GameState.closed_routes` (kingdom codes, saved) and an
  order `TRADE_ROUTE_SET {kingdom, open}`. Closing a route costs its toll
  and the realm's merchants' goodwill (the guildmaster character's opinion,
  `trade_close_opinion` −6, with its reason), and shifts that kingdom's
  relationship when diplomacy exists (**Default**: a no-op hook until
  diplomacy is state; the order's card says so).

### The ontology

- `market` and `trade_route` become live types (instances `market:<id>`,
  `trade_route:<kingdom>`); `trades` market → civil_goods / strategic_goods
  (flow = the market's value a month in that pool), `routes` trade_route →
  gold (flow = the toll), `governs` extended to trade routes. Accounts: a
  domestic market is `full`; a route's foreign side is `basic` (words) —
  the crown knows its own toll, not what the buyer pays.
- Actions: `trade_route` → Close / Open (`TRADE_ROUTE_SET`), audit and
  reassign (M3); `market` → Buy / Sell there.

## Tests

M5: hand-computed feeding (own first, then bought, then idle), the idle
building's output removed from `line_of`, invariant 11's one rounding kept,
artisan speed and its cap, determinism, save round-trip. M6: the realm's
markets by live ownership, routes' sums on a fixture, toll and closing,
basket price, the ledger's new links, save round-trip.

## Out of scope

Prices that move with supply and demand (the export's prices stay fixed),
foreign closure of the crown's routes (sub-project C), naval trade's ships,
market buildings' effect on a market (the `market` building keeps its
existing bonus).
