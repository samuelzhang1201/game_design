# Map Objects — Design

**Date:** 2026-09-08
**Status:** Approved by owner in chat ("go", 2026-09-08) with the recommended scope; written up here for the implementation plan.
**Scope:** Make the world map's towns, roads, rivers, points of interest, and terrain hoverable and clickable, each opening an info card with an "Ask the council" hook. Companion to the kingdom border-on-hover change landed the same day (borders.csv).

## Context

The world map (`WorldMapView`, embedded in the court, conversation, and day-run screens) renders one flattened Azgaar PNG and hit-tests kingdoms through `world_state_index.png`. The render already paints relief, rivers, roads, trails, sea routes, province borders, and town labels — but no town icons (Azgaar's burg-icon layer was off at export), and nothing on it is interactive except kingdoms.

The Azgaar full export (`assets/maps/*Full*.json`) carries everything needed as data: 841 burgs with type and feature flags, 677 routes (18 roads, 499 trails, 160 sea routes) as polylines, 224 named rivers as cell chains, 66 markers (volcanoes, mines, ruins, inns…) each with a legend note, 13 biomes, and 250 provinces with numeric ids.

### Owner rulings (2026-09-08)

1. Kingdom border highlight on hover — vector loops from the importer, not a shader (landed separately).
2. No new sprite assets: the PNG stays the single visual layer; pins and highlights are drawn in `_draw`.
3. Terrain scope: a land card (biome + province + kingdom + nearest town) plus rivers and markers as discrete objects. Lakes and mountain ranges as objects are out of scope.
4. Click payoff: an **Ask the council** button on every card that pre-fills the order/talk box with a question about the place. It never sends by itself (no surprise API spend) and rides the existing free-text path.

## Architecture

```
Azgaar JSON ──▶ tools/import_azgaar.gd ──▶ data/maps/<id>/burgs.csv      (+type, features)
                                          data/maps/<id>/provinces.csv  (+province_id)
                                          data/maps/<id>/routes.csv
                                          data/maps/<id>/rivers.csv
                                          data/maps/<id>/markers.csv
                                          data/maps/<id>/biomes.csv
                                          data/maps/<id>/map_info.csv
                                          assets/maps/<id>/world_province_index.png
                                          assets/maps/<id>/world_biome_index.png

DataRepository.load_map ──▶ repo.routes / rivers / markers / biomes / map_info (+ parsed polylines, bboxes)
MapGeometry (pure)      ──▶ parse_points, distance_to_polyline, polyline_length
MapObjects (pure)       ──▶ object_at(...) hit-test with priority; describe(...) card text
WorldMapView (Control)  ──▶ pins + LOD, hover highlight + tooltip, cards via MapInfoCard,
                            signal place_asked(text) ──▶ CourtScreen / ConversationScene fill the input
```

Invariants hold: nothing here touches `GameState`, the save, the RNG, or the LLM. The only new player-facing text that reaches the model is what the player chooses to submit from the pre-filled box, through `Game.submit_free_text` exactly as typed orders do today.

## Components

### 1. Importer additions (`tools/import_azgaar.gd`)

All outputs deterministic and committed; `maps.csv` unchanged (paths for the two new bitmaps derive from the pack's art dir: `<index_texture dir>/world_province_index.png`, `.../world_biome_index.png`).

- **`burgs.csv`** gains `type` (Azgaar burg type: Generic, Naval, Lake, River, Highland, Hunting, Nomadic) and `features` (pipe list drawn from the flags that are set: `walls|citadel|temple|plaza|shanty`).
- **`provinces.csv`** gains `province_id` (Azgaar `i`), the join key for the province bitmap.
- **`routes.csv`**: `route_code,label,group,from_burg,to_burg,length,points`. `route_code` = slug of the route name, collision-suffixed. `group` ∈ `roads|trails|searoutes`. `from_burg`/`to_burg` = the burg within 3 native px of the first/last point, else empty (78% of endpoints snap). `length` = polyline length in native px, one decimal. `points` = `"x y|x y|..."`.
- **`rivers.csv`**: `river_code,label,type,length,kingdom_codes,points`. Points are the centers of the river's cells in order; `kingdom_codes` = distinct kingdoms of those cells in first-seen order.
- **`markers.csv`**: `marker_code,label,type,x,y,legend`. `label` = the note's name (fallback: humanized type); `legend` = the note's text with line breaks collapsed to single spaces. All 66 markers have notes.
- **`biomes.csv`**: `biome_id,label,color,habitability` (13 rows; 0 = Marine is water).
- **`map_info.csv`**: `key,value` — `width`, `height`, `distance_unit`, `distance_scale`, `population_rate`. Lets cards print real distances ("142 mi") instead of pixels.
- **`world_province_index.png`**: same rasterizer and encoding as the state bitmap (`R | G<<8` = province id, pure white = none).
- **`world_biome_index.png`**: `R` = biome id, `G = B = 0`, pure white = water/none. Only land cells (biome ≠ 0) are filled.

### 2. Engine

- **`DataRepository.load_map`** adds `routes`, `rivers`, `markers` (keyed by code), `biomes` (keyed by int id), `map_info` (String→String), and `province_texture_path` / `biome_texture_path`. Route and river rows get two derived fields at load: `polyline: PackedVector2Array` and `bbox: Rect2`, so hit-testing never re-parses text. All files load through `_load_if_present` (a pack without them still runs, with those layers absent).
- **`MapIndex`** gains a generic `id_at(img, px)` (identical decode; `state_at` stays as the named alias) and `biome_at(img, px)` (R channel; white → -1).
- **`MapGeometry`** gains `distance_to_polyline(p, pts) -> float` and `polyline_length(pts) -> float`.
- **`MapObjects`** (new, `RefCounted`, static, engine-pure):
  - `object_at(repo, state_img, province_img, biome_img, native: Vector2, pick_radius: float, line_radius: float, min_burg_pop: int) -> Dictionary`. Priority: marker pin → burg pin (capitals always; others only if `population >= min_burg_pop`) → route line → river line → land (`{kind:"land", state_id, province_id, biome_id}`) → `{kind:"water"}`. Among pins the nearest wins; among lines the nearest wins. Radii are in native px (the view converts from screen px by dividing by its scale).
  - `nearest_burg(repo, native) -> String`.
  - `min_burg_pop_for_scale(repo, scale) -> int` — the LOD rule from `balance.csv`: below `map_lod_town_scale` only capitals; from there towns with `population >= map_lod_town_pop`; from `map_lod_village_scale` everything. `scale` = screen px per native px (`_zoom * _render_scale`).
  - `describe(repo, obj) -> Dictionary {title, lines: Array[String], ask: String}` — the card text per kind (below). Pure string building, unit-tested.

### 3. View (`WorldMapView` + new `MapInfoCard`)

- **Draw order** in `_draw`: map texture → hovered kingdom outline (existing) → hovered/selected line glow (routes and rivers are already painted in the render; only the highlighted one is redrawn, as a dark halo + gold polyline) → burg pins passing the LOD rule → marker pins (from `map_lod_marker_scale`) → hovered pin ring → tooltip.
- **Pins** are drawn in screen px (constant size at any zoom): capital = 4 px filled circle with a ring, town = 2.5 px, village = 1.5 px, all `UiPalette.GOLD` with a dark outline; marker = 3 px diamond in `UiPalette.TOOL_PERSONAL`. No textures.
- **Hover**: on mouse motion the view resolves `MapObjects.object_at` and, if the object changed, redraws and updates a tooltip `Label` anchored beside the cursor with the object's label (kingdom hover keeps the border outline it already has; a pin over a kingdom shows both).
- **Click** (press/release without drag, as today) opens the card for the object under the cursor; water closes it. `select_state` keeps working for kingdoms (tests depend on it) and new `select_object(obj: Dictionary)` covers the rest.
- **`MapInfoCard`** (`scripts/ui/map_info_card.gd`, `PanelContainer`) takes over the card the view builds today: `show_entry(title, lines, ask_text)`, `ask_button_visible`, signals `ask_requested(text)` and `closed`. The Ask button is hidden until a screen calls `world_map.set_ask_enabled(true)`; the day-run screen has no input box and leaves it off.
- **`signal place_asked(text: String)`** on `WorldMapView`. `CourtScreen` fills `free_text` and focuses it; `ConversationScene` does the same with its talk box. Nothing is submitted until the player presses Enter.

### 4. Card text (`MapObjects.describe`)

| kind | title | lines | ask |
|---|---|---|---|
| kingdom | label | Capital, Provinces, Towns, Population, Neighbors, Court (as today) | "What do we know of {label}?" |
| burg | label | "Capital of {province}, {kingdom}" or "Town in {province}, {kingdom}"; "Population: N"; features in words (Port, Walled, Citadel, Temple, Plaza, Shanty town); "Roads: n" if any route ends here | "What do we know of {label}?" |
| route | label | "Road" / "Trail" / "Sea route"; "From {burg} to {burg}" (only the known ends); "Length: N {unit}" | "What do we know of the {label}?" |
| river | label | "River" / "Fork" / …; "Length: N {unit}"; "Flows through: {kingdoms}" | "What do we know of the {label}?" |
| marker | label | humanized type ("Hot springs"); legend text | "What is known of {label}?" |
| land | province label | kingdom label; "Terrain: {biome}"; "Nearest town: {burg} ({dist} {unit})" | "What do we know of {province}?" |

Distances: native px × `distance_scale`, rounded to whole units, unit from `map_info.csv`.

### 5. Balance values (`data/balance.csv`)

`map_lod_town_scale` 0.5, `map_lod_village_scale` 1.0, `map_lod_marker_scale` 0.5, `map_lod_town_pop` 5000, `map_pick_radius_px` 6, `map_line_pick_px` 4. Screen px radii are divided by the view's scale before hit-testing.

### 6. Tests (GUT, headless; written before code per project convention)

- `test_map_data`: routes/rivers/markers/biomes/map_info load; every route end and river kingdom resolves; every marker lies inside the map; for every province its capital burg's pixel decodes to its `province_id` in the province bitmap; every kingdom center decodes to a land biome (1..12) in the biome bitmap; both new bitmaps match the state bitmap's size.
- `test_map_geometry`: `distance_to_polyline` and `polyline_length` with hand-computed values.
- `test_map_objects`: priority and LOD with a hand-built tiny repo (one capital, one village, one route through both, a marker); with real data: Kuojarpan's coordinates resolve to `kuojarpan`, a known route point resolves to that route, `describe` for a hand-picked burg yields the expected title and first line.
- `test_world_map_view`: pins pickable set shrinks at low scale and grows at high; hovering a burg position sets the hovered object and tooltip text; clicking a burg opens a card titled with its label; the Ask button emits `place_asked` with the described text; `CourtScreen` puts that text into its order box.

## Error handling

- A pack missing any new CSV or bitmap simply lacks that layer: `object_at` skips absent collections, `hover_loops`-style lookups return empty, pins are not drawn. Nothing crashes on a stripped pack.
- Stale bitmaps (ids with no matching row) resolve to `{kind:"water"}` for provinces/biomes and close the card, as unknown states do today.
- The importer hard-fails on a route whose points are empty or a marker without coordinates; it warns (not fails) when a marker has no note.

## Build order (one commit each)

1. Importer + repository + data tests.
2. `MapGeometry`/`MapIndex` helpers + `MapObjects` hit-test and `describe` + unit tests.
3. View: pins with LOD, hover highlight and tooltip + tests.
4. `MapInfoCard` extraction and per-kind cards + tests.
5. `place_asked` wiring in court and conversation screens + tests; CLAUDE.md generated-files note.

## Out of scope

Lakes and mountain ranges as objects; layer toggles (political/terrain); map-driven actions or travel costs; any sim, save, or LLM change; drawing our own roads/rivers where the render already shows them.
