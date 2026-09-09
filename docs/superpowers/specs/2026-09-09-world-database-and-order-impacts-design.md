# World Database, Order Costs, and Two-Part Orders — Design

**Date:** 2026-09-09
**Status:** Approved by owner in chat ("yes to all four, go ahead", 2026-09-09).
**Scope:** Five owner requests of 2026-09-09: (1) align the Azgaar export's economic and military data with the game schema; (2) a province view on the map drawn as lighter dashed lines; (3) a domain-organised world database that the model's structured output can move; (4) every order carries a cost; (5) the order prompt returns a natural-language part and a data-impact part that agree with each other.

## Owner rulings (2026-09-09)

1. **Invariants 1 and 2 are amended.** The model may propose world deltas, but only on paths listed in `data/world_schema.csv`, each clamped to that path's `llm_cap`, each carrying a reason. Everything else about the invariants stands: the engine chooses who speaks, executes actions, applies costs, and the model can never invent an action or an unlisted field.
2. **One truth.** The player's dashboard metrics are seeded from the pack, and the player's treasury row in the world database is an alias of `metrics.treasury`. There are no two copies of the same number.
3. **Five domain folders** under the pack: `geography`, `political`, `economy`, `military`, `society`.
4. **The new export is committed** under the pack folder, as the previous export was.

## Context

The pack (`data/maps/beria/`) imports names, geometry, population, and settlement flags. The `Game_dev` export carries much more: per-state treasury, sales and poll tax, urban and rural population, government form, a diplomacy matrix, past campaigns, and named regiments with unit counts; per-burg treasury, product, market id, and settlement group; goods, markets with stock and price, cultures, religions, and hazard zones. None of it reaches the game.

The order pipeline today makes two calls for a typed line: a parse to `{actions, court_reaction}` and, for questions, a separate in-character reply. The model cannot touch state beyond action codes and the tone enum. Several actions are free (tax changes when no minister cares, confiding, consulting), and the court-addition actions with unknown cost formulas execute for nothing.

The render paints province borders as dark dots, but the game draws none, so they never follow conquest.

## Architecture

```
Azgaar JSON ──▶ tools/import_azgaar.gd ──▶ data/maps/<id>/<domain>/*.csv   (starting values, generated)
                                           assets/maps/<id>/*.png            (unchanged)

DataRepository.load_map ──▶ repo.world_tables[domain][area][code] = row  (+ the old named fields as aliases)
WorldLedger (pure)      ──▶ value_of(path) / apply(path, delta, reason, source) over
                            GameState.world (overrides only) + world_log, clamped by data/world_schema.csv
OrderCosts (pure)       ──▶ has_cost(...) / ensure(...) from data/order_costs.csv + data/metric_polarity.csv
OrderPipeline (pure)    ──▶ one order = actions + world impacts + court reaction + cost rule → ledger lines
PromptBuilder.order_prompts / ResponseValidator.parse_order / Voicer.order  ──▶ one call, two-part JSON
WorldMapView            ──▶ province view: MapOwnership.seams_of drawn dashed
```

Determinism holds throughout: the model's JSON is an input, and identical inputs still yield identical state. Nothing here reads the clock or unseeded RNG.

## 1. Data alignment and domain folders

### 1.1 Pack layout

```
data/maps/beria/
  map_info.csv  realm_bindings.csv                      root, unchanged
  geography/  biomes.csv  rivers.csv  markers.csv  routes.csv
  political/  kingdoms.csv  provinces.csv  burgs.csv  borders.csv  province_borders.csv
              diplomacy.csv  campaigns.csv
  economy/    kingdoms.csv  provinces.csv  burgs.csv  goods.csv  markets.csv
              market_goods.csv  production.csv
  military/   kingdoms.csv  regiments.csv  unit_types.csv
  society/    cultures.csv  religions.csv  zones.csv
```

Existing files move with `git mv`; their columns are kept and extended. Each domain folder carries a `.gdignore` so Godot does not import game tables as translations (the per-column `.translation` artifacts the flat files spawn). `FileAccess` reads them regardless. An export preset must include `data/**` explicitly when the game is packaged; noted in CLAUDE.md.

### 1.2 Alignment table

