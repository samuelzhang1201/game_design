# Crown and Council

Text-first, LLM-narrated grand strategy game: rule a kingdom for ~60 years through a council of ministers with real personalities, ideologies, and grudges. Godot 4 project. The campaign map is the **3D map** (Terrain3D, `scripts/map3d/`, built by `tools/map3d/`) — the ONLY map; the 2D map was deleted (2026-09-24) and is never to come back. A checkout with no built world shows the 3D view's notice naming `build_pack.sh`.

## How the guidance is split (read this first)

This file holds only what holds EVERYWHERE. Each subsystem's rules live in a `CLAUDE.md` beside its code, which Claude Code loads when you read a file in that directory:

| File | Covers |
|---|---|
| `scripts/engine/CLAUDE.md` | the simulation: manors and the economy, time, events and the prologue, regiments, couriers, weather, intel / missives / spies, governors, supply, industry and trade, the LEDGER's data model |
| `scripts/map3d/CLAUDE.md` | the 3D map: build and loading, camera, picking, borders, roads, water, sky, weather visuals, woods, fields, houses, the regiment pieces, HUD, performance gates |
| `scripts/ui/CLAUDE.md` | screens and HUD: the look-in-editor conversion, theme kinds, fonts, the war table, the council row, cards, bars, title and landing, menus, window-size rules |
| `scripts/war_room/CLAUDE.md` | the WAR ROOM plotting-room screen |
| `scripts/ledger3d/CLAUDE.md` | the LEDGER galaxy view |
| `tools/CLAUDE.md` | art and build pipelines: Flux / ComfyUI, installers, arms, portraits, house and unit models, bakes, `snapshot_screen`, benches |
| `data/CLAUDE.md` | the CSV tables and the map pack tables |

**Writing guidance:** a feature's detail goes into its subsystem's `CLAUDE.md` or its spec under `docs/superpowers/specs/`, never here. Write the rule as it stands NOW — no history ("was X until …"), no owner quotes (those belong in the spec), and no tuning numbers that live in a CSV (name the key instead). `tests/engine/test_claude_md_size.gd` caps this file and each nested one.

## Key documents

- `docs/design/PRD.md` — scope of the first playable build; the build order lives here (§6) — follow it.
- `docs/design/COUNCIL_SYSTEM.md` — the council design; source of truth for mechanics and formulas.
- `docs/design/MANOR_SYSTEM.md` — the manor system (manors, houses, purses, focus, buildings).
- `docs/design/DATA_ARCHITECTURE.md` — the data as a whole: the layers (raw → Defs → State → derived → output), the schema of `data/` and `GameState`, the lineage, and what to re-run after each kind of change.
- `docs/design/CHAPTER_0.md` + `game_story/chapter_0/chapter_0_events.md` — the prologue, which is the tutorial.
- `RANDOM_EVENTS.md` (repo root) — the random-events system. **Loaded at runtime**: `StorySource` parses each `### EV-NN` entry's `**Scene:**` prose and the game shows it verbatim, so keep the heading and `**Scene:**` labels intact (a test asserts all ids resolve). The "Your event seeds" section at the top is the owner's inbox: expand each new seed into a fully spec'd event (trigger, weight, choices with signatures, chain) in the pool below. **No event is ever model-written** — `Voicer.voice_event` has no path to the API; if an event needs different words, write them there.
- `.claude/skills/visual-review/` — the loop for EVERY visual change (shoot, compare variants, crop, independent critic) and `taste.md`, the owner's art rulings as principles; add each new ruling there.
- `tools/NEW_MAP.md` (bringing in a new map pack), `tools/map3d/README.md` (the Terrain3D pipeline), `assets/flux/README.md` (the 2D art pipeline: Z-Image and Qwen-Image-2512 only, no Flux model — the folder keeps its old name).
- `docs/art_team/README.md` — the art collaboration: the artist's locked ComfyUI workflows (a Comfy Cloud copy beside them) and the `cc_art_check` Blender add-on (`docs/art_team/kit/`), rebuilt by `tools/art_kit/build_kit.py`; the artist's handbook is the owner's Confluence page.
- `docs/superpowers/specs/` and `plans/` — one spec and plan per feature; the history and the owner's words behind every rule.

## Stack

