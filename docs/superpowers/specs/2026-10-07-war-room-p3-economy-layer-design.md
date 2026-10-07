# WAR ROOM P3 — the economy layer: what feeds a war, and living off the land — design

Status: written 2026-10-07 at the owner's request ("开始做P3，写spec"), the
owner having said for the night "不要问我问题，按照你的推荐做": every choice
below is the recommended one, and §0 lists them so a ruling can overturn any
single one. Builds on P1 (`2026-10-07-war-room-scale-hover-design.md`: the
10° sheet, fine print, the hover slip `WarGround`) and P2
(`2026-10-07-war-room-p2-tactical-layer-design.md`: marks, hazards).

## 0. The request, the survey and the recommended rulings

P1's survey of the Azgaar export named P3 as the economy: "strategic goods
by place (`production.csv` with the goods' `military` tag), foraging from
the markets' food stocks and prices, the trade flows (`deals.csv`) summed
onto the roads". P2 left "mines and inns feed P3".

What the code has today:

- `economy/production.csv` (5,061 rows on beria) is the manor economy's
  source: `ManorEconomy.line_of` values a manor's units by
  `data/goods_economy.csv` (`pool` strategic | civil, `price_gold`), so a
  manor's **strategic goods** are already live gold a month, and the crown's
  share feeds the army's supply. Nothing shows WHERE they are made on the
  war table.
- `economy/markets.csv` (27 markets), `market_goods.csv` (stock and price
  per market) and `deals.csv` (10,815 deals, 1,516 seller–buyer pairs worth
  ~20 gold a month at the median, 278 at most) are `MarketSystem`'s: the
  realm's trade routes and tolls through LIVE ownership. Nothing draws a
  flow, and no market is marked on the table.
- A regiment's stores (`supplies`) are refilled only over the road from the
  capital (or a stronghold) by `SupplySystem.plan`; it eats them a day at a
  time. An army abroad never lives off the land.
- Of 684 towns, 361 make a `military`-tagged good — boots and tools are
  everywhere — so "every maker of war goods" is noise, not a map.

**Recommended rulings** (each can be overturned on its own):

1. **Two sub-projects, A then B, one spec.** **A — the war economy on the
   sheet** (read only: the works, the markets, the trade roads, and their
   lines in the slip). **B — foraging** (state and an effect: a regiment
   abroad lives partly off the land, and strips it). A draws only; B touches
   the supply settlement and the save, so it lands second.
2. **Economic geography is public** (merchants know it, as they know the
   roads): works, markets and trade roads are inked on every sheet, foreign
   or not. What a FOREIGN manor yields this month is not public: abroad the
   slip quotes the pack's production valued at the catalogue; at home it
   adds the live strategic gold `ManorEconomy` counts.
3. **Only the war works are marked, not every maker.** A town is a work when
   its strategic-pool production (pack units × `price_gold`) reaches
   `war_works_min_gold` a month. Its glyph is the family of its largest
   strategic good by gold — four families in `data/war_works.csv`: **arms**
   (arms, artillery, gunpowder, bronze, tools), **horses** (horses, camels,
   elephants, harnesses), **ore** (iron, copper, tin, saltpeter, coal),
   **naval** (ships, sails, tar, ropes, hemp, barrels). A strategic good the
   table does not list (leather, boots, wood, oil, preserved food, …) counts
   toward the threshold but gives no glyph: the town takes the family of
   its largest LISTED good, and a town with none listed is not marked.
4. **The 27 markets are marked** at their centre town with a market glyph;
   the slip names the market, whose it is now (`MarketSystem`), and its
   food price against the catalogue (a stock-weighted basket of the
   `food`-tagged goods against the catalogue price `basket_price_permille`
   uses, weighed as it weighs a pool).
5. **Trade roads are the pack's flows on the road network**, computed once
   per pack: every deal has a market on one side, so each market–town
   pair's month (Σ units × price, the same gold `MarketSystem` counts) is
   laid along the shortest road path from the market's centre town to the
   other town, and summed per road segment. A
   pair with no road path (across the sea) is not drawn. The flows are the
   world's trade; who taxes them is `MarketSystem`'s, so ownership does not
   redraw them. Drawn as the ROAD's own weight in tiers
   (`war_trade_tier_gold`), not as a new line.
6. **Foraging is abroad only, automatic, at the month's end** (B): a crown
   land regiment whose position is in a province the crown does not hold
   takes food from that province before the resupply ships. At home it
   never forages (that would be robbing the realm's own lords; an order for
   it is post-P3).
7. **The land has a capacity and remembers being stripped**: a province's
   forage a month is its towns' `food`-tagged production (pack units) ×
   `forage_supply_per_food_unit` × the season's share
   (`forage_<season>_permille`) × what is not stripped. What is taken
   strips it (`forage_strip_k`), it recovers `forage_recover_permille` a
   month; `GameState.forage_stripped` holds only provinces above 0.
   Regiments in one province share it in proportion to their need.
8. **Market stocks are not a forage source.** `market_goods.csv` is a
   snapshot the game never moves; living off the land is the land's
   production. The market's food price stays information (ruling 4).
9. **Mines and inns stay information** (P2-A marks): a mine's yield is
   already its town's production; no effect in P3.
10. **The 3D map is not touched; no new art.** The glyphs are inked like
    P2's marks (`WarMarkGlyph`); the key slip gains their entries.

## 1. Sub-project A — the war economy on the sheet

### 1.1 Data

- `data/war_works.csv`: `good_code, family, notes` — the four families of
  ruling 3. A test asserts every row's good is in `goods_economy.csv`'s
  strategic pool and every family has a glyph.
- `data/balance.csv`: `war_works_min_gold` (first draft 40 — to be set at
  visual review so a sheet shows a handful, not dozens),
  `war_trade_tier_gold` (three thresholds, `|`-separated, first draft
  `40|120|300`, a road segment's gold a month for weights 1–3),
  `war_ink_trade_px` (the extra road width per tier, ink px),
  `war_works_glyph_px`, `war_market_glyph_px`.

### 1.2 The rule (engine, `scripts/engine/war_economy.gd`, `WarEconomy`, pure)

- `works(repo) -> Dictionary` — `{burg: {gold, family, goods: [{good,
  units, gold}]}}` for every town at or over `war_works_min_gold`, goods
  largest first (ties on the code); cached per pack.
- `markets(repo) -> Array` — `[{id, burg, at}]` sorted as numbers.
- `food_price_permille(repo, market_id) -> int` — the stock-weighted price
  of the market's `food`-tagged goods against the same catalogue price
  `MarketSystem.basket_price_permille` uses, 1000 when it holds none.
- `trade_flows(repo) -> Dictionary` — `{segment key: gold}` over the road
  graph's segments (`RoadGraph`), one shortest-path tree per market
  (`RoadGraph.shortest` from its centre town — 27 trees on beria), markets
  in numeric order, each pair's gold rounded once to whole gold before it
  is summed; cached per pack (`MarketSystem.forget` clears it too).
- `trade_tier(repo, gold) -> int` — 0..3 by `war_trade_tier_gold`.
- `trade_at(repo, at) -> int` — the gold a month on the road nearest `at`
  within `army_road_reach_m`, 0 off the road.

### 1.3 Presentation

- **Sheet ink** (`WarSheetInk.strokes`): a road segment is drawn
  `war_ink_trade_px × tier` wider than a plain road; a work gets its
  family's glyph just above its town ring (`WarMarkGlyph`, the plain ink
  colour); a market's centre town gets the market glyph (a pair of
  scales) on the ring's other side. Names keep their place: the glyphs sit
  inside the town's label box (`town_label_box` grows to hold them).