| Export field | Table and column | Notes |
|---|---|---|
| state `form`, `formName`, `fullName`, `culture` | political/kingdoms `form`, `form_name`, `full_name`, `culture_code`, `religion_code` | religion = majority religion of the state's cells by population |
| state `diplomacy[i]` | political/diplomacy `kingdom_code,other_code,stance` | stance as Azgaar writes it: Ally, Friendly, Neutral, Suspicion, Rival, Enemy, Vassal, Suzerain, Unknown; self and neutrals skipped |
| state `campaigns` | political/campaigns `kingdom_code,label,start_year,end_year,attacker_code,defender_code` | neutrals as "" |
| state `treasury`, `salesTax`, `pollTax`, `urban`, `rural` | economy/kingdoms `treasury,sales_tax,poll_tax,urban_population,rural_population` | populations × populationRate, whole numbers |
| province `urban`, `rural` | economy/provinces `urban_population,rural_population` | |
| province `formName`, `fullName`, `color` | political/provinces `form_name,full_name,color` | |
| burg `group`, `culture` | political/burgs `group,culture_code` | group ∈ capital, city, town, village, hamlet, fort, monastery, caravanserai, trading_post |
| burg `treasury`, `product`, `market` | economy/burgs `treasury,product,market_id` | |
| burg `production[].goodId/units` | economy/production `burg_code,good_code,units` | deal references skipped |
| `goods` | economy/goods `good_id,good_code,label,value,tags,unit` | tags pipe-joined |
| `markets` | economy/markets `market_id,center_burg`; economy/market_goods `market_id,good_code,stock,price` | |
| `deals` | not imported | 10,844 simulated trades; nothing in the game reads them |
| state `military[]` | military/regiments `regiment_code,kingdom_code,label,x,y,infantry,archers,cavalry,artillery,fleet,is_naval` | |
| totals of the above, state `alert`, `expansionism` | military/kingdoms `infantry,archers,cavalry,artillery,fleet,regiments,strength,alert,expansionism` | strength = Σ units × unit power |
| `settings.options.military` | military/unit_types `unit_code,label,type,rural_rate,urban_rate,crew,power,separate` | |
| `cultures` | society/cultures `culture_code,culture_id,label,type,expansionism,color` | |
| `religions` | society/religions `religion_code,religion_id,label,type,form,culture_code,deity,urban_population,rural_population,area` | |
| `zones` | society/zones `zone_code,label,type,cells,center_x,center_y,province_codes,kingdom_codes` | provinces touched by the zone's cells |
| coats of arms, cells, vertices, features, notes for regiments | not imported | bitmaps cover geometry; the rest is decoration |

### 1.3 Engine alignment

- `GameState.new_campaign` seeds the player's realm from economy/kingdoms when the row exists: `treasury = round(pack treasury × pack_treasury_scale)`, `tax_rate = clamp(round(poll_tax × tax_rate_per_poll_tax), 1, 10)`, `tariff_rate = clamp(round(sales_tax × tariff_rate_per_sales_tax), 0, 10)`. The three factors live in balance.csv. A pack without the row falls back to `start_treasury` and friends, so hand-built fixtures keep working.
- `DataRepository.world_tables: Dictionary` holds every domain table keyed `[domain][area][code] → row`. The existing named fields (`kingdoms`, `provinces`, `burgs`, `routes`, `rivers`, `markers`, `biomes`) point at the same row dictionaries, so nothing downstream changes. `diplomacy` rows are keyed `"<kingdom>><other>"`; `market_goods` and `production` rows are keyed by `"<owner>:<good>"`.

## 2. The world ledger

### 2.1 Paths

A path names one field: `metrics.<name>`, `opinion.<character_id>`, `attribute.<character_id>.<name>`, or `<domain>.<area>.<code>.<field>` for a pack table. A code segment may be a realm slot (`player_realm`, `raider_realm`, ...), which the ledger resolves through `realm_bindings` before matching.

### 2.2 Schema: `data/world_schema.csv`

Columns: `path,type,min,max,enum_values,good_direction,llm_cap,alias_to,alias_scale_key,label,notes`.

- `path` may use `*` for one segment. The row with the fewest wildcards wins.
- `type` ∈ `float`, `int`, `enum`; enum rows list their legal values pipe-joined in `enum_values`.
- `good_direction` ∈ `1`, `-1`, `0`: which way is good for the crown. `0` means neutral (rates, colours, stances), so a change there is neither a gain nor a cost.
- `llm_cap` is the largest absolute delta the model may move the field by in one order; `0` means engine-only.
- `alias_to` names another path that holds the truth; `alias_scale_key` names a balance key `k` such that `world_value = truth / bal(k)`. Only the player's economy row uses it: `economy.kingdoms.player_realm.treasury → metrics.treasury` (scale 1), `poll_tax → metrics.tax_rate` (`tax_rate_per_poll_tax`), `sales_tax → metrics.tariff_rate` (`tariff_rate_per_sales_tax`).