- **Godot 4.7 + GDScript**, typed everywhere (type hints on vars, params, returns). **Forward+** renderer: `source_color` uniforms are converted to linear and blending is linear, so a colour passed per VERTEX must be turned linear in the shader.
- **A tick is a MONTH of 30 days** (`Calendar.DAYS_PER_TICK`, 12 ticks a year); `GameState.day` runs 1..30 under it and the month's end is the settlement.
- **GUT** for tests. The simulation engine must be unit-testable headless.
- **OpenAI API via raw HTTP** (`HTTPRequest`). Model IDs and prices live in one config table (PRD §8).
- **Run:** `/Applications/Godot.app/Contents/MacOS/Godot --path .`
- **A fresh clone runs as it is**: every asset the game draws is committed (the Terrain3D build and its textures included). Steps: Godot 4.7, `git clone`, ONE import pass (`Godot --headless --path . --import`, or open the editor; `.godot/` is never committed) — the first pass prints font/theme load errors that are gone on the next run. No Blender, ComfyUI, Python or `build_pack.sh` is needed to play; those only REBUILD art. `.env` / `user://config.json` are optional (absent, the game runs offline).
- **Test:** `./run_tests.sh` runs the full GUT suite headless and must report the **expected error count**: "Errors 2" while the `gdai-mcp-plugin-godot` GDExtension binaries are installed (GUT cannot resolve its class-database probing headless), 0 without them — the script keys off `gdai_mcp_plugin.gdextension`, which git ignores, so a fresh clone expects 0. It exports `CC_FORCE_OFFLINE=1` so no live API call is possible. `./run_tests.sh --fast` runs only `tests/engine`, `tests/ledger3d`, `tests/llm` for the edit-run loop; run the whole suite before a merge.
- **A test takes its data from `tests/suite_data.gd`, never `DataRepository.load_all`**: `SuiteData.repo()` is a deep copy of data parsed once per run (change any table freely), `SuiteData.campaign(repo, seed)` a cached campaign copied through the save format; `tests/pre_run.gd` hands the same copier to `Game.campaign_maker`. Wait with `wait_process_frames` or `wait_until`, never `wait_frames` (a 60 Hz physics frame of real time in this GUT).
- **`.env`** (git-ignored, read by `OpenAIClient.load_config()`; `.env.example` lists `OPENAI_API_KEY`, `LLM_MODEL`/per-tier overrides, `LLM_MAX_OUTPUT_TOKENS`) overlays defaults and is overlaid by **`user://config.json`** (`api_key`, `model_parse`, `model_voice`, `model_order`, `model_flagship`, `offline_mode`). A missing/malformed file, an empty key or `CC_FORCE_OFFLINE=1` fails closed to `offline_mode: true`.

## Architecture invariants (do not violate)

