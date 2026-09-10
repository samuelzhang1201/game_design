# Crown and Council

Text-first, LLM-narrated grand strategy game: rule a kingdom for ~60 years through a council of ministers with real personalities, ideologies, and grudges. **Greenfield** — no code exists yet; this directory currently holds design docs and data.

## Key documents

- `PRD.md` — scope of the first playable build. Build order lives here; follow it.
- `COUNCIL_SYSTEM.md` — the council design doc; source of truth for mechanics and formulas.
- `RANDOM_EVENTS.md` — random-events system: triggering rules + the event pool. The "Your event seeds" section at the top is the owner's inbox for raw ideas — when new seeds appear there, expand each into a fully spec'd event (trigger, weight, choices with signatures, chain) in the pool below it. **This file is loaded at runtime**, not just design reference: `StorySource` parses each `### EV-NN` entry's `**Scene:**` field and the game displays that prose verbatim. Its formatting is therefore a contract — keep the heading and `**Scene:**` labels intact, and a test asserts all 20 ids still resolve. **No event is ever model-written:** event stories are fixed authored prose, `Voicer.voice_event` has no path to the API, and no event prompt exists. If an event needs different words, write them here.
- `council_seats.csv`, `character_traits.csv`, `faction_escalation.csv`, `policy_actions_court_additions.csv`, `action_signatures.csv`, `events.csv`, `event_choices.csv`, `world_rules.csv`, `claim_types.csv`, `facts.csv`, `world_schema.csv`, `metric_polarity.csv`, `order_costs.csv`, `political_palette.csv`, `kingdoms.csv`, `provinces.csv`, `burgs.csv` — game data, loaded at runtime. **Design values live in these CSVs, never hardcoded in scripts.** Add columns/rows rather than embedding constants. Exception: the map pack tables under `data/maps/<id>/` — `map_info.csv`, `realm_bindings.csv`, and `house_bindings.csv` (both bindings hand-maintained, never written by the importer: realms bind authored slots to kingdoms, houses bind the court's families to provinces of the player's realm; unbound provinces are held by a house named after their seat) at the root and, by domain, `geography/` (`biomes`, `rivers`, `markers`, `routes`), `political/` (`kingdoms`, `provinces`, `burgs`, `borders`, `province_borders`, `diplomacy`, `campaigns`), `economy/` (`kingdoms`, `provinces`, `burgs`, `goods`, `markets`, `market_goods`, `production`), `military/` (`kingdoms`, `regiments`, `unit_types`), `society/` (`cultures`, `religions`, `zones`); `data/` carries a `.gdignore` at its root (the per-domain ones are now redundant but harmless) so Godot does not import game tables as translations — it was generating ~120 `.translation`/`.csv.import` sidecars nothing loads; `FileAccess` reads the CSVs regardless, and a future export preset must include `data/**` explicitly — plus `assets/maps/<id>/world_map.png` and the `world_state_index.png` / `world_province_index.png` / `world_biome_index.png` hit-test bitmaps are **generated** by `tools/import_azgaar.gd` from the Azgaar exports in `assets/maps/` — hand-edits are overwritten on re-import; lasting changes belong in Azgaar. **The render is terrain only** (owner ruling 2026-09-09: export with the political layer, borders, and labels off): the game paints every province in its live owner's colour from `data/political_palette.csv` (realm slots, `other_N` for unbound kingdoms, and the named line colours) via `MapPalette`, and `WorldMapView` draws every kingdom's border, the province seams, and the labels itself, so conquest repaints and redraws with no new art. **Reset the zoom in Azgaar before exporting the PNG** — the PNG export captures the current view, so a render taken while zoomed is a scaled, shifted picture of the same world; it still has the right dimensions, so it imports cleanly and then draws borders that miss the coastline by tens of pixels. `data/maps.csv` carries `render_scale` / `render_offset_x` / `render_offset_y` to correct such a render (1 / 0 / 0 = a clean export); `WorldMapView.map_to_screen` applies it and `screen_to_map` undoes it, so all pack coordinates and the hit-test bitmaps stay in the JSON's own space. **Measure it, never eyeball it:** `python3 tools/calibrate_render.py --pack <id> --write` (needs numpy, pillow, scipy) registers the pack's coastline against the render and writes the three numbers; `test_map_data` fails when a calibration leaves the coast off the render's coastline (2026-09-09: an eyeballed calibration was off by 8 native px and every drawn border sat beside the printed one).

## Stack