- **Fine print** (`war_fine_print`): under a work's name, its top two
  strategic goods ("iron · saltpeter").
- **The slip** (`WarGround`): on a road, "Trade: about N gold a month
  passes"; at a work, "Works: iron 12, saltpeter 4 (N gold a month)" — at
  home with "(this month: N)" from the live line; at a market's town,
  "Market of X (ours | Kingdom) — food at ×0.90".
- **The key slip**: Works (arms / horses / ore / naval), Market, Trade road.

## 2. Sub-project B — foraging

### 2.1 Data

`data/balance.csv` (first draft, owner to tune): `forage_supply_per_food_unit`
30 (a median province, 9 food units, yields ~280 supply units a month at
full season — about half a 5,000-head regiment's use);
`forage_spring_permille` 600, `forage_summer_permille` 1000,
`forage_autumn_permille` 1200, `forage_winter_permille` 300;
`forage_strip_k` 500 (taking a province's whole full capacity strips 500‰);
`forage_recover_permille` 100; `forage_bare_permille` 900.

### 2.2 State

`GameState.forage_stripped: Dictionary` — province → permille stripped,
only non-zero entries, in the save (`to_dict` / `from_dict`); an old save
loads with `{}`.

### 2.3 The rule (`scripts/engine/forage.gd`, `Forage`, pure)

- `capacity(repo, state, province, tick) -> int` — ruling 7, whole units.
- `takes(repo, state) -> Dictionary` — `{code: units}` for every crown land
  regiment standing abroad (ruling 6). Its need is the plan's own shortfall
  (`target − at_end`, one helper `SupplySystem.short_of` that `plan` uses
  too); per province, the capacity shared in proportion to need (`need ×
  capacity / Σ need`, integer, codes in order, the remainder to none),
  never more than the need. "Full capacity" below is the capacity with
  nothing stripped, in this month's season.
- `SupplySystem.plan` folds it in (one plan per system): each row gains
  `forage`, and `short = max(target − at_end − forage, 0)` — so less is
  shipped, less paid, less lost on the road; the LEDGER and the card read
  the same row.
- `SupplySystem.settle_month` adds each row's `forage` to the regiment's
  `supplies` with its delivery, then `Forage.strip(repo, state, takes)`
  raises each province's stripping by `taken × forage_strip_k / full
  capacity` and recovers every province by `forage_recover_permille`
  (provinces in sorted order, clamped 0..1000, zeros erased). Returns news
  only for a province that crosses `forage_bare_permille` this month: "X
  is stripped bare; no army can live off it now." — one line per province
  per crossing.
- Determinism: integers only, sorted orders, no RNG.

### 2.4 Presentation

- **The slip** abroad on land: "Forage: rich | fair | thin | stripped (N a
  month)"; with a regiment chosen, "would feed it N of its M a month". At
  home: "Our own land — not foraged".
- **The folio's supply row**: "living off the land: N" beside the shipped.
- **The intel ink**: a province stripped past `forage_bare_permille` is
  named "Stripped" in the intel ink at its centre (the crown's own
  knowledge — its regiments did it).
- **The key slip**: nothing new (the word is self-explaining).

## 3. Tests

- A: `war_works.csv` rows are strategic goods; `works` keeps only towns at
  the threshold and names the family of the largest listed good;
  `food_price_permille` hand-computed for one market; `trade_flows` lays a
  hand-built pair's gold on every segment of its path and none off it,
  and is identical across two runs; a sea-only pair adds nothing; the
  slip's three lines appear where they should and nowhere else.
- B: capacity by season and stripping (hand-computed); no forage at home;
  two regiments in one province share in proportion to need and never get
  more than their need; the supply plan ships less by the forage; stripping
  recovers and its zero entries are erased; the bare news comes once per
  crossing; the save round-trips `forage_stripped`; an old save loads with
  `{}`; 24 months twice from one seed give identical state.

## 4. Order of work

A first (data, `WarEconomy`, the ink, the slip, the key, visual review),
then B (state, `Forage`, the supply plan and settlement, the slip and
folio, the intel word, visual review).

## 5. Not in P3

- Cutting an enemy's trade by standing on its road (interdiction), sacking
  or plundering a town, a FORAGE order at home, foreign armies foraging
  (no foreign regiment is simulated), market stocks moving, the 3D map.
