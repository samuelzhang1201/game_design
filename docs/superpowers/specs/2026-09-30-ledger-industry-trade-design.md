# LEDGER M5 + M6 — raw materials, artisans, markets and trade routes — design

Status: designed 2026-09-30 overnight under the owner's standing order (see
`2026-09-30-ledger-supply-design.md`). Both are IN the MVP (owner
2026-09-30: "整个mvp必须要有全部游戏体验"). **Default** marks each choice the
owner has not ruled on, with its cost if wrong. Charter:
`2026-09-30-ledger-ontology-design.md` §8 (M5, M6). Needs M3 (a trade
route is a governed flow).

**Built 2026-09-30 (branch `ledger-supply`)**: commits `33be2f1`..`b010eed`;
`tests/engine` 900/900 for this pair alone, the whole suite 1644/1643 (the
one known pre-existing `test_map3d_layers.gd` failure only). Controller
rulings made during the build, each one superseding the **Default** it
replaces:

- **An idle building gives NOTHING while idle** — no goods, no bonus, no
  per-tick effect (a starved smithy's own output bonus lapses along with its
  tools; "no iron, no work"). A waking building is billed only its
  SHORTFALL (`IndustrySystem.own_supply`, walking the manor's input
  buildings in the same sorted code order as `line_of`), never its whole
  need.
- **Only manors the crown's own house holds** buy and idle through the lord
  (`IndustrySystem.buildings`, exactly like `WorkshopSystem.cells`); a
  building on any other house's manor still eats its own manor's units in
  its line and is never billed or idled by the lord.
- **An empty Master of Works seat reads `Governance.factors`'s own floor**
  (`min_permille` 600) like every other governed flow, never an unscaled
  1000‰ — implemented once the other way and reversed, because
  unscaled-while-vacant would let appointing a poor Master of Works make the
  artisans SLOWER than having no one in the office, which no appointment
  should ever do. Since `Governance.factors` already clamps a seated
  governor's efficiency to `[600, 1000]`, this holds for free: nobody's
  artisans ever run slower than the vacant-seat pace.
- `data/ledger_governance.csv` gained a `books` column (1 for `workshop`,
  `supply_line`, `trade_route`; 0 for `works`): `LEDGER_AUDIT` refuses a
  flow with no books ("The building works keeps no books to audit"), while
  `GOVERNOR_SET` still reassigns it — the master of works cannot be
  audited until his skim exists.
- **A trade route counts only deals whose SELLER is a realm market** — a
  town's own sale into a market is domestic supply, not export, so losing a
  home TOWN never raises the tolls (losing the MARKET itself still does,
  since its exports move abroad). Losing a non-market realm province still
  raises the tolls modestly (measured 240 → up to 271 on the beria fixture),
  because that province's towns become foreign buyers of the realm's
  remaining markets, which is a real export; accepted, not fixed — the
  owner may rule otherwise.
- **A market offers no "Sell here"**: on this pack selling at a market never
  beats the flat factor, so pricing guards against a round-trip arbitrage
  instead of following the plan's "buy at basket, sell at basket" rule
  literally — buying at a market costs at least the flat sell price (never
  cheaper than `max(basket, factor's selling price)`), and selling at a
  market pays at most the cheapest purchase anywhere in the realm
  (`min(basket × (1 − spread), the realm's cheapest buy)`); no sale ever
  pays more than any purchase costs. The toll floors once:
  `value × toll_permille × efficiency / 1,000,000`.
- **`trade_toll_permille` is 250, not the 50 first written below** — the
  50‰ default gave tolls of only 47 gold against 1,961 of tax (2.4% of the
  crown's treasury tax, well under the brief's 5% floor and the Azgaar
  export's deal values run small); following the brief's Step 6 formula
  (`round(50 × 0.12 / 0.024)`) brings it to 250‰, which pays 240 gold of
  tolls against the same 1,961 (12.2% — ≈15% was the target, near enough on
  this pack). The six opening routes at 250‰: brackmoor 35, corwyn 35,
  farhold 107, irongate 12, valmoor 11, yorwald 40.

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
  waking building is billed only that shortfall (fix round 1). When a whole
  CHAIN wakes together (a mine shaft, a smithy and an armoury all idle,
  then all paid the same month), the downstream building's first month may
  still BUY an input its upstream makes that same month — `line_of` reads
  last month's idle set to decide what an about-to-wake building fed the
  manor, so the armoury cannot yet see the smithy's own tools this month —
  a one-month overbill, ACCEPTED (final fix wave, Minor1): the chain reads
  true from its second month on.
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

- A **trade route** is the aggregate of every deal a realm MARKET sells to a
  buyer outside the realm, grouped by the buyer's kingdom (a town's sale into
  a market supplies that market, domestic, never tolled — Task 3 review
  ruling: counting towns made losing a province RAISE the tolls):
  `trade_route:<kingdom>`. `MarketSystem.routes(repo, state) -> Array[{kingdom,
  gold, deals}]` sums `units × price` a month (the export's units are a
  month's — **Default**, as its `production.csv` is) — cached by the
  ownership signature, since a conquest moves markets and buyers.
- **Toll**: the crown takes `trade_toll_permille` (250, calibrated in the
  build — see the Status line above) of each open route's monthly value
  into the TREASURY at the settlement (ledger line "tolls on the trade with
  X"). Governed by the STEWARD (M3 flow type `trade_route`: efficiency
  scales the toll, a venal steward skims it, reports it whole).
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
  domestic market is `full`; a route's export value is the crown's own
  customs count, not the buyer's book — so the toll derived from it is
  shown EXACTLY, never as words.
- Actions: `trade_route` → Close / Open (`TRADE_ROUTE_SET`), audit and
  reassign (M3); `market` → Buy there (civil and strategic). Not Sell: on
  this pack selling at a market never beats the factor's flat price (Task 3
  review ruling; the engine's GOODS_SELL still takes a `market` param).
  The toll floors once: value × toll‰ × efficiency‰ / 1,000,000. The works
  (the flow `works`) keep no books: `ledger_governance.csv` `books` 0, and
  LEDGER_AUDIT refuses them; they are governed on the LEDGER as
  `governs_works` → the artisans.

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
