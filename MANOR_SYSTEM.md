# Manor System — design (2026-09-13, draft for owner review)

The manor is the smallest piece of land in the game: one land cell of the
map pack's Voronoi graph (beria: 3 500 land cells of 4 833). Today it is
only a coloured patch in the ECONOMY view. This document makes it a **unit**:
clickable, with attributes tied to its province, held by a **house**, and
movable — bought, sold, or seized. It follows the owner's rulings of
2026-09-13: owner = house; trade = an offer to the holding house at a formula
price; seizure = data and order skeleton only this round; attributes = the
full set including buildings and taxes; plus a **Manor Master** view listing
every manor on the map.

Everything below obeys the invariants in CLAUDE.md: the engine decides, one
seeded RNG, engine-pure `RefCounted` classes, every change carries a reason,
design values in CSVs, save = one JSON.

---

## 1. Identity and geometry

| Thing | Where it comes from |
|---|---|
| Manor id | the cell id (`cells.csv` `cell_id`), int; stable across runs and saves |
| Which cells are manors | land cells only (`water == ""`); lakes and sea are not manors |
| Province of a manor | fixed geometry: the province index sampled at the cell centre (as `WorldMapView.cell_province` does today), moved into the engine as `MapManors.province_of(data, cell_id)` and cached per repo |
| Hit-testing | a new pack bitmap **`world_cell_index.png`** (R \| G<<8 = cell id, white = none), rasterised by the importer with the same `_rasterize` the province index uses (4 833 ids fit two bytes; the importer asserts `< 65536`). `tools/bake_cell_index.gd` bakes it for the existing pack from `cells.csv` + `vertices.csv`. `data/maps.csv` gains `cell_texture`; `DataRepository.cell_texture_path`; `MapIndex.id_at` decodes it. |
| Name | **every manor has a proper, unique name, in the pack** (owner 2026-09-13: the player has to be able to say "buy Ashcombe"). New pack table `political/manors.csv` (`cell_id,manor_code,label,province_code,burg_code,culture_code`), written by the importer and by `tools/bake_manor_names.gd` for the existing pack. A cell with a burg is named after it ("Shole Manor", `burg_code` set). Every other land cell gets a name **forged in its culture's style**: the Azgaar export carries `nameBases` (43 banks of real place names, e.g. the German bank "Achern, Aichhalden, Aitern…") and each culture's `base`; `NameForge` (engine-pure, tested) runs an order-2 letter Markov chain over the cell's culture's bank — the same method Azgaar named the burgs with, so manors and towns sound like one country — seeded from the map seed and the cell id, so a re-import forges the same names; uniqueness is enforced across the pack, and the code is the label's slug. Hand corrections go in a hand-maintained `manor_name_overrides.csv` (`cell_id,label`) that the loader applies last, so a re-export cannot undo them. Orders and the model refer to a manor by `manor_code`; the validator also accepts the label case-insensitively, so a typed "buy Ashcombe" resolves. |
| Area | polygon area of the cell (native px²) × `distance_scale`² → km², shown as hectares/km² |

## 2. Ownership — houses

