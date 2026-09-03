# Beria Map Integration — Design

**Date:** 2026-09-03
**Status:** Approved by owner (chat), pending spec review
**Scope:** Import the Azgaar "Beria" map exports in `assets/maps/` into game data, and add a clickable pan/zoom world-map screen.

## Context

The owner exported a world from Azgaar's Fantasy Map Generator (v1.150.0) into `assets/maps/`:

- `Beria 2026-09-03-20-03.png` — rendered map, 2560×929 RGBA, state names painted in.
- `Beria Full 2026-09-03-20-04.json` — full export: 17 states, 250 provinces, 841 burgs, 11 cultures, plus cells/vertices geometry. JSON coordinates are 1:1 with the PNG pixels (`info.width`/`info.height` match).
- `Beria 2026-09-03-20-03.map` — Azgaar's own save file; not consumed by the game, kept as the editable source.

The game's fiction already names four kingdoms in `roles.csv`: `averlain` (the player's realm), `bentleigh`, `doncaster`, `empire`. The current Beria states carry Azgaar's generated names (Axalalamotco, Hitia, …).

### Owner rulings (2026-09-03)

1. **Scope:** map screen **and** world-data import (not display-only).
2. **Name reconciliation:** the owner will reopen the `.map` in Azgaar, rename four chosen states to Averlain / Bentleigh / Doncaster / Empire, and re-export PNG + JSON. The import pipeline must be re-runnable so the renamed export is a re-run, not a rework.
3. **Map entry point:** the bottom bar's MAP tab is repurposed to toggle a full-screen map overlay (supersedes the 2026-08-30 ruling that MAP only closes overlays; other tabs still close the map).
4. **Import depth:** states + provinces + burgs (full depth).
5. **Interactivity:** pan/zoom viewer with clickable **states** (not provinces) opening an info panel.
6. **Hit-testing:** approach A — a rasterized state-index bitmap generated at import time (no polygon code in GDScript).

## Architecture

```
assets/maps/*.json ──▶ tools/import_azgaar.py ──▶ data/kingdoms.csv
assets/maps/*.png  ──▶        │                    data/provinces.csv
                              │                    data/burgs.csv
                              ├──▶ assets/maps/world_map.png          (stable path copy)
                              └──▶ assets/maps/world_state_index.png  (hit-test bitmap)

DataRepository.load_all() ──▶ repo.kingdoms / repo.provinces / repo.burgs
GameRoot ──owns──▶ MapScreen (overlay) ──reads──▶ repo + world_map.png + index png
```

The engine's behavior does not change: the imported tables are static reference data. Nothing enters the save file, no RNG, no LLM involvement (invariants 1–2, 5 untouched).

## Components

### 1. Importer — `tools/import_azgaar.gd`

> **Amendment (2026-09-03, owner request):** the importer is a headless GDScript tool (`extends SceneTree`), not Python, so the whole repo speaks one language. Run:
> `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/import_azgaar.gd [-- --json PATH --png PATH]`
> Everything below (inputs, outputs, columns, encoding, warnings, determinism) is unchanged; the original Python version produced byte-identical CSVs and a pixel-identical bitmap before being removed. Section text below still says "Python" where it describes the original plan.

Python 3, stdlib + Pillow (Pillow is already used by the existing `tools/*.py`). Deterministic: same inputs ⇒ byte-identical outputs.

**Input selection:** newest `*Full*.json` and newest `Beria*.png` (excluding `world_map.png` / `world_state_index.png`) in `assets/maps/`, overridable with `--json` / `--png` flags. Fails with a clear message if either is missing or if `info.width`/`info.height` don't match the PNG dimensions.

**Outputs (all committed to git):**

- `data/kingdoms.csv` — one row per state, `Neutrals` (state 0) excluded:
  `kingdom_code,state_id,label,capital_burg,neighbor_codes,color,area,population`
  - `kingdom_code` = slugified state name (lowercase, non-alphanumeric → `_`). After the owner's rename-and-re-export, the four fiction kingdoms line up with `roles.csv` automatically.
  - `state_id` = Azgaar's numeric state id, the join key for the hit-test bitmap.
  - `neighbor_codes` = pipe-separated kingdom codes from Azgaar's state `neighbors`.
  - `population` = rural + urban, scaled by `settings.populationRate`.
- `data/provinces.csv` — `province_code,label,kingdom_code,capital_burg,area,population`. `province_code` = slugified name, suffixed `_2`, `_3`… on collision (250 generated names will collide).
- `data/burgs.csv` — `burg_code,label,province_code,kingdom_code,population,is_capital,is_port` (booleans as `1`/`0`; `burg_code` slugified with the same collision rule; removed burgs skipped).
- `assets/maps/world_map.png` — byte copy of the input render. Game code references only this stable name, so datestamped re-exports never touch game code.
- `assets/maps/world_state_index.png` — same dimensions as the map. Each land cell polygon (`pack.cells.v` indices into `pack.vertices`) is filled with a flat color encoding its cell's state id: `R = id & 0xFF`, `G = (id >> 8) & 0xFF`, `B = 0`, alpha 255. Water/unassigned pixels are `(255,255,255)` (sentinel: no state; state ids in Azgaar practice stay far below 65535).

