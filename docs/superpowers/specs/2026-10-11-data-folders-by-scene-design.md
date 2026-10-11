# Data folders by scene — design

Date: 2026-10-11. Status: draft for the owner's review.

## Why

The owner tunes the game by hand. Today `data/` is 106 flat CSVs plus one
1034-row `balance.csv` in which ~330 gameplay numbers sit among ~700 camera,
ink, pixel and fade values. Finding "what am I changing" means reading
prefixes. Goal: open one folder per part of the game and see every table and
every number that drives it; the screens' look lives apart, so a balance pass
never wades through it.

## What the owner ruled (2026-10-11)

- Split by the kind of thing being tuned, with readable folder names, by scene.
- Each scene folder carries its own `balance.csv` beside its tables (not one
  separate balance folder).
- Stay with CSV (notes per key, opens in a spreadsheet, row-level errors);
  no JSON.

## Layout

```
data/
  tables.csv        index: folder,table — the one place a table's folder is named
  CLAUDE.md
  realm/            the realm's rule: laws, decrees, order costs, metric polarity,
                    action signatures, domain policies, world schema
  ledger/           the LEDGER's data model (objects, links, loops, clusters, actions)
  council/          seats, founding council, traits, relationships, roles,
                    faction escalation, court policies, minister line templates
  economy/          manors, estates, focus, buildings and their inputs, goods,
                    workshops, road speed
  army/             the army_* tables, foraging/desertion words, march hazards,
                    war plan kinds, war order words, war works
  battle/           battle outcomes, stances, enemy AI doctrines
  intel/            spies, couriers, intel facts, facts, claim types, world rules
  story/            random events and choices, the prologue's events and branches,
                    presenters, locations, regions
  world/            weather and its odds, landmark names, marker types, the pack index
  screens/          the look only — nothing here changes the game's outcome
    ui/  map3d/  war_room/  ledger/
  maps/<id>/        map packs — unchanged
```

Every folder above may hold a `balance.csv` (`key,value,notes`, the schema of
today's file). The exact placement of all 106 tables is
`2026-10-11-data-folders-table-map.csv`; of all 1034 keys,
`2026-10-11-data-folders-key-map.csv` (columns: folder, key, value, who reads
it, how it was found, why it landed there, notes). Approximate key counts:
army 117, council 36, economy 39, intel 30, realm 29, battle 25, world 7,
ledger 2, story 2; screens/war_room 302, screens/ui 177, screens/map3d 151,
screens/ledger 121.

### How a key was placed

By who reads it, not by its prefix:

- read by `scripts/engine` or `scripts/llm`, or named by a data table's cell
  (`law_effects.amount`, event ops, `war_plan_kinds`) → the gameplay folder of
  the thing it tunes. A key the screens also read stays here.
- read only by `scripts/ui`, `scripts/map3d`, `scripts/war_room`,
  `scripts/ledger3d` → `screens/<that screen>/`.
- read only by a bake tool → the folder of what the bake feeds (the march
  grid's keys → `army/`, the map's relief and biome bakes → `screens/map3d/`).
- `war_*` keys the engine reads (the war sheet's grid, plan limits, trade
  tiers, mark reach) → `army/`; the WAR ROOM's camera, ink and pieces →
  `screens/war_room/`.
- LLM caps (`prompt_*`, `order_*`, `tone_delta_cap`) → `council/`.

## Mechanics

1. **One index.** `data/tables.csv` (`folder,table`) lists every table once.
   `DataRepository.table_path(dir, "army_speed")` resolves through it; every
   loader call, `@tool` path, test and Godot tool goes through it, and the
   Python bakes read the same CSV. Moving a table later is one row.
2. **Balance loads from every folder.** `DataRepository` reads each
   `<folder>/balance.csv` the index's folders name (sorted, fixed order) into
   the one `balance` dict. `bal()` and its ~1100 callers do not change; tests
   that set `Game.data.balance[k]` keep working. `load_look` reads the same
   files.
3. **A key in two files fails the load**, naming both files.
4. **Tools.** `tools/bake_settlements.gd`, `bake_relief.gd`,
   `bake_biome_weights.gd` and `tools/map3d/bake_march_grid.py`,
   `bake_world.py` read balance through the index instead of
   `data/balance.csv`.

## Guards (tests/engine)

- `tables.csv` and the disk agree: every CSV under `data/` (outside `maps/`)
  is listed exactly once, every listed table exists, and no `balance.csv`
  sits in a folder the index does not name.
- No key repeats across the `balance.csv` files.
- `scripts/engine` reads no key from `screens/*/balance.csv`, except a named
  list in the test — the 21 keys the engine's own look helpers read today
  (`map_manor_*`, `map_relief_*`, `map_light_*`, `map_lod_*`,
  `map_terrain_blend`, `map_altitude_gain`, `province_card_max_towns`,
  `ui_war_table`), each with its reason.
- `test_data_csv_shape` walks `data/` recursively.

## Documentation

- `data/CLAUDE.md`: the folder table, "a new table gets a `tables.csv` row in
  the folder of the scene it serves; a new number goes into that folder's
  `balance.csv`; a number only a screen reads goes under `screens/`".
- `data/CLAUDE.md`'s "`balance.csv` holds every tuning number", the root
  `CLAUDE.md`'s `data/*.csv` (→ `data/`) and the nested guides'
  "`balance.csv` key …" mentions name the folder's `balance.csv`. Table names in prose stay as they are (the index finds them).
- Dated specs and plans are history and stay untouched.

## Out of scope

- Deleting the 15 keys no game code reads: the 8 `war_hud_*`,
  `war_plan_ring_min_mm`, `map_show_markers`, `map_lod_marker_scale`,
  `map_pick_radius_px`, `map_line_pick_px` (only a test's stand-in dict names
  these four), `raid_appear_day` (a test only checks it exists; each host's
  day is `raid_hosts.csv`'s `appear_day`) and `war_hover_budget_ms` (a test's
  performance budget). They move with their folder and wait for a ruling.
  (`map_compass_*_table` are live: `MapPalette.table_key` reads them on the
  war table.)
- Renaming any table or key; difficulty presets; the map pack layout.

## Testing and landing

`./run_tests.sh --fast`, then `tests/ui`, `tests/map3d`, `tests/war_room`
with GUT (they load the look tables); a dry run of the two Python bakes'
balance read. No look changes, so no visual-review. One PR against `main`,
committed in order: index and loader, the `git mv` of the tables, the balance
split, tools, docs — so `git log --follow` keeps each table's history.