- **A house is a family name.** There is no House entity in the engine today
  (houses are `Character.family_name`, `house_bindings.csv`, and
  `MapObjects.house_of`). This round adds no entity either: a manor's owner is
  a family-name string, and "the crown" is the player's family
  (`GameState.player_setup.family_name`, the same string every character of
  the player's house carries).
- **Default owner** of an unmoved manor = the house of its province
  (`MapObjects.house_of`: the `house_bindings.csv` family, else the seat's
  house). So the pack needs no manor table: every manor starts with its
  province's house, exactly as province ownership starts from the pack.
- **State is sparse**, mirroring provinces: `GameState.manor_owner:
  Dictionary {cell_id (String in JSON): family_name}` holds only manors that
  moved; `GameState.manor_log: [{tick, cell, from, to, reason}]`.
  `MapManors.set_owner(data, state, cell_id, family, reason) -> bool` refuses
  unknown cells, water, unknown houses (a house is "known" if any character
  carries the name or any binding names it or it is the player's) and no-op
  moves, and never accepts an empty reason — the same shape as
  `MapOwnership.set_owner`.
- **Province stays the political layer.** Kingdom borders come from
  provinces only; a manor changing house never moves a border. A conquest of
  a province does not reassign its manors (the bindings are per province and
  survive conquest today) — the new kingdom simply contains a province whose
  manors are held by whoever held them. This is deliberate: houses outlive
  crowns.

## 3. Attributes (the manor card)

All derived, none stored, except buildings.

| Attribute | Formula / source | Data |
|---|---|---|
| Province, kingdom, house | `province_of`, `MapOwnership.owner_of`, `MapManors.owner_of` | live |
| Terrain | biome label + height class (lowland / hills / mountain by `map_relief` bands) + coast / river flags (a water neighbour; a river polyline crossing the polygon) | `biomes.csv`, `cells.csv`, `rivers.csv` |
| Land value | `MapEconomy.land_value` (habitability 0..1) | `biomes.csv` |
| Population | the province's **rural** population (ledger `economy.provinces.<p>.rural_population`) apportioned by weight `area × land_value` over the province's land cells, plus the **urban** population of any burg in the cell (`burgs.csv` population, or the ledger's urban share for the seat). Manor populations therefore always sum to the province's — the tie to province data the owner asked for, and nothing to keep in sync. | ledger |
| Production | working manors: `MapEconomy.manors` (goods, dominant good, units); other manors: "subsistence" — no goods row | `production.csv` |
| Buildings | the list in `GameState.manor_buildings {cell_id: [building_code]}`; catalogue in **`data/manor_buildings.csv`** (`building_code,label,cost_gold,civil_cost,build_days,tax_bonus,output_bonus,defence_bonus,church_bonus,gold_per_tick,grain_per_tick,contentment_per_tick,unrest_per_tick,produce_good,produce_units,notes` — `civil_cost` is the one price the game charges and `cost_gold` is unused, kept for the library): manor house, mill, granary, chapel, palisade, market — six to start | new CSV |
| Tax (rent) | A MONTH of whole gold, §4.2 of the spec (`docs/superpowers/specs/2026-09-14-economy-and-staging-design.md`): `round(people / 1000 × manor_tax_per_1000 × tax_rate / tax_rate_base × (1 + Σ tax_bonus))`, plus its town's tariff `round(town_goods_gold × tariff_rate × tariff_per_sales_tax / 100)`. `ManorEconomy.line_of` computes it and `RealmEconomy` sums it; the crown's share is settled into `metrics.treasury` at the month's end (spec §5). Other houses' taxes are shown on the card as what the house earns (no house treasuries exist — the number is information and a price input, not a ledger). | `balance.csv` `manor_tax_per_1000`, `tax_rate_base`, `tariff_per_sales_tax` |
| Defence | `manor_defence_base + Σ defence_bonus` — displayed now, used by the seizure resolution later | `balance.csv` |
| Value (price) | see §5 | `balance.csv` |
| Actions | BUY / SELL / BUILD / SEIZE buttons, shown by legality (§5) | — |

The card is `MapObjects.manor_card(data, state, cell_id)` returning the same
`{kind, code, title, subtitle, kingdom_code, fields, features, production,
center, ask, known, actions}` shape `province_card` returns, so
`MapDetailPanel.show_card` renders it with two additions: a buildings row
(icons from `resource_icons.csv`, glyphs until art exists) and an action row.
`known == "basic"` for manors outside the player's realm, as for provinces.

**The card's face** (owner 2026-09-14): over the card, a third of its height, the painting of the manor's estate (library `B-`, the same industry × size row as its map drawing, `data/manor_estates.csv` `painting`); below the title the attributes above as icons — owner, province, seat, terrain, land, area, people, tax, strategic and civil goods a month, chief good, estate size, defence, slots, value, price — a short value beside each and the full fact in its tooltip (`manor_card.stats`); then **Output a month**, one row per good the manor makes with `+N / mo` and, in the tooltip, what the units are worth and to which pool (`manor_card.rates`, from `ManorEconomy.line_of`).

## 4. Province tie-in

- The province card gains a **Manors** field: "N manors — crown k, House A m,
  House B j" (`MapManors.holdings_of_province`), and a **rents** line.
- Manor populations are shares of the province's numbers (§3), so a ledger
  delta on a province moves every manor in it; nothing is stored twice.
- `WorldLedger.belongs_to_player` is unchanged: the model still only touches
  provinces the crown's kingdom holds. Manor ownership is not a ledger path;
  it moves only through actions (§5), never through a model-proposed delta.

## 5. Orders

New rows in `data/policy_actions_court_additions.csv`, costs in
`data/order_costs.csv`, ideology in `data/action_signatures.csv`. All params
are validated in `ActionSystem.validate` (a manor must exist, be land, be in
the player's realm, and the actor must not already hold it / must hold it);
execution in `ActionSystem.execute`; every effect carries a reason. Clicked
from the card they go `Game.try_execute` and never touch the model; typed,
the model may name them as actions and the same validation applies.

| Order | Params | Legal when | Effect | Costs |
|---|---|---|---|---|
| `MANOR_BUY` | `cell` | not crown-held, and one of (§5c): in a province the crown controls or a province of the realm bordering one — `lord_gold` ≥ price; across the border, a manor whose cell touches the realm — `treasury` ≥ price | inside the realm: owner → crown, `lord_gold` −price. Across the border: `treasury` −price, the manor is annexed into the richest bordering province of the realm (`MapManors.annex`) and held by that province's house. Either way the selling house's characters: opinion +`manor_trade_goodwill`, the head's `wealth` +; `manor_log` "bought from House X for N" | price (formula) + `generic_order` |
| `MANOR_SELL` | `cell` | crown-held | owner → the province's house; `lord_gold` +price × `manor_sell_ratio` | `generic_order` |
| `MANOR_BUILD` | `cell, building` | crown-held, not built yet, the lord's CIVIL stores (`lord_civil`) ≥ the building's `civil_cost` | the work begins (`manor_works`), finishing after `build_days`; `lord_civil` −`civil_cost` | building's `civil_cost` |
| `MANOR_SEIZE` | `cell` | in the player's realm, not crown-held, `manor_seize_enabled` = 1 | **skeleton**: owner → crown with reason "seized by force"; legitimacy −`manor_seize_legitimacy`; unrest +`manor_seize_unrest`; the house's characters opinion −`manor_seize_outrage`; `manor_log`. Resolution is automatic success this round; the defence number and the regiment data are read and displayed but not rolled. When the raid/military system lands (PRD RD-1..3) the outcome tier plugs in here. | `always=1` row |

**Price** (`MapManors.price_of`), every term in `balance.csv`:

```
base   = pop / 1000 × manor_price_per_1000
       + units × manor_price_per_unit            (working manors)
       + Σ building civil_cost × manor_price_building_ratio
land   = 1 + (land_value − 0.5) × manor_price_land_swing
ask    = base × land × markup
markup = 1 + manor_markup_max × (1 − opinion / 100)
```

`opinion` is the selling house's head's opinion of the player when a
character of that house exists (the highest-ranked council member of the
family, else any character of the family), 50 for a house with no character.
So a friendly house sells near base and a hostile one asks up to
`manor_markup_max` more — the same opinion system the council runs on, with
no new ledger.

Signatures: BUY centralism +1, expansionism +1; SELL centralism −1; BUILD
centralism +1; SEIZE militarism +2, centralism +2, orthodoxy −1.

### 5a. Control and the chief good (owner 2026-09-13)

The player is the king of the realm AND the lord of one province. A
province is **controlled** by the house holding the most of its manors
(`MapManors.controller_of`; a tie goes to the province's own house). The
crown starts controlling the capital's province alone (`house_bindings.csv`
binds the royal house to it and nothing else) and gains or loses provinces
manor by manor. Everything that reads as "the crown's economy" is the
controlled provinces: the seeded LORD's purse (their towns' treasuries,
§5c), the dashboard's people and provinces, the ECONOMY column, the ledger
paths the model may write (`WorldLedger.belongs_to_player`) and the order
prompt's "Your provinces". The host stays the realm's. SEIZE works anywhere
in the realm; BUY only where §5c allows; BUILD and FOCUS need a province
the crown controls.

Every manor works one **chief good** (`data/manor_focus.csv`): a focus is
allowed by the cell's biome (and, for fisheries, a sea neighbour); the
default is the first the land allows, and `GameState.manor_focus` holds
only manors whose focus was chosen (`{focus, since}`), logged in
`manor_log` with a `focus` field. Yield a MONTH = people / 1000 ×
`yield_per_1000` × land value × the settling-in ramp (0 on the tick of
the switch, 1 after `transition_ticks`) × (1 + buildings' `output_bonus`)
× the good's growth index, rounded ONCE to whole units
(`ManorEconomy.focus_units`; the old `manor_focus_yield_scale` knob was
retired 2026-09-14 with the float path it scaled). The focus adds nothing
to the tax (the `rent_bonus` column was dropped 2026-09-14: tax is the
buildings' `tax_bonus` alone); its units count in the value like town
trade, and `MapEconomy.output_of_provinces(repo, provinces, state)` sums
every manor's month (`ManorEconomy.line_of`'s units — chief good,
buildings and town together) for the ECONOMY column.

| Order | Params | Legal when | Effect | Costs |
|---|---|---|---|---|
| `MANOR_FOCUS` | `manor, focus` | crown-held, province crown-controlled, focus allowed on the land, not the one it works, `lord_gold` ≥ `switch_cost_gold` | `manor_focus[cell] = {focus, since: tick}`; `lord_gold` −`switch_cost_gold` | `switch_cost_gold` + the reeve's fee |

The card shows "Chief good" and one `WORK <focus> — N gold` button per
allowed focus it does not work; the Manor Master's tooltip names it.

### 5c. Two purses and where land may be bought (owner 2026-09-14)

**Two purses, told apart everywhere.** The CROWN's treasury and stores —
`metrics.treasury`, `strategic`, `grain` (the civil pool), marked with a
crown in the top bar — are the realm's: each month's end pays them
`crown_share_permille` of every province of the realm the player's house
does NOT control, and they pay the ministers' salaries, the court's ration,
the orders' fees and land bought across the border. The LORD's own purse —
`metrics.lord_gold`, `lord_strategic`, `lord_civil`, marked with the house's
arms — is the player's as lord of his own provinces, free to spend: the
provinces the crown controls pay into it in full, with the autumn harvest
and the crown's buildings' `*_per_tick`. `RealmEconomy.purses` is the one
split the settlement (`TickEngine._settle_economy`) and the top bar read. At
the start the lord's gold is what the controlled provinces' towns hold
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
political wash redraw with no new art. The card of a `foreign` border manor
(a "basic" card otherwise) offers its one BUY, and every BUY button names
the purse that pays.

### 5b. Time, works, slots and demolition (owner 2026-09-13)

**The smallest unit of time is a day.** `GameState.day` (1..15) sits under
the tick; the top bar's clock (`||`, `>`, `2x`, `4x` — `time_day_seconds`,
`time_speed_fast/faster`) runs on the court only, in `GameRoot._process`,
and calls `Game.advance_day`: works step, and the fifteenth day's end runs
the tick (`TickEngine.advance` resets the day). A tick that rolls an event
stops the clock and takes the player to the council; there is no End Turn (owner 2026-09-14: play is the only switch)
too. Real time never enters the engine.

**Building takes time and room.** `data/manor_buildings.csv` `build_days`
(palisade 20, granary 25, mill 30, chapel 40, market 45, manor house 60);
`MANOR_BUILD` begins a work — `GameState.manor_works {cell: [{building,
start, days}]}` — that takes a slot until `MapManors.advance_works` moves
it into `manor_buildings`. A manor has `manor_slots_base` slots (+
`manor_slots_burg_bonus` with a town). `MANOR_DEMOLISH` pulls a building
down or stops a work for `manor_demolish_refund` of its `civil_cost`,
returned to the CIVIL STORES (a build is bought with goods, so goods come
back — never gold). The card
draws one box per slot (icon, a dimmed icon with days left, or `+`) with a
cross under each building or work.

**What buildings do** (per finished building, per tick, crown manors):
`gold_per_tick` (market 3), `grain_per_tick` (mill 2, granary 3),
`church_bonus` → church opinion (chapel 0.3), `contentment_per_tick`
(manor house 0.2), `unrest_per_tick` (palisade −0.1), plus the standing
`tax_bonus` / `output_bonus` / `defence_bonus`; `produce_good/units`
(market: cloth 1) join the ECONOMY column. The `*_per_tick` columns are a
MONTH's worth — a tick is a month — and `TickEngine` applies them as their
own ledger lines after the month's settlement.

## 6. Map and views

- **Click**: `MapObjects.object_at` gains a `manor` kind. It is picked when
  the MANORS layer is on or the ECONOMY layer is on (both show manors);
  elsewhere a land click keeps meaning the province/kingdom, so the political
  map does not change behaviour. In those layers a badge still opens the
  burg (as now), and a bare manor opens the manor card in the LEFT column
  (columns divide by kind). Hover names the manor in the tooltip; only a
  clicked manor is ringed.
- **MANORS layer** (the "Manor Master" view): a fourth theme beside
  PROVINCES / HEIGHTS / ECONOMY, on its own bottom-bar toggle, mutually
  exclusive like the others. It draws the manor mesh coloured **by holding
  house**: the crown in the realm's colour, each other house in a hue
  derived deterministically from its name (`MapPalette.house_color`), pale
  outside the player's realm; cell edges ruled as in ECONOMY; no realm tint
  on symbols (thematic rule).
- **Manor Master panel** in the LEFT column while the layer is on (the way
  ECONOMY puts `EconomyPanel` there): a scrollable, sortable table of manors
  — name, province, house, population, rent, value, buildings, production —
  defaulting to the player's realm (hundreds of rows), with a house filter
  and an "all realms" toggle (thousands; a `Tree` handles it), and a totals
  line (manors held by the crown, taxes per month). Clicking a row centres the
  map on the manor and selects it, so the card opens beside the table.
  Everything wraps or scrolls inside `ScreenLayout.LEFT_WIDTH`.

## 7. Save

`GameState`: `manor_owner`, `manor_buildings`, `manor_log` added to
`to_dict` / `from_dict` with `.get` defaults (old saves load), keys as
strings in JSON and re-int'd on load, numeric leaves through
`_encode_values`. `SAVE_VERSION` unchanged (additive).

## 8. Data files touched

| File | Change |
|---|---|
| `assets/maps/beria/world_cell_index.png` | new, generated |
| `data/maps/beria/political/manors.csv` | new, generated: one named manor per land cell (§1) |
| `data/maps/beria/manor_name_overrides.csv` | new, hand-maintained, never written by the importer |
| `scripts/engine/name_forge.gd` | new: the Markov name forge over the export's `nameBases` |
| `data/maps.csv` | `cell_texture` column |
| `data/manor_buildings.csv` | new catalogue |
| `data/balance.csv` | `manor_tax_per_1000`, `manor_price_per_1000`, `manor_price_per_unit`, `manor_price_building_ratio`, `manor_price_land_swing`, `manor_markup_max`, `manor_sell_ratio`, `manor_trade_goodwill`, `manor_defence_base`, `manor_seize_enabled`, `manor_seize_legitimacy`, `manor_seize_unrest`, `manor_seize_outrage`, `manor_master_max_rows` |
| `data/policy_actions_court_additions.csv`, `order_costs.csv`, `action_signatures.csv` | four orders |
| `data/political_palette.csv` | `manor_crown`, `manor_foreign`, house hue ramp keys |
| `data/resource_icons.csv` | rows for the six buildings (glyphs) |

## 9. Tests (written before the code, hand-computed values)

- `test_map_manors.gd`: default owner is the province's house; `set_owner`
  refuses water / unknown house / no-op / empty reason and logs; population
  apportionment sums to the province's rural + urban; price formula on a
  fixture (pop 2 000, 40 units, one building, land 0.8, opinion 20 → the
  exact number); rent; name derivation; holdings per province.
- `test_action_system.gd`: BUY refuses foreign / own / unaffordable, moves
  owner, debits treasury, logs, lifts the seller's opinion; SELL; BUILD
  refuses duplicates; SEIZE gated by the flag and charges legitimacy and
  unrest.
- `test_map_index.gd` / `test_map_pack.gd`: the cell index exists at canvas
  size and returns each land cell's id at its centre.
- `test_game_state.gd`: round-trip of the three new fields, old-save load.
- `test_world_map_view.gd`: a click in the MANORS layer selects a manor and
  the card shows its fields; in the political view the same click selects
  the province; the master panel lists the realm's manors and a row click
  selects one.
- `test_tick_engine.gd`: crown manor rents reach the treasury with a reason.

## 10. Build order

1. Cell index (importer + bake tool + `maps.csv` + tests), and the names:
   `NameForge` (tests: deterministic for a seed, unique across a bank, only
   letters the bank uses, length inside the bank's min/max), `manors.csv`
   baked for beria, the overrides file, and the `manor_code` / label lookup.
2. `MapManors` engine class: province, name, owner, population, rent, price;
   `GameState` fields + save; tests.
3. Orders: data rows, `ActionSystem` validate/execute, tests.
4. `TickEngine` manor rents.
5. Card: `MapObjects.manor_card`, `object_at` manor kind, `MapDetailPanel`
   buildings + action buttons, province card's manors field.
6. MANORS layer: mesh colouring by house, palette, bottom-bar toggle, hover.
7. Manor Master panel.
8. CLAUDE.md, snapshots, full suite.

Each step lands as its own commit; the suite stays green between steps.

## 11. Out of scope this round (named so they are not forgotten)

Seizure resolution (needs the military system), house treasuries and AI
houses trading among themselves, manor loyalty, construction time, cross-
border purchases and the diplomacy they imply, building art (glyphs first).