1. **The engine decides; the LLM only writes dialogue.** Concern scans, advisor suggestions, opinion drift, faction power and escalation are deterministic engine code. A minister's suggestion is a real `action_code` with real params — always legal, always affordable; the model never invents actions. The model may propose **world deltas** only on paths listed in `data/world_schema.csv`, each clamped to its `llm_cap`, each with a reason, only on the player's own realm; the engine picks the speaker and applies everything through `WorldLedger`.
2. **Determinism.** One seeded RNG stream owned by the engine. No `Time.get_*`, no wall-clock, no unseeded `randi()` in simulation code (no wall-clock below `Game`). Identical save + identical inputs ⇒ identical state. LLM output enters the engine only as validated action codes, clamped enums (`tone` deltas ±3) and schema-listed world deltas clamped to their caps. Engine state holds no floats that must survive the JSON save (positions are whole metres).
3. **Simulation core is engine-pure.** Sim classes are `RefCounted` (no Node/scene dependencies) so GUT runs them headless; nothing under `scripts/engine/` names a `scripts/ui/` or `scripts/llm/` class or touches `Game` (`test_engine_isolation.gd`). UI observes state via signals and never mutates it directly; state changes go through `Game`.
4. **Readable causality.** Every opinion change carries a reason string at creation (`−8: revoked noble tax exemption (opposes, centralism)`). Never write an opinion delta without one. The same holds for every state move that takes a reason (`MapOwnership.set_owner`, `MapManors.set_owner`).
5. **Authored prose never names a kingdom.** Story text, facts, role names and templates say `{player_realm}` / `{raider_realm}` / `{neighbor_realm}` / `{empire_realm}`; `DataRepository.fill_realms()` substitutes the bound kingdom at load, structural columns use the slot (`resolve_realm`). A re-export that renames the world touches `data/maps/<id>/realm_bindings.csv` and nothing else — tests included: fixtures derive kingdom, capital and roads from the pack. No code, tool or test names a map pack either (`DataRepository.default_pack_id()`).
6. **Territory is state, not pack data.** The pack ships the starting border; who holds a province now is `GameState.province_owner` (only what moved), moved through `MapOwnership.set_owner` with a reason. A kingdom's live outline is the merge of its provinces' loops, so conquest redraws border, label and land with no new art. Hit-testing reads the province index bitmap (geometry) and looks the owner up; never trust `world_state_index.png` for ownership. Likewise a manor's holder and province are state (`GameState.manor_owner`, `manor_province`).
7. **Save = one JSON file.** All state in memory, serialized whole. No database, no partial saves.
8. **Every order carries a cost.** `OrderCosts` guarantees an explicit (gold, grain, population) or hidden (opinion, relationship, attribute) cost per executed order from `data/order_costs.csv` (polarity in `data/metric_polarity.csv`); `COUNCIL_CONSULT` and `EVENT_CHOICE` are the exemptions. A typed order is ONE model call returning `{narrative, impacts}`; the screens print the narrative and then the ledger lines that actually applied, so an overreaching narrative is visible as such.
9. **Cost discipline.** Clicked suggestions bypass the LLM. Low-stakes minister lines use trait-tinted templates with no API call. The flagship model is only for rare confrontation/betrayal scenes.
10. **The columns divide by kind.** The LEFT column is FACTS (the realm card, the hovered country, the host, the card of whatever is clicked on the map — a click replaces the left column, never the right); the RIGHT slot is PEOPLE (the council column and the record of what was said). The talk itself is the **audience window** centred over the map; events and the opening narration stand in the same window. A map click never displaces the talk. The left column's width is fixed (`ScreenLayout.LEFT_WIDTH`): anything in it must wrap and scroll, never widen it. Each screen owns one `_refresh_left()` applying the precedence (card > hovered country > host > the column's own content); no panel hides its siblings. Details: `scripts/ui/CLAUDE.md`.
11. **The economy is whole gold, rounded once, at the manor** (`ManorEconomy.line_of`). Provinces and the realm are sums; growth is an integer per-mille table; iteration order is fixed.

## Rules that cut across every module