Initial rows cover: every `metrics.*` the engine owns (with its clamp range and polarity), `opinion.*` (cap 3, the same as tone), `attribute.*.<health|wealth|prestige|influence>` (cap 2), economy kingdoms and provinces populations and treasuries, military kingdoms unit counts and alert, political diplomacy stance (enum, engine-only for now), society religions populations (engine-only).

### 2.3 State and API

- `GameState.world: Dictionary` maps resolved path → value, holding only fields that have moved (the `province_owner` pattern). `GameState.world_log: Array` of `{tick, path, delta, applied, reason, source}`. `SAVE_VERSION` becomes 3; older saves load with both empty.
- `WorldLedger` (RefCounted, static, engine-pure):
  - `resolve(data, path) -> String` substitutes slots.
  - `schema_for(data, path) -> Dictionary` (`{}` when unlisted).
  - `value_of(data, state, path) -> Variant`: alias → truth ÷ scale; override; else the pack row's column parsed by type; `null` when the path has no row.
  - `apply(data, state, path, delta, reason, source) -> Dictionary`: refuses an unlisted path, an empty reason, or a non-numeric type; clamps to `[min, max]`; writes the override or the aliased truth; appends to `world_log`; returns `{path, delta (as applied), value, reason, source}` or `{error}`.
  - `set_enum(data, state, path, value, reason, source)` for enum fields.
  - `prompt_catalog(data, state) -> String`: the model-writable paths for the player's realm with current values and caps, one line each, plus the realm's province codes and its largest burgs (count capped by `order_prompt_max_burgs`).
- `EventEffects` gains two ops so events can hit the same fields: `world:<path>:<delta>:<reason>` and `attribute:<who>:<name>:<delta>:<reason>`.
- `Character.change_attribute(name, delta, reason, tick)` clamps to 0..100 and logs to `attribute_log`, mirroring `change_opinion`.
- `MapOwnership` stays the authority for territory; the schema lists `political.provinces.*.kingdom_code` as engine-only for documentation.

## 3. Order costs

### 3.1 Rule

Every executed order carries at least one cost. A cost is any of: a metric delta against its `good_direction`; an opinion loss on any character; a relationship sentiment loss; an attribute loss; a world delta against its `good_direction`. Tone deltas and kept-promise pseudo-effects are not counted.

### 3.2 Data

- `data/metric_polarity.csv`: `metric,good_direction,notes` for every `GameState.metrics` key (rates and bonuses are `0`).
- `data/order_costs.csv`: `action_code,cost,notes`. `cost` is an effect-op string in the `EventEffects` dialect (`gold:-5`, `opinion:steward:-2:re-cutting the tax rolls`, `attribute:you:prestige:-1:...`, `world:economy.kingdoms.player_realm.rural_population:-2000:levies drawn from the villages`). `none` marks an exempt action: `COUNCIL_CONSULT` (a question, not an order) and `EVENT_CHOICE` (authored effects). A `generic_order` row covers an order that executes no action and whose world impacts carried no cost.
- Every action in the catalog has a row; a test asserts it, and a second test executes each handled action from a fresh campaign and asserts a cost landed.

### 3.3 Where it runs

`OrderCosts.ensure(data, state, effects, drift, opinions_before, action_code, target)` runs at the end of `ActionSystem.execute`, so clicked suggestions and typed orders are charged alike. `opinions_before` is a snapshot the executor takes first, so direct opinion moves count without changing the effects shape. For an order that executed no action but applied world impacts, `OrderPipeline` runs the same check over the impacts and charges `generic_order`. Applied costs are appended to the outcome's `effects` with their reason, so the court log and the day-run narration print them like any other effect.

## 4. Two-part orders

### 4.1 Output shape

```json
{"narrative": "One to three sentences, in the speaker's voice.",
 "impacts": {
   "actions": [{"action_code": "LEVY_RAISE", "params": {}, "target": ""}],
   "world": [{"path": "economy.kingdoms.player_realm.rural_population",
              "delta": -1500, "reason": "levies drawn from the marches"}],
   "court_reaction": {"addressed": [], "tone": "neutral", "promises": []}}}
```

### 4.2 Correlation

- The prompt states the rule both ways: every world impact is something the narrative says happens; the narrative claims no change absent from impacts. Actions are preferred whenever one fits; world impacts are for consequences no action covers. A question or plain talk yields empty impacts and a narrative that answers.
- The validator (`ResponseValidator.parse_order`) requires a non-empty narrative, rejects an impact with no reason, an unlisted path, or a non-numeric delta, and clamps a delta beyond `llm_cap` (noting `clamped`). Rejections are per impact and reported, never fatal; malformed JSON or an unknown action code fails the whole reply as today.
- The engine prints the narrative under the speaker's name and, beneath it, one ledger line per applied effect (`treasury −40: surveyors hired`), then one line per struck impact (`the clerk struck: <path> (<why>)`). A narrative that promises more than the ledger shows is visible as such.
- Empty impacts and no actions make the narrative a conversational reply, remembered by everyone present exactly as replies are today.

