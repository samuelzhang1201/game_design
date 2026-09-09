# Crown and Council

Text-first, LLM-narrated grand strategy game: rule a kingdom for ~60 years through a council of ministers with real personalities, ideologies, and grudges. **Greenfield** — no code exists yet; this directory currently holds design docs and data.

## Key documents

- `PRD.md` — scope of the first playable build. Build order lives here; follow it.
- `COUNCIL_SYSTEM.md` — the council design doc; source of truth for mechanics and formulas.
- `RANDOM_EVENTS.md` — random-events system: triggering rules + the event pool. The "Your event seeds" section at the top is the owner's inbox for raw ideas — when new seeds appear there, expand each into a fully spec'd event (trigger, weight, choices with signatures, chain) in the pool below it. **This file is loaded at runtime**, not just design reference: `StorySource` parses each `### EV-NN` entry's `**Scene:**` field and the game displays that prose verbatim. Its formatting is therefore a contract — keep the heading and `**Scene:**` labels intact, and a test asserts all 20 ids still resolve. **No event is ever model-written:** event stories are fixed authored prose, `Voicer.voice_event` has no path to the API, and no event prompt exists. If an event needs different words, write them here.
- `council_seats.csv`, `character_traits.csv`, `faction_escalation.csv`, `policy_actions_court_additions.csv`, `action_signatures.csv`, `events.csv`, `event_choices.csv`, `world_rules.csv`, `claim_types.csv`, `facts.csv`, `kingdoms.csv`, `provinces.csv`, `burgs.csv` — game data, loaded at runtime. **Design values live in these CSVs, never hardcoded in scripts.** Add columns/rows rather than embedding constants. Exception: the map pack tables under `data/maps/<id>/` (`kingdoms.csv`, `provinces.csv`, `burgs.csv`, `borders.csv`, `routes.csv`, `rivers.csv`, `markers.csv`, `biomes.csv`, `map_info.csv`) plus `assets/maps/<id>/world_map.png` and the `world_state_index.png` / `world_province_index.png` / `world_biome_index.png` hit-test bitmaps are **generated** by `tools/import_azgaar.gd` from the Azgaar exports in `assets/maps/` — hand-edits are overwritten on re-import; lasting changes belong in Azgaar. **Reset the zoom in Azgaar before exporting the PNG** — the PNG export captures the current view, so a render taken while zoomed is a scaled, shifted picture of the same world; it still has the right dimensions, so it imports cleanly and then draws borders that miss the coastline by tens of pixels. `data/maps.csv` carries `render_scale` / `render_offset_x` / `render_offset_y` to correct such a render (1 / 0 / 0 = a clean export); `WorldMapView.map_to_screen` applies it and `screen_to_map` undoes it, so all pack coordinates and the hit-test bitmaps stay in the JSON's own space.

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

1. **The engine decides; the LLM only writes dialogue.** Concern scans, advisor suggestions, opinion drift, faction power, and escalation are all deterministic engine code. A minister's suggestion is a real `action_code` with real params — always legal, always affordable. Never let the model invent actions.
2. **Determinism.** One seeded RNG stream owned by the engine. No `Time.get_*`, no wall-clock, no unseeded `randi()` inside simulation code. Identical save + identical inputs ⇒ identical state. LLM output enters the engine only as validated action codes and clamped enums (e.g. `tone` deltas capped at ±3).
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
8. **Cost discipline.** Clicked suggestions bypass the LLM entirely. Low-stakes minister lines use trait-tinted templates with no API call. Reserve the flagship model for rare confrontation/betrayal scenes only.

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