- **Design values live in `data/*.csv`, never hardcoded in scripts.** Add columns/rows rather than embedding constants (`data/CLAUDE.md`).
- **The LOOK lives in the editor, not in code or CSV** (binding): a screen's static look is authored in its `.tscn` and `.tres` resources so the editor shows what the game draws — never built in `_ready()`, never a `res://` path column in a CSV, never a style assembled in code. A key → art table is an `ArtTable` / typed Resource `.tres` (`GameArt`), the game's Theme is `assets/2D/ui/theme/game_theme.tres` with label kinds (`theme_type_variation`) instead of code colours, custom styles and drawn pieces are `@tool` with `@export`ed fields. Look changes are made THROUGH THE EDITOR (gdai MCP), never by text-editing a `.tscn`, checking every open script buffer against disk before an editor save (a stale buffer clobbers the file). In a `@tool` path read tables through `UiPalette.data()`, never `Game.data`. Guards: `tests/ui/test_editor_owned_look.gd`, `tests/map3d/test_map3d_editor_owned_look.gd`. Details: `scripts/ui/CLAUDE.md`.
- **Asset layout**: every 3D asset the game uses is in `assets/3D/{category}/{object}/`, whatever produced it in that object's `model_wip/` (git-ignored but its `.gdignore`; a category-wide source in `assets/3D/{category}/model_wip/`). A Tripo export waiting to be processed sits in the staging folder `assets/3D/model_wip/tripo_inbox/<category>/<object>/` beside its picked reference, and moves to its object's `model_wip/tripo/` once processed (README there). Every 2D asset is in `assets/2D/{category}/{set}/`, a set being what one installer fills. Fonts, audio, `assets/maps/` (data bitmaps) and `assets/flux/` stay outside. Every installer and exporter already writes there. **`assets/` holds art, never a scene** (owner 2026-10-04): a model's `.glb` (the art Godot imports; it stays, since the import is made from it and the scenes instance it) is in `assets/`, its scene in `scenes/models/`; the Terrain3D build writes its world scene to `scenes/map3d/worlds/<map>.tscn` and keeps its data in `assets/3D/terrain/<map>/`; `test_scene_layout.gd` holds it.
- **Every `world_*.png` is DATA**: imported lossless, never VRAM compressed (it scrambles manor ids and bands the sea); `project.godot`'s `[importer_defaults] texture` carries `detect_3d/compress_to: 0` for that reason. They are generated (`tools/import_azgaar.gd` and the bakes) — lasting changes belong in Azgaar, not hand edits.
- **Art sourcing**: ComfyUI's work ends at the IMAGE. **No Hunyuan3D** anywhere (its licence). Tripo 3D is allowed for 3D sources on the owner's PAID plan only.
- **Every visual change** goes through the `visual-review` skill; real-window shots with `tools/snapshot_screen.gd --resolution WxH` are the only faithful check. Headless Godot cannot render 3D (a 3D snapshot hangs) — never run one with `--headless`.
- **`scripts/map3d/` and `scripts/war_room/` never read the `Game` autoload** (`map3d_view.gd` and `WarRoomScreen` in `scripts/ui/` are the bridges; a test scans for `Game.`), so their layers draw in the editor from a pack alone.
- **Time**: the clock is driven only by `GameRoot._process` through `Game.advance_day`; there is no End Turn. An order never starts the clock. Space pauses/resumes on every play screen (never from a text box or under the pause menu).
- **Build order** is PRD §6, strictly (briefings/suggestions → opinion drift → debates → recruitment → factions to stage 3 → chapter framework → faction stages 4–6 for Tomas's faction only → raid defense → chapter-1 event chains → art integration), except that the 3D map look route (`docs/superpowers/specs/2026-09-24-map3d-humankind-look-gap.md`) runs first. The MVP is ONE complete chapter, the prologue (`docs/design/CHAPTER_0.md`), expanded so PRD §7's three arcs play inside it (owner 2026-10-04): every feature, its art and its gameplay, nothing placeholder. Succession, assassination, aging and stages 4–6 for other factions are post-MVP.

## Layout

```
project.godot
icon.png          # the application icon
RANDOM_EVENTS.md  # event pool — loaded at runtime (StorySource), stays at the root
game_story/       # opening narration and the chapter documents — loaded at runtime (.gdignore)
data/             # CSVs, the design source of truth (.gdignore; read by FileAccess); data/maps/<id>/ = pack tables
scripts/engine/   # deterministic sim: tick, actions, characters, opinion, factions, economy, armies, couriers, intel, ledger model, save
scripts/llm/      # OpenAI client, prompt builders, response validation
scripts/ui/       # screens, panels, and the HUD pieces the 3D map shares; scripts/ui/war_table/ the oak-table pieces
scripts/map3d/    # the 3D map: Map3DView the coordinator, Map3DContext, one script per layer / HUD job, pure maths, .gdshader files
scripts/war_room/ # the WAR ROOM's 3D plotting room (WarRoomScreen itself is in scripts/ui/)
scripts/ledger3d/ # the LEDGER galaxy view
scenes/           # EVERY scene, by kind (owner 2026-10-04): game_root.tscn (MENU → CONVERSATION → COURT); screens/ (court, conversation, main_menu, ledger, missive, war room, info, pause); hud/ (top and bottom bars, news slip, fps); panels/ (the cards and popups); models/buildings/ and models/units/ (each model a scene inheriting its .glb in assets/); map3d/worlds/ (each pack's built Terrain3D world, written by build_pack.sh); tools/ (the snapshot and bench tools' scenes); characters/, locations/, map3d/, war_room/, ledger/, war_table/
tests/            # GUT: engine/, llm/, ui/, map3d/, ledger3d/, war_room/, fixtures/
tools/            # headless bakes, importers, snapshots, benches (Godot -s); every tool takes --map, none names a pack
tools/map3d/      # the Terrain3D pipeline: build_pack.sh, bench.gd, README.md
assets/3D/ assets/2D/   # every asset the game uses (see Asset layout)
assets/fonts/ assets/audio/ assets/maps/ assets/flux/
addons/           # gut, terrain_3d (committed); gdai-mcp-plugin-godot (binaries git-ignored)
docs/design/      # PRD, council / manor systems, chapter 0, data architecture
docs/references/  # owner reference images; the art prompt library (art_prompt_library.md)
docs/superpowers/ # specs/ and plans/ per feature
```

## Conventions

- GDScript style: `snake_case` files/functions/vars, `PascalCase` classes, signals in past tense (`opinion_changed`).
- UI screens are self-contained scenes signalling up to GameRoot; state mutations only via `Game`.
- The API key comes from a local git-ignored config file — never committed, never shipped.
- Every engine formula (opinion drift, faction power, cohesion) gets a GUT test with hand-computed expected values before UI work uses it.
