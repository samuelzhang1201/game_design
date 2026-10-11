# Manor System — design (2026-09-13; built; revised to the code 2026-09-18)

The manor is the smallest piece of land in the game: one land cell of the
map pack's Voronoi graph (beria: 3 500 land cells of 4 833). Before this
document it was only a coloured patch in the ECONOMY view. This document
makes it a **unit**: clickable, with attributes tied to its province, held by
a **house**, and movable — bought, sold, or seized. It follows the owner's
rulings of 2026-09-13: owner = house; trade = an offer to the holding house
at a formula price; seizure = data and order skeleton only; attributes = the
full set including buildings and taxes; plus a **Manor Master** view listing
every manor on the map. Later rulings (2026-09-13 control and chief goods,
2026-09-14 purses, purchase map, buildings and the one integer economy) are
folded in below with their dates.

Everything below obeys the invariants in CLAUDE.md: the engine decides, one
seeded RNG, engine-pure `RefCounted` classes, every change carries a reason,
design values in CSVs, save = one JSON, and the economy is whole gold rounded
once, at the manor (invariant 11).

---

## 1. Identity and geometry

| Thing | Where it comes from |
|---|---|
| Manor id | the cell id (`cells.csv` `cell_id`), int; stable across runs and saves |
| Which cells are manors | land cells only (`water == ""`); lakes and sea are not manors. The rows of `political/manors.csv` ARE the manors (`MapManors.is_manor`) |
| Province of a manor | the pack's `political/manors.csv` `province_code` (27 beria manors in the wildlands have none), unless the manor was annexed (§5c): `MapManors.province_of(repo, cell_id, state)` reads `GameState.manor_province` first |
| Hit-testing | a pack bitmap **`world_cell_index.png`** (R \| G<<8 = cell id, white = none), rasterised by the importer with the same `_rasterize` the province index uses (4 833 ids fit two bytes; the importer asserts `< 65536`). `tools/bake_manors.gd` bakes it — together with `manors.csv` — for a pack from its export, and must run AFTER the import (`tools/NEW_MAP.md` step 3: the importer's own index and names differ in a few cells, and the bake is what the game reads). Like every tool it takes `--map ID` and otherwise uses `data/world/maps.csv`'s `is_default` pack (`DataRepository.default_pack_id`). `data/world/maps.csv` `cell_texture`; `MapIndex.id_at` decodes it. |
| Name | **every manor has a proper, unique name, in the pack** (owner 2026-09-13: the player has to be able to say "buy Ashcombe"). Pack table `political/manors.csv` (`cell_id,manor_code,label,province_code,burg_code,culture_code`), written by the importer and by `tools/bake_manors.gd` (`ManorNames`). A cell with a burg is named after it ("Skipton Manor", `burg_code` set). Every other land cell gets a name **forged in its culture's style**: the Azgaar export carries `nameBases` (banks of real place names) and each culture's `base`; `NameForge` (engine-pure, tested) runs an order-2 letter Markov chain over the cell's culture's bank — the same method Azgaar named the burgs with, so manors and towns sound like one country — seeded from the map seed and the cell id, so a re-bake forges the same names; uniqueness is enforced across the pack, and the code is the label's slug. Hand corrections go in the hand-maintained `data/maps/<id>/manor_name_overrides.csv` (`cell_id,label`, optional) that the loader applies last, so a re-export cannot undo them. Orders and the model refer to a manor by `manor_code`; `MapManors.find` also accepts the label case-insensitively (with or without "Manor") and the cell id, so a typed "buy Ashcombe" resolves. |
| Area | polygon area of the cell (native px², `MapManors.area_of`) × `distance_scale`² → km², shown as hectares/km² |

## 2. Ownership — houses

- **A house is a family name.** There is no House entity in the engine
  (houses are `Character.family_name`, `house_bindings.csv`, and
  `MapObjects.house_name_of`). A manor's owner is a family-name string, and
  "the crown" is the player's family (`MapManors.crown`: the `you`
  character's family name, else `GameState.player_setup.family_name`).
- **Default owner** of an unmoved manor = the house of its province
  (`MapObjects.house_name_of`: the `house_bindings.csv` family, else a house
  named after the seat). When that house is the royal house under the name it
  had before character creation renamed it (`player_setup.house_was`), the
  manor is the crown's. So the pack needs no ownership column: every manor
  starts with its province's house, exactly as province ownership starts
  from the pack.
- **State is sparse**, mirroring provinces: `GameState.manor_owner:
  Dictionary {cell_id (String in JSON): family_name}` holds only manors that
  moved; `GameState.manor_log` holds one entry per change —
  `{tick, cell, from, to, reason}` for a transfer, and entries with a
  `building` / `begun` / `rushed` / `demolished` / `focus` field for works
  and chief goods. `MapManors.set_owner(repo, state, cell_id, family, reason)
  -> bool` refuses a cell that is no manor, unknown houses (a house is
  "known" if it is the crown's, a binding names it, any character carries
  the name, or it is some province's default house), no-op moves, and an
  empty reason — the same shape as `MapOwnership.set_owner`.
- **Province stays the political layer.** Kingdom borders come from
  provinces; a manor changing house never moves a border (only an
  annexation, §5c, moves a cell between provinces). A conquest of a province
  does not reassign its manors — the new kingdom simply contains a province
  whose manors are held by whoever held them. This is deliberate: houses
  outlive crowns.
- **A house wears its seat's arms** (owner 2026-09-15): `HouseArms`
  resolves a family to its first province by `province_id` and that
  province's capital town's generated arms; the crown through
  `player_setup.house_was`. A pack with no arms of its own borrows installed
  arms from other packs, or pins them in an optional
  `data/maps/<id>/arms_bindings.csv` (owner 2026-09-18). The manor card and
  each Manor Master row wear the holding house's arms.

## 3. Attributes (the manor card)

All derived, none stored, except buildings, works, chief good and province
moves.

| Attribute | Formula / source | Data |
|---|---|---|
| Province, kingdom, house | `MapManors.province_of`, `MapOwnership.owner_of`, `MapManors.owner_of` | live |
| Terrain | biome label + height class + coast / river flags | `biomes.csv`, `cells.csv`, `rivers.csv` |
| Land value | `MapEconomy.land_value` (habitability 0..1) | `biomes.csv` |
| People | WHOLE people (spec 2026-09-14 §4.1): the province's **rural** population (ledger `economy.provinces.<p>.rural_population`) apportioned by weight `area × land_value` over the province's manors, plus its **urban** population apportioned over the manors that have a burg by the burgs' pack populations — both by the largest-remainder method (`MapManors.apportion`, `people_table`, `people_of`). Manors therefore always sum EXACTLY to the province — the tie to province data the owner asked for, and nothing to keep in sync. The earlier float share (`population_of`) is gone. | ledger |
| Output | `ManorEconomy.line_of`'s `units`: the chief good (§5a), the buildings' `produce_good/units`, and, for a manor with a town, the pack's `production.csv` rows for its burg — each × the good's growth index, whole units a month, their worth split into the strategic and civil pools by `data/economy/goods_economy.csv` | `production.csv`, `goods_economy.csv` |
| Buildings | the list in `GameState.manor_buildings {cell_id: [building_code]}`, works in progress in `manor_works` (§5b); catalogue **`data/economy/manor_buildings.csv`** (`building_code,label,tier,land,prereq,cost_gold,civil_cost,build_days,tax_bonus,output_bonus,defence_bonus,church_bonus,gold_per_tick,grain_per_tick,contentment_per_tick,unrest_per_tick,produce_good,produce_units,notes` — `civil_cost` is the one price the game charges and `cost_gold` is unused, kept for the library): 22 buildings in three tiers (§5d) | CSV |
| Tax (rent) | A MONTH of whole gold, §4.2 of the spec (`../superpowers/specs/2026-09-14-economy-and-staging-design.md`): `round(people / 1000 × manor_tax_per_1000 × tax_rate / tax_rate_base × (1 + Σ tax_bonus))`, plus its town's tariff `round(town_goods_gold × tariff_rate × tariff_per_sales_tax / 100)`. `ManorEconomy.line_of` computes it (the only rounding in the economy), `RealmEconomy` sums it into provinces and the realm, and the month's end settles it into the two purses (§5c). Other houses' taxes are shown on the card as what the house earns (no house treasuries exist — the number is information and a price input, not a ledger). | `balance.csv` `manor_tax_per_1000`, `tax_rate_base`, `tariff_per_sales_tax` |
| Defence | `manor_defence_base + Σ defence_bonus` — displayed now, for the seizure resolution later | `economy/balance.csv` |
| Value (price) | see §5 | `balance.csv` |
| Actions | BUY / SELL / BUILD / HURRY / DEMOLISH / WORK (focus) / SEIZE buttons, shown by legality (§5) | — |

The card is `MapObjects.manor_card(repo, state, cell_id)` returning the same
`{kind, code, title, subtitle, kingdom_code, fields, features, production,
center, ask, known, actions}` shape `province_card` returns, plus
`buildings`, `works`, `slots`, `slot_actions`, `stats`, `rates` and
`painting`, so `MapDetailPanel.show_card` renders it with a slot row (the
buildings' `bld_*` art from `resource_icons.csv`, §5b) and an action row.
`known == "basic"` for manors outside the player's realm, as for provinces;
a `foreign` border manor's basic card still offers its one BUY (§5c).

**The card's face** (owner 2026-09-14): over the card, a third of its height, the painting of the manor's estate (library `B-`, the same industry × size row as its map drawing, `data/economy/manor_estates.csv` `painting`); below the title the attributes above as icons (`resource_icons.csv` `manor_*`) — owner, province, seat, terrain, land, area, people, tax, strategic and civil goods a month, chief good, estate size, defence, slots, value, price — a short value beside each and the full fact in its tooltip (`manor_card.stats`); then **Output a month**, one row per good the manor makes with `+N / mo` and, in the tooltip, what the units are worth and to which pool (`manor_card.rates`, from `ManorEconomy.line_of`).

## 4. Province tie-in

- The province card carries a **Manors** field: "N manors — crown k, House A
  m, House B j" (`MapManors.holdings_of_province`), and a **Controlled by**
  field (`MapManors.controller_of`, §5a). (The "rents" line once planned
  here was not built.)
- Manor people are shares of the province's numbers (§3), so a ledger delta
  on a province moves every manor in it; nothing is stored twice.
- `WorldLedger.belongs_to_player` now reads the provinces the crown
  CONTROLS (§5a, superseding "the provinces the crown's kingdom holds");
  military figures stay the realm's. Manor ownership is not a ledger path;
  it moves only through orders (§5), never through a model-proposed delta.

## 5. Orders

Rows in `data/council/policy_actions_court_additions.csv`, fees in
`data/realm/order_costs.csv`, ideology in `data/realm/action_signatures.csv`. All params
are validated in `ActionSystem.validate` (`_validate_manor`: the manor must
exist and — except a cross-border BUY (§5c) — lie in the player's realm; the
crown must not already hold it / must hold it); execution in
`ActionSystem.execute`; every effect carries a reason. The param is `manor`
(code, label or cell id, `MapManors.find`). Clicked from the card they go
`Game.try_execute` and never touch the model; typed, the model may name them
as actions and the same validation applies. Every manor order also pays its
small `order_costs.csv` fee from the treasury (the notary, the surveyor, the
reeve…); the prices below are charged by the order itself.

| Order | Params | Legal when | Effect | Costs |
|---|---|---|---|---|
| `MANOR_BUY` | `manor` | not crown-held, and one of (§5c): in a province the crown controls or a province of the realm bordering one — `lord_gold` ≥ price; across the border, a manor whose cell touches the realm — `treasury` ≥ price + fee | inside the realm: owner → crown, `lord_gold` −price. Across the border: `treasury` −price, the manor is annexed into the richest bordering province of the realm (`MapManors.annex`) and held by that province's house. Either way the selling house's characters: opinion +`manor_trade_goodwill`; its councillor's `wealth` +`manor_trade_wealth`; `manor_log` "bought from House X for N" | price (formula) + 2 gold fee |
| `MANOR_SELL` | `manor` | crown-held, in the realm, and the province's house is not the crown | owner → the province's house; `lord_gold` +value × `manor_sell_ratio` | 2 gold fee |
| `MANOR_BUILD` | `manor, building` | crown-held, province crown-controlled, the ground and prerequisites allow it (§5d), not standing or begun, a free slot, the lord's CIVIL stores (`lord_civil`) ≥ the building's `civil_cost` | the work begins (`manor_works`), finishing after `build_days`; `lord_civil` −`civil_cost` | building's `civil_cost` + 1 gold fee |
| `MANOR_SEIZE` | `manor` | in the player's realm, not crown-held, `manor_seize_enabled` = 1 (it is **0**: the order is refused and its button hidden) | **skeleton**: owner → crown with reason "seized by force"; legitimacy −`manor_seize_legitimacy`; unrest +`manor_seize_unrest`; the house's characters opinion −`manor_seize_outrage`; `manor_log`. Resolution is automatic success; the defence number is displayed but not rolled. The regiments now have state (`ArmySystem`, owner 2026-09-17: morale, wounded, supplies, training and a power figure) but no combat resolution yet — when it lands (PRD RD-1..3) the outcome tier plugs in here. **Not yet built.** | 10 gold fee (the men-at-arms' pay) |

**Price** (`MapManors.price_of`), every term in `balance.csv`:

```
base   = people / 1000 × manor_price_per_1000
       + units × manor_price_per_unit        (the month's units, every good, §3)
       + Σ building civil_cost × manor_price_building_ratio
land   = 1 + (land_value − 0.5) × manor_price_land_swing
value  = base × land                          (MapManors.value_of_line)
ask    = round(value × (1 + manor_markup_max × clamp((100 − opinion) / 200, 0, 1)))
sell   = round(value × manor_sell_ratio)
```

`opinion` (−100..100) is the selling house's council member's opinion of the
player when the family has a seat, else any character of the family's, else
0 for a house with no voice at court (`MapManors.house_opinion`). So a house
at +100 asks the value itself and one at −100 up to `manor_markup_max` more —
the same opinion system the council runs on, with no new ledger.

Signatures (`action_signatures.csv`, centralism / militarism / orthodoxy /
tax incidence / expansionism): BUY +20 / 0 / 0 / 0 / +10; SELL −10 / … /
−5; BUILD +10; SEIZE +30 / +40 / −10 / 0 / +20; FOCUS +5; DEMOLISH −5;
RUSH +10.

### 5a. Control and the chief good (owner 2026-09-13)

The player is the king of the realm AND the lord of one province. A
province is **controlled** by the house holding the most of its manors
(`MapManors.controller_of`; a tie goes to the province's own house). The
crown starts controlling the capital's province alone (`house_bindings.csv`
binds the royal house to it and nothing else) and gains or loses provinces
manor by manor (`MapManors.controlled_provinces`). Everything that reads as
"the crown's economy" is the controlled provinces: the seeded LORD's purse
(their towns' treasuries, §5c), the dashboard's people and provinces, the
ECONOMY column, the ledger paths the model may write
(`WorldLedger.belongs_to_player`) and the order prompt's "Your provinces".
The host stays the realm's. SEIZE works anywhere in the realm; BUY only
where §5c allows; BUILD and FOCUS need a province the crown controls.

Every manor works one **chief good** (`data/economy/manor_focus.csv`, twelve rows):
a focus is allowed by the cell's biome (and, for fisheries, a sea
neighbour). The default **follows the terrain** (owner 2026-09-14,
`MapManors.default_focus`): the focus whose `default_on` claims the cell —
`coast`, `peak` (height ≥ `manor_focus_peak_height`, 63), `high` (≥
`manor_focus_high_height`, 52) or a biome id, a coast claim outranking a
peak, a peak the high ground, any of those a biome, ties to file order —
among those the land allows, else the first the land allows.
`GameState.manor_focus` holds only manors whose focus was chosen
(`{focus, since}`), logged in `manor_log` with a `focus` field. Yield a MONTH
= people / 1000 × `yield_per_1000` × land value × the settling-in ramp (0 on
the tick of the switch, 1 after `transition_ticks`) × (1 + buildings'
`output_bonus`) × the good's growth index, rounded ONCE to whole units
(`ManorEconomy.focus_units`; the old `manor_focus_yield_scale` knob was
retired 2026-09-14 with the float path it scaled). The focus adds nothing
to the tax (the `rent_bonus` column was dropped 2026-09-14: tax is the
buildings' `tax_bonus` alone); its units count in the value like town
trade, and `MapEconomy.output_of_provinces(repo, provinces, state)` sums
every manor's month (`ManorEconomy.line_of`'s units — chief good,
buildings and town together) for the ECONOMY column.

| Order | Params | Legal when | Effect | Costs |
|---|---|---|---|---|
| `MANOR_FOCUS` | `manor, focus` | crown-held, province crown-controlled, focus allowed on the land, not the one it works, `lord_gold` ≥ `switch_cost_gold` | `manor_focus[cell] = {focus, since: tick}`; `lord_gold` −`switch_cost_gold` | `switch_cost_gold` + the reeve's 1 gold fee |

The card shows "Chief good" and one `WORK <focus> — N gold` button per
allowed focus it does not work; the Manor Master's tooltip names it.

### 5c. Two purses and where land may be bought (owner 2026-09-14)

**Two purses, told apart everywhere.** The CROWN's treasury and stores —
`metrics.treasury`, `strategic`, `grain` (the civil pool), marked with a
crown in the top bar — are the realm's: each month's end pays them
`crown_share_permille` (200, a fifth) of every province of the realm the
player's house does NOT control, and they pay the ministers' salaries, the
court's ration, the orders' fees and land bought across the border. The
LORD's own purse — `metrics.lord_gold`, `lord_strategic`, `lord_civil`,
marked with the house's arms — is the player's as lord of his own provinces,
free to spend: the provinces the crown controls pay into it in full, with the
autumn harvest (`harvest_civil_per_1000`) and the crown's buildings'
`gold_per_tick` / `grain_per_tick`. `RealmEconomy.purses` is the one split
the settlement (`TickEngine._settle_economy`) and the top bar read. At the
start the lord's gold is what the controlled provinces' towns hold
(`WorldLedger.crown_town_treasury` × `pack_treasury_scale` ×
`start_lord_gold_scale`), the treasury the crown's share of the rest of the
realm's towns (`realm_share_town_treasury`), and each goods pool months of
its own purse's month. Every manor order inside the realm — buy, sell,
build, hurry, a new chief good, a demolition's refund — moves the lord's
purse; only the orders' fees (`order_costs.csv`) stay on the treasury.

**Where a manor may be bought** (`MapManors.purchase_kind`):

| Kind | Where | Paid from | What becomes of it |
|---|---|---|---|
| `own` | a province the crown controls | `lord_gold` | the crown's |
| `domestic` | a province of the realm that shares a border with a controlled one (`province_neighbours`) | `lord_gold` | the crown's |
| `foreign` | another kingdom's manor whose cell touches a cell of the realm | `treasury` | annexed into the bordering province of the realm with the most tax a month (`annex_target`, ties to the code that sorts first) and held by that province's house |
| refused | a realm province bordering none of the crown's; a foreign manor off the border | — | the validator says which |

**Annexation makes a manor's province state.** `GameState.manor_province`
holds only manors moved out of their pack province (saved; `annex` needs a
reason and logs `annexed_from`/`annexed_to`). `MapManors.province_of` and
`manors_of_province` take the state, and so does everything that counts a
province's manors — owner, holdings, control, people, `RealmEconomy`'s
columnar index (rebuilt when the annexations change). A province's live
outline is `MapOwnership.province_loops`: its pack loops merged with the
outline of every cell annexed into or out of it by EDGE PARITY — cells share
the provinces' exact vertices — so the kingdom border, the seams and the
political wash redraw with no new art, on the 2D map and on the 3D MAP
(whose borders rebuild when `manor_province` changes). The card of a
`foreign` border manor (a "basic" card otherwise) offers its one BUY, and
every BUY button names the purse that pays.

### 5d. Where buildings may stand, and what they yield (owner 2026-09-14)

Not every manor raises the same buildings. `data/economy/manor_buildings.csv` holds
22 buildings in three `tier`s (14 / 5 / 3). Its `land` says where the ground
takes one — tokens joined by `|` of which ONE must hold: `coast`, `high` /
`peak`, `town`, `focus:<code>`, a biome id, or `any` (`MapManors.land_allows`
/ `describe_land`, the language of `manor_focus.csv` `default_on`). So a
fishing quay and a shipwright stand only on the coast; a mine shaft and a
stonecutter on high ground or where iron and stone are worked; a sawmill
where there is forest or timber is worked; a mill and a granary on farming
land; a winepress where vines grow; a tannery where the herds are; a loom
house where sheep run or in a town. `prereq` names buildings that must ALL
stand first (`building_prereqs`): a market needs a manor house, a smithy a
mine shaft, a brewery a mill, a shipwright a fishing quay, an abbey a chapel,
a castle a palisade and a manor house, a harbour a quay and a market, an
armoury a smithy. `MapManors.building_blocked` gives the reason and
`ActionSystem` refuses a MANOR_BUILD with it. Chains fit the three slots.
Every building yields once it stands (a test holds that): goods a month
(fish, salt, wood, stone, iron, honey, wine, leather, cloth, tools, beer,
ships, books, arms, preserved food, candles, grain) or its bonus columns. The
card lists what the ground takes in one dropdown
(`MapDetailPanel._add_build_menu`), each entry its `bld_<code>` art, cost and
days, its tooltip what it yields; a building still waiting on another is
shown disabled with the reason.

### 5b. Time, works, slots and demolition (owner 2026-09-13)

**The smallest unit of time is a day.** `GameState.day` (1..30,
`Calendar.DAYS_PER_TICK`: a tick is a month) sits under the tick; the top
bar's clock (`||`, `>`, `2x`, `4x` — `time_day_seconds`,
`time_speed_fast/faster`) runs on the court and on the council stage (owner
2026-09-14), in `GameRoot._process`, and calls `Game.advance_day`: works
step, `RealmEconomy.step_day` recomputes the day's bucket of provinces, and
the thirtieth day's end runs the tick (`TickEngine.advance` resets the day).
A tick that rolls an event stops the clock and opens the council; there is
no End Turn (owner 2026-09-14: play is the only switch). Real time never
enters the engine.

**Building takes time and room.** `data/economy/manor_buildings.csv` `build_days`
(from 20 — palisade, apiary — to 90 for a castle; granary 25, mill 30,
chapel 40, market 45, manor house 60); `MANOR_BUILD` begins a work —
`GameState.manor_works {cell: [{building, start, days}]}`, `start` the
absolute day — that takes a slot until `MapManors.advance_works` moves it
into `manor_buildings`. A manor has `manor_slots_base` (3) slots (+
`manor_slots_burg_bonus` (1) with a town). The news bar announces a work at
`news_build_milestone_1` / `_2` and at its completion.

| Order | Params | Legal when | Effect | Costs |
|---|---|---|---|---|
| `MANOR_RUSH` | `manor, building, days` | crown-held, a work with days left, `lord_gold` ≥ days × `build_rush_gold_per_day` (3) | cuts the days (never below done; `MapManors.rush_work`); the card's HURRY button buys `manor_rush_days_per_click` (5) days | the gold + 1 gold fee |
| `MANOR_DEMOLISH` | `manor, building` | crown-held, the building standing or begun | pulls it down or stops the work; `manor_demolish_refund` (half) of its `civil_cost` returned to `lord_civil` — a build is bought with goods, so goods come back, never gold | 1 gold fee |

The card draws one box per slot (the building's icon, a see-through box with
a dashed edge and its art faint inside for a work, or `+`) with a cross under
each building or work.

**What buildings do** (per finished building on a crown manor, per tick —
the `*_per_tick` columns are a MONTH's worth): `gold_per_tick` into
`lord_gold` (manor house 3, market 3, harbour 6), `grain_per_tick` into
`lord_civil` (mill 2, granary 3), `church_bonus` → church opinion (chapel
0.3, abbey 0.8), `contentment_per_tick` (manor house 0.2, abbey and brewery
0.1, apiary and winepress 0.05), `unrest_per_tick` (palisade −0.1, castle
−0.3), plus the standing `tax_bonus` / `output_bonus` / `defence_bonus`;
`produce_good/units` join the manor's line and the ECONOMY column (§3).
`TickEngine` applies the purse lines with the month's settlement and the
metric lines in its drift, each as its own ledger line.

## 6. Map and views

- **Click**: `MapObjects.object_at` has a `manor` kind. It is picked when
  the MANORS layer or the ECONOMY layer is on (both show manors), through
  `world_cell_index.png`; elsewhere a land click keeps meaning the
  province/kingdom, so the political map does not change behaviour. In those
  layers a badge still opens the burg, and a bare manor opens the manor card
  in the LEFT column (columns divide by kind). Hover names the manor in the
  tooltip; only a clicked manor is ringed. The 3D MAP tab (owner 2026-09-18)
  picks provinces and settlements, not manors.
- **MANORS layer** (the "Manor Master" view): a theme beside PROVINCES /
  HEIGHTS / ECONOMY, on its own bottom-bar toggle, mutually exclusive like
  the others. It draws the manor mesh coloured **by holding house**: the
  crown in the realm's colour deepened (`map_manor_crown_deep`), each other
  house in a hue derived deterministically from its name
  (`MapPalette.house_color`, `map_manor_house_sat` / `_val`), pale outside
  the player's realm (`map_manor_foreign_pale`), neighbouring provinces told
  apart by shade levels (`map_manor_shade_*`); cell edges ruled as in
  ECONOMY; no realm tint on symbols (thematic rule). The town drawings wear
  their manor's colour (`map_manor_mark_alpha`), and every manor without a
  town wears ONE **estate** drawing by its industry and size
  (`data/economy/manor_estates.csv`, library `D-43`..`D-78`, `MapObjects.estate_tier`
  / `manor_estates`, one `MarkMesh` thinned by zoom through
  `estate_lod_ranks`; balance `map_manor_estate_*`) — see CLAUDE.md.
- **Settlements grow with their manor** (owner 2026-09-15):
  `MapObjects.settlement_look` promotes a town's drawing by
  `data/settlement_growth.csv` — its manor's live people past a row's
  `min_people` (village → town, town → city), or a row's building standing on
  the manor (a palisade or castle draws a town walled). Promotion only.
- **Manor Master panel** (`ManorMasterPanel`) in the LEFT column while the
  layer is on (the way ECONOMY puts `EconomyPanel` there): a sortable `Tree`
  of manors — columns Manor, House (with its arms), Value; province, people,
  tax and buildings in the row's tooltip — defaulting to the crown's realm,
  with a scope toggle for the whole map and a house filter, capped at
  `manor_master_max_rows` (400) with a line saying how many were left out,
  and a summary line. Clicking a row centres the map on the manor and rings
  it; activating it (double click or Enter) opens its card. Everything wraps
  or scrolls inside `ScreenLayout.LEFT_WIDTH`.

## 7. Save

`GameState`: `manor_owner`, `manor_province`, `manor_buildings`,
`manor_works`, `manor_focus` and `manor_log` in `to_dict` / `from_dict` with
`.get` defaults (old saves load), keys as strings in JSON and re-int'd on
load, numeric leaves through `_encode_values`. They were additive, so
`SAVE_VERSION` (5 as of 2026-09-18) was not bumped for them. The regiments'
state (`GameState.regiments`, 2026-09-17) is saved the same way.

## 8. Data files touched

| File | Change |
|---|---|
| `assets/maps/<id>/world_cell_index.png` | generated (importer, `tools/bake_manors.gd`) |
| `data/maps/<id>/political/manors.csv` | generated: one named manor per land cell (§1) |
| `data/maps/<id>/manor_name_overrides.csv` | optional, hand-maintained, never written by the importer |
| `scripts/engine/name_forge.gd`, `manor_names.gd` | the Markov name forge over the export's `nameBases`, and the manor table built with it |
| `scripts/engine/map_manors.gd`, `manor_economy.gd`, `realm_economy.gd` | the manor rules; one manor's month; the provinces' and realm's sums and the purses |
| `data/world/maps.csv` | `cell_texture` column |
| `data/economy/manor_buildings.csv` | the catalogue: 22 buildings, `tier`, `land`, `prereq`, `build_days`, yields |
| `data/economy/manor_focus.csv` | the twelve chief goods (`biomes`, `coast`, `yield_per_1000`, `switch_cost_gold`, `transition_ticks`, `default_on`) |
| `data/economy/manor_estates.csv` | the estate drawing and painting per industry × size |
| `data/settlement_growth.csv` | a settlement's drawing promoted by its manor's people or buildings |
| `data/balance.csv` | `manor_tax_per_1000`, `tax_rate_base`, `tariff_per_sales_tax`, `crown_share_permille`, `manor_price_per_1000`, `manor_price_per_unit`, `manor_price_building_ratio`, `manor_price_land_swing`, `manor_markup_max`, `manor_sell_ratio`, `manor_trade_goodwill`, `manor_trade_wealth`, `manor_defence_base`, `manor_seize_enabled`, `manor_seize_legitimacy`, `manor_seize_unrest`, `manor_seize_outrage`, `manor_master_max_rows`, `manor_slots_base`, `manor_slots_burg_bonus`, `manor_demolish_refund`, `build_rush_gold_per_day`, `manor_rush_days_per_click`, `manor_focus_high_height`, `manor_focus_peak_height`, `economy_check_full`, the clock's `time_*`, and the views' `map_manor_*` |
| `data/council/policy_actions_court_additions.csv`, `order_costs.csv`, `action_signatures.csv` | seven orders: BUY, SELL, BUILD, SEIZE, FOCUS, DEMOLISH, RUSH |
| `data/screens/ui/political_palette.csv` | `manor_pale`, `manor_rich`, `manor_line`, `manor_mark` (the ECONOMY view's `manor_badge` / `manor_label_*`); house hues come from `balance.csv` (`map_manor_house_*`), not palette rows |
| `data/screens/ui/resource_icons.csv` | `bld_<code>` art for the 22 buildings and the card's `manor_*` stat icons |

## 9. Tests (written before the code, hand-computed values)

As built: `tests/engine/test_map_manors.gd` (default owner, `set_owner`
refusals and log, whole-people apportionment summing to the province, price,
names, control, chief goods and the terrain default, slots, works and
rushing), `test_manor_purchase.gd` (the `own` / `domestic` / `foreign`
purchase map and annexation), `test_manor_economy.gd` and
`test_realm_economy.gd` (the month's line, the sums, the day buckets and
the full-recompute check), `test_action_system.gd` (the orders, land and
prerequisite refusals, SEIZE gated by the flag),
`test_map_index.gd` / `test_map_pack.gd` (the cell index at canvas size),
`test_game_state.gd` (round-trip, old-save load), `test_tick_engine.gd`
(the settlement reaches the two purses with reasons),
`tests/ui/test_world_map_view.gd` and `test_manor_master_panel.gd` (a click
in the MANORS layer selects a manor, the political view selects the
province, the master lists and selects).

## 10. Build order

Done: every step below landed (2026-09-13..14); step 4's manor rents were
then replaced by the one integer economy (`ManorEconomy` / `RealmEconomy`,
spec 2026-09-14).

1. Cell index (importer + bake tool + `maps.csv` + tests), and the names:
   `NameForge` (tests: deterministic for a seed, unique across a bank, only
   letters the bank uses, length inside the bank's min/max), `manors.csv`
   baked for beria, the overrides file, and the `manor_code` / label lookup.
2. `MapManors` engine class: province, name, owner, population, rent, price;
   `GameState` fields + save; tests.
3. Orders: data rows, `ActionSystem` validate/execute, tests.
4. `TickEngine` manor rents (superseded by the month's settlement, §5c).
5. Card: `MapObjects.manor_card`, `object_at` manor kind, `MapDetailPanel`
   buildings + action buttons, province card's manors field.
6. MANORS layer: mesh colouring by house, palette, bottom-bar toggle, hover.
7. Manor Master panel.
8. CLAUDE.md, snapshots, full suite.

Each step lands as its own commit; the suite stays green between steps.

## 11. Out of scope (named so they are not forgotten)

Still not built: seizure resolution (needs combat; the regiments have state
since 2026-09-17 but nothing rolls), house treasuries and AI houses trading
among themselves, manor loyalty, and the diplomacy that cross-border
purchases imply. Since built: construction time (§5b), cross-border purchases
(§5c), building art (`bld_*`, §5d).
