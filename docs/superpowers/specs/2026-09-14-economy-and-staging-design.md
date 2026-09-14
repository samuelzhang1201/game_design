# The manor economy, the three pools, and staged orders

Owner decisions 2026-09-14. Repo files stay English; the owner's words are kept where they are the ruling.

## 1. What this is

Every manor of the pack earns, each month, three integers: **tax** (gold), **strategic goods** and **civil goods** (both valued in gold). A province's economy is the sum of its manors; the realm's is the sum of its provinces. Nothing is rounded above the manor, so the numbers tie out at every level and no decimal is ever shown. The month is the game's tick, now 30 days. The realm holds three pools — the **treasury**, the **strategic stock** and the **civil stock** — and the treasury can buy or sell the other two. The top bar shows the realm's monthly economy on one line and the crown's own provinces on a second, smaller line with their share of the realm in percent.

Time has one control: the clock in the top-left (pause, play, 2x, 4x). "End Turn" is gone. While the clock is stopped, every action the player takes is **staged**; pressing play **commits** the stage in order and lets the days run; at the end of each month the clock stops itself and the council convenes.

Decided against: storing per-manor output (3500 records that go stale the moment a province's ledger moves — everything stays derived, as MANOR_SYSTEM §3 rules); per-good stocks (71 stocks nobody can read on a bar); keeping End Turn or the chronicle interlude (the days already pass on the clock and the news is published as they do); a council that opens only on events (COUNCIL_SYSTEM's loop opens every tick).

## 2. The calendar: a tick is a month

- `Calendar.DAYS_PER_TICK` 15 → 30, `TICKS_PER_YEAR` 24 → 12. A season stays 90 days (three months), a year 360.
- `GameState.day` runs 1..30. A save with `day` ≤ 15 loads unchanged.
- Every "per tick" quantity becomes "per month" by definition. Values that were tuned for a fortnight are re-tuned in data (§9), never in code: `manor_focus.transition_ticks`, the event pity timer and base chance, the council's Guided/Assisted/Independent phases (ticks 1–12 / years 2–5 / year 5+), grain drain and harvest (now civil, §5), promise deadlines, relationship drift.
- `build_days` and `time_day_seconds` are already in days and do not move.

## 3. Goods: pool, price, growth

The pack's `economy/goods.csv` is written by the importer and must not be hand-edited, so the game keeps its own table keyed by the pack's `good_code`:

`data/goods_economy.csv` — `good_code,pool,price_gold,growth_permille,notes`

| column | meaning |
|---|---|
| `pool` | `strategic` or `civil` — where a unit's value lands |
| `price_gold` | gold per unit, integer; the deliberate spread: grain 1, wood 1, stone 2, salt 3, cloth 3, iron 4, wine 5, marble 6, furs 6, weapons 10, horses 12, ships 30, silver 20, gold 40 (these are the scale; the table fills all 71) |
| `growth_permille` | the good's monthly growth of output, per mille, integer: food ~2, construction ~3, luxury ~5, military ~4, each good tuned |

Classification: military, naval, horses, iron and ore, weapons, fuel and preserved food are **strategic**; food, livestock, timber and stone, cloth, wine, luxuries, salt, wares are **civil**.

`data/goods_economy_defaults.csv` — `tag,pool,price_gold,growth_permille`: a good the table does not name takes the row of its first tag in the pack's `tags` column, so a re-exported pack with a new good never breaks. A test asserts every good of the loaded pack resolves to a pool and a price.

`DataRepository` loads both; `goods_economy_of(good_code) -> {pool, price_gold, growth_permille}` is the one lookup.

## 4. A manor's month

`ManorEconomy` (`scripts/engine/manor_economy.gd`, RefCounted, pure): for one manor, one tick, `{tax, strategic, civil}` integers, plus `units` per good for the cards.

### 4.1 People are integers

`MapManors.people_of` becomes integer: a province's rural population is apportioned to its manors by weight (area × land value, as now) with the **largest-remainder method**, so Σ manor people == the province's rural population exactly. A burg's cell adds the burg's urban share the same way among the province's burgs. Cached with the existing share cache.

### 4.2 Tax

```
tax = round(people / 1000 × manor_tax_per_1000 × tax_rate / tax_rate_base × (1 + Σ tax_bonus))
```
`tax_rate` is the realm's poll-tax metric (1..10, exists); `tax_rate_base` (balance) is the level at which the factor is 1. A manor with a settlement adds the sales tax on its town's goods:
```
tariff = round(town_goods_gold × tariff_rate × tariff_per_sales_tax / 100)
```
The realm-level "tax_rate × admin capacity" formula of `TickEngine._drift` is removed; admin capacity keeps its other uses.