- **Godot 4.x + GDScript** (typed GDScript everywhere: type hints on vars, params, returns).
- **GUT** (Godot Unit Test) for tests. The simulation engine must be unit-testable headless.
- **OpenAI API via raw HTTP** (`HTTPRequest` node) — there is no GDScript SDK. Model IDs and prices live in one config table (see PRD §8), not scattered through code.
- **Run:** `/Applications/Godot.app/Contents/MacOS/Godot --path .`
- **Test:** `./run_tests.sh` (runs the full GUT suite headless; "Errors 2" in the summary is a documented, expected condition from a vendored GExtension's class-database probing, not a real failure — any other error count is treated as fatal). `run_tests.sh` exports `CC_FORCE_OFFLINE=1` so the suite can never make a live API call even with a real `.env` present.
- **`.env`** (git-ignored, dev-convenience source for `OpenAIClient.load_config()`; `.env.example` documents the keys — `OPENAI_API_KEY`, `LLM_MODEL`/per-tier overrides, `LLM_MAX_OUTPUT_TOKENS`) overlays defaults and is itself overlaid by `user://config.json` (player override); a missing key or `CC_FORCE_OFFLINE=1` fails closed to `offline_mode: true`.
- **`user://config.json`** (git-ignored, read by `OpenAIClient.load_config()`; missing/unreadable/malformed file, or an empty `api_key`, all fail closed to `offline_mode: true`):
  ```json
  {
    "api_key": "",
    "model_parse": "gpt-5.6-luna",
    "model_voice": "gpt-5.6-terra",
    "offline_mode": true
  }
  ```

## Architecture invariants (do not violate)

1. **The engine decides; the LLM only writes dialogue.** Concern scans, advisor suggestions, opinion drift, faction power, and escalation are all deterministic engine code. A minister's suggestion is a real `action_code` with real params — always legal, always affordable. Never let the model invent actions. The model may also propose **world deltas** (owner ruling 2026-09-09), but only on paths listed in `data/world_schema.csv`, each clamped to that path's `llm_cap`, each carrying a reason, and only on the player's own realm; the engine still picks the speaker and applies everything through `WorldLedger`.
2. **Determinism.** One seeded RNG stream owned by the engine. No `Time.get_*`, no wall-clock, no unseeded `randi()` inside simulation code. Identical save + identical inputs ⇒ identical state. LLM output enters the engine only as validated action codes, clamped enums (e.g. `tone` deltas capped at ±3), and schema-listed world deltas clamped to their caps.
3. **Simulation core is engine-pure.** Keep sim classes as `RefCounted` (no Node/scene dependencies) so GUT can run them headless. UI observes state via signals; it never mutates it directly.
4. **Readable causality.** Every opinion change carries a reason string at creation time (`−8: revoked noble tax exemption (opposes, centralism)`). Never write an opinion delta without one.
5. **Authored prose never names a kingdom.** The map is a generated Azgaar
   export, so story text, fact text, role names and templates say
   `{player_realm}` / `{raider_realm}` / `{neighbor_realm}` / `{empire_realm}`;
   `DataRepository.fill_realms()` substitutes the bound kingdom's label at
   load. Structural columns keep using the slot itself (`resolve_realm`).
   A re-export that renames the world should touch
   `data/maps/<id>/realm_bindings.csv` and nothing else — tests included:
   fixtures derive their kingdom, capital and roads from the pack, never
   from a literal name.
6. **Territory is state, not pack data.** The map pack ships the *starting*
   border; who holds a province now lives in `GameState.province_owner`
   (only what has moved) and moves through `MapOwnership.set_owner`, which
   requires a reason like every other state change. A kingdom's live outline
   is the merge of the loops of the provinces it holds
   (`province_borders.csv`), so conquest redraws the border, recentres the
   label and repaints the land with no new art. Hit-testing reads the
   province index bitmap — geometry, which never goes stale — and looks the
   owner up; never trust `world_state_index.png` for ownership.
7. **Save = one JSON file.** All state in memory, serialized whole. No database, no partial saves.
8. **Every order carries a cost.** `OrderCosts` guarantees an explicit (gold, grain, population) or hidden (opinion, relationship, attribute) cost per executed order from `data/order_costs.csv` (polarity per metric in `data/metric_polarity.csv`); `COUNCIL_CONSULT` and `EVENT_CHOICE` are the listed exemptions. A typed order is ONE model call returning `{narrative, impacts}`; the screens print the narrative and then the ledger lines that actually applied, so a narrative that overreaches is visible as such.
9. **Cost discipline.** Clicked suggestions bypass the LLM entirely. Low-stakes minister lines use trait-tinted templates with no API call. Reserve the flagship model for rare confrontation/betrayal scenes only.
10. **The columns divide by kind** (owner ruling 2026-09-10). The LEFT
    column is FACTS: the realm dashboard, the country under the cursor, the
    host while the military layer is on, and the fact card of whatever the
    player clicks on the map — clicking an object replaces the left column,
    never the right. The RIGHT slot is PEOPLE AND TALK: the council column,
    the dialogue panel, and the speaker's dossier, which stands at the top
    of it over their words — a thumbnail, name, seat and standing, with
    BIO / SKILLS / TIES pages that open in the talk's space and hand it
    straight back, because the column cannot hold both. So a map click
    never displaces the council, and the map only narrows for the council.
    The left column's width is fixed
    (`ScreenLayout.LEFT_WIDTH`, 120 design px): anything put in it must wrap
    — a label that cannot wrap sets a minimum width and pushes the column
    over the map — and scroll rather than grow. Each screen owns one
    `_refresh_left()` that applies the precedence (card > hovered country >
    military > the column's own content); no panel hides its own siblings.

## Planned layout (create as needed)

```
project.godot
data/            # CSVs — design source of truth
scripts/engine/  # deterministic sim: tick, actions, characters, opinion, factions, save
scripts/llm/     # OpenAI client, prompt builders, response schema validation
scripts/ui/      # scenes and view scripts
tests/           # GUT tests, mirror engine structure
scenes/game_root.tscn (state machine: MENU→CONVERSATION→COURT→DAY_RUN), main_menu,
  conversation, court, day_run, kingdom_card, characters/*
```

UI screens are self-contained scenes signaling up to GameRoot; state mutations only via Game.

## Conventions

- GDScript style: `snake_case` files/functions/vars, `PascalCase` classes, signals named in past tense (`opinion_changed`).
- The API key is read from a local git-ignored config file — never committed, never shipped in a build.
- Every engine formula (opinion drift, faction power, cohesion) gets a GUT test with hand-computed expected values before UI work uses it.
- Build order is PRD §6, strictly: briefings/suggestions → opinion drift → debates → recruitment → factions to stage 3 → chapter framework → faction stages 4–6 (Tomas's faction only, data-capped) → raid defense → chapter-1 event chains → art integration. The MVP is a complete Chapter 1 (PRD v2.0, §7); succession/assassination/aging and stages 4–6 for other factions remain post-MVP.