**Validation on run:** every province's `state` exists, every burg's `cell`→province resolves; warns (does not fail) if any of `averlain`/`bentleigh`/`doncaster`/`empire` is absent — expected until the renamed re-export lands.

### 2. Godot import settings

`world_state_index.png` must survive with exact pixel values: its `.import` file is committed with **Lossless** compression mode (no VRAM compression). At runtime the screen calls `texture.get_image()` on the imported texture — no raw file loading, so exported builds work unchanged. `world_map.png` uses default import settings.

### 3. Engine — `DataRepository` additions

Three new fields, loaded with the existing `_load_if_present` pattern (absent files stay non-fatal, matching `regions`/`locations`):

```gdscript
var kingdoms: Dictionary = {}   # kingdom_code -> row
var provinces: Dictionary = {}  # province_code -> row
var burgs: Dictionary = {}      # burg_code -> row
```

Required columns: `kingdoms.csv` → `kingdom_code,label,capital_burg`; `provinces.csv` → `province_code,label,kingdom_code`; `burgs.csv` → `burg_code,label,province_code,kingdom_code`. No `GameState`, save, or tick changes.

### 4. UI — `scripts/ui/map_screen.gd` (`MapScreen`)

A full-rect `Control` overlay, built in code like `InfoScreen`/`RelationshipGraphScreen`, owned by `GameRoot`, hidden by default, sitting below the pause menu and above screens.

- **Routing (`GameRoot._on_bottom_tab`):** `"MAP"` toggles the map overlay (and hides the info screen / relations graph); every other tab hides the map. ESC/close button hides it. Not available in `State.MENU` (same guard as the relations graph).
- **Pan/zoom view:** a clipped `Control` that draws `world_map.png` via `draw_texture_rect` under a pan offset + zoom scale. Drag pans; mouse wheel zooms toward the cursor (zoom clamped ~0.5×–4×, pan clamped so the map never fully leaves the viewport). Initial view: fit height.
- **Hit-testing:** on click, view transform → map pixel → `index_image.get_pixelv()` → state id (`r + (g << 8)` from the 8-bit channels; white sentinel = no state). The id resolves to a `kingdoms.csv` row via an id→code lookup built at import time — the importer writes a `state_id` column into `kingdoms.csv` for this join.
- **Info panel:** right-side panel (UiPalette styling) showing the clicked kingdom's label, capital burg, province count, town count, population, neighbors — and the characters whose `roles.csv` `kingdom` matches the code, listed by display name. Clicking water/`Neutrals` clears the panel. The panel reads `Game.repo` only; it never mutates state (invariant 3: MapScreen is view-only).

### 5. Tests (GUT, written before the UI per project convention)

- `tests/engine/test_map_data.gd`:
  - `kingdoms.csv`/`provinces.csv`/`burgs.csv` load through `DataRepository`.
  - Referential integrity: every province's `kingdom_code` exists; every burg's `province_code` and `kingdom_code` exist; every kingdom's `capital_burg` exists in burgs; every `neighbor_codes` entry resolves.
  - `world_state_index.png` exists and its dimensions equal `world_map.png`'s.
  - A known sampled pixel (a state capital's burg coordinates from the JSON, hard-coded at import review time) decodes to that state's `state_id`.
- `tests/ui/` smoke test: MAP tab toggles `MapScreen` visibility; other tabs hide it; hidden in MENU state.
- Headless-safe: all tests read committed files, no network, `CC_FORCE_OFFLINE` irrelevant (no LLM path exists here).

## Error handling

- Importer: hard-fails (non-zero exit, message) on missing/mismatched inputs or broken references in the JSON; warns on missing fiction-kingdom codes.
- Game: missing CSVs or PNGs degrade gracefully — `_load_if_present` keeps the repo loading, and `MapScreen` shows a "No map imported" label instead of the viewer if `world_map.png` is absent, so the game never crashes on a clean checkout of a branch without assets.
- Clicks that decode to an id with no matching kingdom row (stale index vs. CSVs) clear the panel silently.

## Migration / re-export flow

1. Owner renames four states in Azgaar (Averlain, Bentleigh, Doncaster, Empire), optionally culls others, re-exports PNG + full JSON into `assets/maps/`.
2. Re-run `python3 tools/import_azgaar.py`.
3. Commit regenerated CSVs + PNGs. The importer's missing-kingdom warning disappears; no code changes.

Until then, the pipeline is built and tested against the current exports (the warning fires; the sampled-pixel test uses whatever state names currently exist).

**Hand-edits to the generated CSVs are overwritten on re-import** — lasting changes belong in Azgaar (names, borders) or in new columns added by the importer. If a column must be hand-authored later, it moves to a separate overlay CSV rather than editing generated rows.

## Out of scope

Province-level clicking, hover highlighting (the index bitmap enables it later; not built now), armies/movement, map-driven actions, travel costs between regions, any simulation or save-format change, culture/religion/river import.