### 4.3 Goods

Units are rounded per good, then valued:
- **Chief good** (focus): `round(people / 1000 × yield_per_1000 × land_value × ramp × (1 + Σ output_bonus) × growth(good, tick))`
- **Buildings**: `produce_units` per building, × growth(good, tick)
- **Settlement**: every row of the pack's `production.csv` for the burg: `round(units × growth(good, tick) × (1 + Σ output_bonus))` — this is how a settlement earns more: a town has many lines where a manor has one
- `growth(good, tick)` = `(1 + growth_permille / 1000) ^ tick`, a pure function of the tick — computed in **integer per-mille arithmetic** (`index = index × (1000 + g) / 1000`, rounded, iterated from tick 0) and tabulated once per good per tick (§11), so the same save gives the same integers on every machine

`strategic = Σ units × price_gold` over strategic goods, `civil` likewise. Gold values are integer because units and prices are.

### 4.4 Sums

`ProvinceEconomy.of(repo, state, province) -> {tax, strategic, civil}` = Σ its manors. `RealmEconomy.of(repo, state) -> {realm: {…}, crown: {…}, per_province: {code: {…}}}` = Σ provinces, with the crown's controlled provinces (`MapManors.controlled_provinces`) summed separately. **The only rounding is at the manor.** Cached **per province** (§11): a province's entry holds its manors' lines and its sum, keyed on (tick, the province's owner and holders, its buildings and focus); the realm is the sum of the 203 entries. A test over the real beria pack asserts Σ manors == province and Σ provinces == realm for all three numbers.

`MapEconomy.output_of_provinces` keeps feeding the ECONOMY column, now from the same integer units.

## 5. The three pools and the month's end

Stocks, all integers in `state.metrics`: `treasury` (exists), `strategic` (new), `civil` (new). `world_schema.csv` gains `metrics.strategic` and `metrics.civil` as `int`, minimum 0, `llm_cap` small; `economy.kingdoms.player_realm.strategic` / `.civil` alias them like `treasury` does.

**Grain folds into civil.** `metrics.grain` becomes an alias of `metrics.civil` in the schema, so every concern scan, event, rule and prompt that reads grain keeps working. The harvest becomes a civil credit in autumn, the ration a monthly civil debit: `ration = round(crown_people / 1000 × ration_gold_per_1000)`, halved by the ration order as before. `grain_cap_*` is dropped; the civil stock is uncapped.

**The month's settlement** (`TickEngine`, replacing the income part of `_drift`), with `share = crown_share_permille / 1000`:

```
treasury  += crown.tax       + round(share × (realm.tax       − crown.tax))       − salaries − ration
strategic += crown.strategic + round(share × (realm.strategic − crown.strategic))
civil     += crown.civil     + round(share × (realm.civil     − crown.civil))
```
Each is a ledger line with its reason ("taxes of the crown's provinces", "the crown's share of the realm's taxes", "ministers' salaries", "the court's ration"), so the report and the top bar deltas read the same numbers.

**Salaries**: `council_seats.csv` gains `salary_gold`; each seated minister costs it monthly. `court_upkeep` goes.

**Buying and selling**: orders `GOODS_BUY` and `GOODS_SELL` with `{pool, gold}`:
- buy: treasury −= round(gold × (1 + goods_trade_spread)), pool += gold
- sell: pool −= gold, treasury += round(gold × (1 − goods_trade_spread))
Both go through `OrderCosts` (the spread is the cost) and can be issued from the council's free text or, later, a market panel.

**Where the pools go** (wired here, not designed here):
- civil: `manor_buildings.csv` gains `civil_cost`, paid on `MANOR_BUILD`; `cost_gold` becomes the price of **rushing**: `build_rush_gold_per_day` gold takes one day off the work. Settlement building uses the same columns.
- strategic: `order_costs.csv` gains a `strategic` column; levy, muster and campaign orders charge it. `RealmEconomy.strategic_stock(state)` is the single number the military design will read as the army's capacity and reach.
- treasury: events, realm actions, manor purchase, research, arms — as today.

## 6. The top bar

`Row` becomes two lines; `TopBar.bar_height()` grows and every screen's columns follow it.