### 4.3 Pipeline

- `PromptBuilder.order_prompts(text, speaker_id, report, state, data)`: the speaker's persona sheet (`persona_context`; a herald preamble when nobody is present), `realm_facts`, the legal action catalog, event context, the schema catalog from `WorldLedger.prompt_catalog`, the output shape, and the correlation rules.
- `Voicer.order(...)`: one call on `model_order` (config; `LLM_MODEL_ORDER`, default = the parse tier; `LLM_MODEL` still sets every tier). Offline or failure degrades to `{ok: false, error: "couriers unavailable"}` as the parse does today. `parse_player_text` and `converse` remain for their existing callers and tests.
- `Game.submit_free_text` picks the speaker **before** the call: the character the player faces, else a present character whose name or seat appears in the text, else the Chancellor if present, else anyone present, else the herald. It then runs `OrderPipeline.apply_order` and returns `{ok, executed, rejected, reply: {speaker, speaker_id, text, degraded}, ledger: Array[String], world_effects, world_rejected}`.
- `OrderPipeline.apply_order(data, state, engine, actions, impacts, court_reaction, source)` executes actions through the existing path, applies validated impacts through the ledger, applies the court reaction, runs the pure-impact cost rule, and builds the ledger lines.
- The court screen and the conversation scene print the reply as they print replies today and then each ledger line. The MILITARY and REALM tabs show the player's unit counts and urban/rural population from the ledger.

## 5. Province view

- `MapOwnership.seams_of(data, state, kingdom_code) -> Array` of two-point `PackedVector2Array` segments: the edges walked by exactly two of the loops of the provinces the kingdom holds now. Cached beside the outlines and invalidated with them.
- `WorldMapView.show_provinces` (default off), `toggle_provinces()`, a PROVINCES chip in the view's top-left corner, and the P key. When on and `view_scale() >= map_province_min_scale`, every kingdom's seams are drawn with `draw_dashed_line` in `map_province_line_*` colour, alpha, width, and dash from balance.csv, after the territory tint and before the labels. Off-screen segments are skipped.
- Seams follow conquest: after a province changes hands its former seams become outline edges and vanish from the old owner's view, and it draws no seam against its new neighbours until it shares an owner with them.

## Balance additions (`data/balance.csv`)

`pack_treasury_scale` 1, `tax_rate_per_poll_tax` 36, `tariff_rate_per_sales_tax` 60, `order_prompt_max_burgs` 12, `order_narrative_max_chars` 600, `map_province_min_scale` 0.6, `map_province_line_alpha` 0.55, `map_province_line_width` 1.0, `map_province_dash_px` 4.0.

## Tests (GUT, written first)

- Importer/data: every domain table loads; economy, military, and society rows reference real kingdoms, provinces, burgs, and goods; diplomacy lists every ordered kingdom pair once; military kingdom totals equal the sum of their regiments; unit_types has five units; every zone names real provinces; `world_tables` and the named fields share rows.
- Ledger: slot resolution; wildcard specificity; alias reads and writes hit the metric; clamps and caps; unlisted path and empty reason refused; overrides survive a save round trip; seeding from the pack matches the pack row through the balance factors.
- Costs: every catalog action has a row; each handled action leaves a cost; a positive-only world impact set gets `generic_order`; a cost-bearing set does not; polarity table covers every metric.
- Order pipeline: prompt lists the schema catalog, persona, and correlation rule; validator requires narrative and reasons, clamps caps, rejects unknown paths per impact; a fake client's two-part reply moves state and produces ledger lines; the court screen and conversation scene print reply then ledger lines; speaker pre-selection by name.
- Province view: seams lie on shared province edges and never on the outline; a transfer removes the moved province's seams from the old owner; the toggle and key flip the flag; segments are drawn only above the minimum scale.

## Error handling

- A pack missing a domain folder loads with that domain absent; the ledger returns `null` for its paths and the prompt catalog omits them.
- A schema row naming a column the pack lacks reads `null` and refuses writes with a clear error.
- Model output that is not JSON fails the order as today; per-impact faults are reported in the ledger, and the narrative still prints.

## Out of scope

Trade simulation over goods and deals; AI kingdoms acting on diplomacy; regiments moving on the map; changing the render to drop its printed borders; a key-proxy for the API.