- Line 1, the realm: **treasury** `stock (+tax/month)`, **strategic** `stock (+/month)`, **civil** `stock (+/month)`, then unrest, legitimacy, army quality, church as now. The monthly figures are the realm's.
- Line 2, the crown's provinces, a smaller font: `tax  N (P%)   strategic  N (P%)   civil  N (P%)` — the crown's monthly sums and their integer percent of the realm's.
- Both lines read `RealmEconomy.of`; the bar computes nothing. New `resource_icons.csv` rows: `strategic`, `civil` (the grain icon retires to `civil`).

## 7. Staged orders, the play button, no End Turn

**The rule**: while the clock is stopped, every player action is staged; while it runs, actions apply at once.

`GameState.staged: Array[Dictionary]`, saved with the game. An entry: `{id, kind, label, request, resolved}` — `kind` ∈ `suggestion` (a minister's proposal, an action code and params), `free_text` (the model's parsed order: `actions`, `world`, `court_reaction`, plus the narrative already shown), `event_choice` (event id and choice id), `manor` (a manor order from the card). A free-text order calls the model **when staged**, so the reply is read at once; its impacts wait in `resolved`.

`Game.stage(entry)` / `Game.unstage(id)` / `Game.commit_staged()`. Commit walks the list in order: each entry is validated again (gold, stock, the event still pending) and applied through the existing paths (`ActionSystem.execute`, `OrderPipeline.apply_order`, `apply_event_choice`); a rejected entry becomes a court line ("the treasury could not meet …") and is dropped. The list is cleared, `state_changed` fires, then the clock speed is set.

The **play button** (`Clock_1`, and `2x`/`4x` from a stop) is the commit: `Game.set_clock_speed(n)` from 0 calls `commit_staged()` first. Pause never commits.

**The staged list** sits at the bottom of the right column (people and talk, invariant 10): one row per entry with its label and a ✕ that unstages it. An event whose choice is staged shows "chosen, awaiting play" on its chip and no longer blocks the clock — the clock is stopped anyway.

**Month's end**: when `Game.advance_day` ticks, `GameRoot._process` sets the clock to 0 and switches to CONVERSATION with the report (today only a pending event does so; now every month). The conversation ends back on the court with everything staged.

**Removed**: the End Turn button in `court.tscn`, its Enter binding, `CourtScreen.end_turn_requested`, `GameRoot._on_end_turn_requested`, `State.DAY_RUN`, `scenes/day_run.tscn`, `day_run_screen.gd`, `calendar_overlay.gd`, and their tests. Daily news keeps publishing from the clock.

## 8. Testing

Engine (GUT, headless, hand-computed):
- calendar: 30 days a tick, 12 a year, seasons and dates
- `goods_economy`: every pack good resolves; defaults by tag; prices and growth are integers
- people apportionment: largest remainder sums exactly; a two-manor province by hand
- manor month: tax, tariff, chief good, building, settlement lines by hand, integers throughout; growth at tick 0 is 1
- beria tie-out: Σ manors == province, Σ provinces == realm, all three numbers
- month's settlement: the four treasury lines and the two stock lines by hand; the crown share rounds once
- buy and sell with the spread; `OrderCosts` sees the cost
- staging: order kept, unstage, commit applies in order, a rejected entry leaves a line, save round-trips the list, commit from 0 only
- caching (§11): a day step and a top bar refresh do not recompute; a manor order recomputes exactly one province; the growth table is integer and the same after a save round trip

UI:
- top bar: two lines, the second smaller, percentages, `bar_height` grew and the columns follow
- court: no End Turn, Enter does nothing, the staged list shows and unstages
- game root: play commits then runs; month's end stops the clock and opens the council; no DAY_RUN

## 9. Data rewrite

The owner allowed every initial economic number to be rewritten.
- `balance.csv`: retire `tax_income_factor`, `tariff_income_factor`, `court_upkeep`, `harvest_gain`, `grain_drain*`, `grain_cap_*`, `manor_rent_per_1000`; add `manor_tax_per_1000`, `tax_rate_base`, `tariff_per_sales_tax`, `crown_share_permille` (200), `goods_trade_spread`, `ration_gold_per_1000`, `harvest_civil_per_1000`, `build_rush_gold_per_day`, `start_strategic_months`, `start_civil_months`; re-tune every per-tick value to a month.
- seeding: treasury from the pack's town treasuries as now; strategic and civil = the crown's monthly production × the start months.
- `goods_economy.csv` filled for all 71 goods at the §3 scale; `goods_economy_defaults.csv` for the tag families.
- `council_seats.csv` `salary_gold`; `manor_buildings.csv` `civil_cost`; `order_costs.csv` `strategic`.
- `manor_focus.csv` `transition_ticks` halved; event and council timers per month.

## 10. Out of scope

The military's use of the strategic stock (capacity, reach, campaign costs) beyond the cost column; a market panel; research and arms; per-manor event modifiers (the interface is the derived formula — a `manor_modifiers` table can multiply into §4 later without storing output).

## 11. Performance

### 11.1 The size of the work

The beria pack: 3 500 land manors in 203 provinces, 684 settlements, 5 061 town production rows, 71 goods. One full realm computation is, per manor, an integer people share (already cached), one chief-good line, a few building lines, and for a settlement manor its town's production rows — about 10 000 rounded lines and 10 000 table lookups in all. In GDScript that is **20–50 ms cold** on the development machine (a rounded line with two dictionary lookups costs 2–5 µs). Nothing in the design is per frame: the map draws nothing new, the top bar reads a cached sum, and the ECONOMY column reads the same cache.

What could hurt, and the answer to each:

| where the cost would land | without care | with the design |
|---|---|---|
| the month's end (tick) | one full computation, 20–50 ms, once a month — fine either way; the tick already runs works, drift, events | same; the settlement adds six ledger lines |
| a manor order (buy, build, focus) | invalidating the realm cache and recomputing everything: a 20–50 ms hitch at 60 fps, and the card refreshes right after the click | **per-province cache**: only the province whose manor changed is rebuilt — ~17 manors, well under 1 ms — and the realm sum re-adds 203 entries |
| a day step (`state_changed` every day at 4x, four a second) | the top bar re-reading a sum keyed on state that changed | the key is the tick, not the day; a day step is a cache hit; a work that finishes changes one province's key, not the realm's |
| the manor master table (up to 400 rows, sorted over all 3 500 manors) | one line computation per manor on every refresh, 20–50 ms | the province entry keeps its manors' lines, so the table reads them; a refresh is a sort |
| the growth index | `pow` per line, 10 000 a computation, and float `pow` differs across platforms | one table per tick: 71 goods × integer per-mille compounding, filled incrementally as ticks pass (a 60-year game is 720 ticks × 71 = 51 000 ints, ~0.4 MB) |
| the goods lookups | `goods_economy_of` through two CSV tables per line | resolved once at load into `good_code → {pool, price_gold, growth_permille}`; the pack's production rows pre-grouped per burg as `good_code → units` (done today for the ECONOMY column) |
| staging and commit | — | N entries through the paths they use today; a commit of ten orders is ten orders |
| the save | — | two integers and the staged list; no per-manor state (the reason for §1's decision) |
| the model | — | no new calls; the free-text order's one call moves from execute-time to stage-time |

The calendar change halves the ticks a year, so per year the engine does half the month's-end work it does today.

### 11.2 The cache

`RealmEconomy` keeps one dictionary `province_code → {key, manors: {manor_id: line}, sum}` and one realm sum with its own key.
- A province's key: `(tick, controller, Σ hash of its manors' owner, buildings and focus)`, cheap to build from `GameState.manor_owner`, `manor_works` and `manor_focus`, which hold only what moved.
- The realm key is the tuple of the province keys' hash. Reading the realm compares 203 keys, no lines.
- `MapManors.set_owner`, `MANOR_BUILD` / `MANOR_DEMOLISH`, `MANOR_FOCUS` and a finished work call `RealmEconomy.forget_province(code)`; the tick calls `forget_all()` and recomputes the realm once for the settlement, which then serves the report, the top bar and the council.
- The province ledger (`economy.provinces.<p>.rural_population` moved by the model or an event) invalidates that province through `WorldLedger.apply`.
- `DataRepository.load_map` clears everything, like every other cache.

### 11.3 Discipline and measurement

- **Integers only, integer growth**: no `pow`, no float in the sums, so a save loaded on another machine ticks to the same numbers (invariant 2) and the tie-out test is exact, not approximate.
- **A bench**: `tools/bench_economy.gd` (like `tools/bench_map.gd`) times a cold realm computation, a warm realm read, a single-province recompute and a month's settlement on the beria pack and prints them; the targets are cold < 60 ms, warm read < 0.1 ms, one province < 1 ms, settlement < 5 ms beyond the cold computation. Run it when the formulas change.
- **A test seam**: `RealmEconomy.compute_count` (a counter, test only) so tests assert that a day step, a top bar refresh and a card click do not recompute the realm, and that a manor order recomputes exactly one province.
- If a later pack were ten times larger, the same shape holds: the cold computation scales with lines, everything else with what changed.
