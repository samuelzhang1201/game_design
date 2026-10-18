# Beyond the King's Words

Before editing or delivering work, read `.codex/harness.md` for Codex scope, branch/PR, CI and handover rules. Read subsystem guides below only as needed.

Text-first, LLM-narrated grand strategy game: rule a kingdom for ~60 years through a council of ministers with real personalities, ideologies, and grudges. Godot 4 project. The campaign map is the **3D map** (Terrain3D, `scripts/map3d/`, built by `tools/map3d/`) — the ONLY map; there is no 2D map and none is ever added. A checkout with no built world shows the 3D view's notice naming `build_pack.sh`.

## How the guidance is split (read this first)

This file holds only what holds EVERYWHERE. Subsystem rules live in the indexed `CLAUDE.md` guides below; read each relevant guide before editing that subsystem:

| File | Covers |
|---|---|
| `scripts/engine/CLAUDE.md` | the simulation: manors and the economy, time, events and the prologue, regiments, couriers, weather, intel / missives / spies, governors, supply, industry and trade, the LEDGER's data model |
| `scripts/map3d/CLAUDE.md` | the 3D map: build and loading, camera, picking, borders, roads, water, sky, weather visuals, woods, fields, houses, the regiment pieces, HUD, performance gates |
| `scripts/ui/CLAUDE.md` | screens and HUD: the look-in-editor conversion, theme kinds, fonts, the war table, the council row, cards, bars, title and landing, menus, window-size rules |
| `scripts/war_room/CLAUDE.md` | the WAR ROOM plotting-room screen |
| `scripts/ledger3d/CLAUDE.md` | the LEDGER galaxy view |
| `tools/CLAUDE.md` | art and build pipelines: ComfyUI image generation (`assets/imagegen/`), installers, arms, portraits, house and unit models, bakes, `snapshot_screen`, benches |
| `data/CLAUDE.md` | the CSV tables and the map pack tables |
| `scripts/llm/CLAUDE.md` | the OpenAI client, `.env` / `user://config.json`, prompts, validation, the voicers |

**Writing guidance:** a feature's detail goes into its subsystem's `CLAUDE.md` or its spec under `docs/superpowers/specs/`, never here. Write the rule as it stands NOW — no history ("was X until …"), no owner quotes (those belong in the spec), and no tuning numbers that live in a CSV (name the key instead). `tests/engine/test_claude_md_size.gd` caps this file and each nested one. A nested guide near its cap moves whole topics into `guide/<topic>.md` beside it and lists them in a **Topic guides** index (Codex does not load those on its own, so the index names the classes each covers).

## Key documents

- `docs/design/PRD.md` — scope of the first playable build; the build order lives here (§6) — follow it.
- `docs/design/COUNCIL_SYSTEM.md` — the council design; source of truth for mechanics and formulas.
- `docs/design/MANOR_SYSTEM.md` — the manor system (manors, houses, purses, focus, buildings).
- `docs/design/DATA_ARCHITECTURE.md` — the data as a whole: the layers (raw → Defs → State → derived → output), the schema of `data/` and `GameState`, the lineage, and what to re-run after each kind of change.
- `docs/design/CHAPTER_0.md` + `game_story/chapter_0/chapter_0_events.md` — the prologue, which is the tutorial.
- `RANDOM_EVENTS.md` (repo root) — the random-events system. **Loaded at runtime**: `StorySource` parses each `### EV-NN` entry's `**Scene:**` prose and the game shows it verbatim, so keep the heading and `**Scene:**` labels intact (a test asserts all ids resolve). The "Your event seeds" section at the top is the owner's inbox: expand each new seed into a fully spec'd event (trigger, weight, choices with signatures, chain) in the pool below. **No event is ever model-written** — `Voicer.voice_event` has no path to the API; if an event needs different words, write them there.
- `.claude/skills/visual-review/` — the loop for EVERY visual change (shoot, compare variants, crop, independent critic) and `taste.md`, the owner's art rulings as principles; add each new ruling there.
- Art and build pipelines (new map packs, Terrain3D, 2D art, the art team's kit): the guides listed at the top of `tools/CLAUDE.md`.
- `docs/superpowers/specs/` and `plans/` — one spec and plan per feature; the history and the owner's words behind every rule.

## Stack

- **Godot 4.7 + GDScript**, typed everywhere (type hints on vars, params, returns). **Forward+** renderer: `source_color` uniforms are converted to linear and blending is linear, so a colour passed per VERTEX must be turned linear in the shader.
- **A tick is a MONTH of 30 days** (`Calendar.DAYS_PER_TICK`, 12 ticks a year); `GameState.day` runs 1..30 under it and the month's end is the settlement.
- **GUT** for tests. The simulation engine must be unit-testable headless.
- **OpenAI API via raw HTTP** (`HTTPRequest`). Model IDs and prices live in one config table (PRD §8).
- **Run:** `/Applications/Godot.app/Contents/MacOS/Godot --path .` (macOS). `$GODOT`, when set, names the binary for `run_tests.sh` (the cloud SessionStart hook sets it).
- **A fresh clone runs as it is**: every asset the game draws is committed (the Terrain3D build and its textures included). Steps: Godot 4.7, `git clone`, ONE import pass (`Godot --headless --path . --import`, or open the editor; `.godot/` is never committed) — the first pass prints font/theme load errors that are gone on the next run. No Blender, ComfyUI, Python or `build_pack.sh` is needed to play; those only REBUILD art. `.env` / `user://config.json` are optional (absent, the game runs offline).
- **Test:** `./run_tests.sh` runs the full GUT suite headless (`CC_FORCE_OFFLINE=1`, so no live API call) and fails on any error count but the expected one: 2 while the git-ignored `gdai-mcp-plugin-godot` binaries are installed, 0 without them (a fresh clone, the cloud). `./run_tests.sh --fast` runs only `tests/engine`, `tests/ledger3d`, `tests/llm` for the edit-run loop — this is the regression check to run while developing and before every commit. **GitHub Actions (`.github/workflows/tests.yml`) runs the whole suite on every PR against `main` before merge**, so don't run the full `./run_tests.sh` yourself on each commit — let CI do it; only run it locally when you need to debug a CI-reported failure; for a change under `tests/ui`, `tests/map3d` or `tests/war_room` run just those directories with GUT.
- **A test takes its data from `tests/suite_data.gd`, never `DataRepository.load_all`**: `SuiteData.repo()` is a deep copy of data parsed once per run (change any table freely), `SuiteData.campaign(repo, seed)` a cached campaign copied through the save format; `tests/pre_run.gd` hands the same copier to `Game.campaign_maker`. Wait with `wait_process_frames` or `wait_until`, never `wait_frames` (a 60 Hz physics frame of real time in this GUT).
- **Config** (`.env`, `user://config.json`) is optional and fails closed to offline: `scripts/llm/CLAUDE.md`.

## Architecture invariants (do not violate)

1. **The engine decides; the LLM only writes dialogue.** Concern scans, advisor suggestions, opinion drift, faction power and escalation are deterministic engine code. A minister's suggestion is a real `action_code` with real params — always legal, always affordable; the model never invents actions. The model may propose **world deltas** only on paths listed in `data/realm/world_schema.csv`, each clamped to its `llm_cap`, each with a reason, only on the player's own realm; the engine picks the speaker and applies everything through `WorldLedger`.
2. **Determinism.** One seeded RNG stream owned by the engine. No `Time.get_*`, no wall-clock, no unseeded `randi()` in simulation code (no wall-clock below `Game`). Identical save + identical inputs ⇒ identical state. LLM output enters the engine only as validated action codes, clamped enums (`tone` deltas ±3) and schema-listed world deltas clamped to their caps. Engine state holds no floats that must survive the JSON save (positions are whole metres).
3. **Simulation core is engine-pure.** Sim classes are `RefCounted` (no Node/scene dependencies) so GUT runs them headless; nothing under `scripts/engine/` names a `scripts/ui/` or `scripts/llm/` class or touches `Game` (`test_engine_isolation.gd`). UI observes state via signals and never mutates it directly; state changes go through `Game`.
4. **Readable causality.** Every opinion change carries a reason string at creation (`−8: revoked noble tax exemption (opposes, centralism)`). Never write an opinion delta without one. The same holds for every state move that takes a reason (`MapOwnership.set_owner`, `MapManors.set_owner`).
5. **Authored prose never names a kingdom.** Story text, facts, role names and templates say `{player_realm}` / `{raider_realm}` / `{neighbor_realm}` / `{empire_realm}`; `DataRepository.fill_realms()` substitutes the bound kingdom at load, structural columns use the slot (`resolve_realm`). A re-export that renames the world touches `data/maps/<id>/realm_bindings.csv` and nothing else — tests included: fixtures derive kingdom, capital and roads from the pack. No code, tool or test names a map pack either (`DataRepository.default_pack_id()`).
6. **Territory is state, not pack data.** The pack ships the starting border; who holds a province now is `GameState.province_owner` (only what moved), moved through `MapOwnership.set_owner` with a reason. A kingdom's live outline is the merge of its provinces' loops, so conquest redraws border, label and land with no new art. Hit-testing reads the province index bitmap (geometry) and looks the owner up; never trust `world_state_index.png` for ownership. Likewise a manor's holder and province are state (`GameState.manor_owner`, `manor_province`).
7. **Save = one JSON file.** All state in memory, serialized whole. No database, no partial saves.
8. **Every order carries a cost.** `OrderCosts` guarantees an explicit (gold, grain, population) or hidden (opinion, relationship, attribute) cost per executed order from `data/realm/order_costs.csv` (polarity in `data/realm/metric_polarity.csv`); `COUNCIL_CONSULT` and `EVENT_CHOICE` are the exemptions. A typed order is ONE model call returning `{narrative, impacts}`; the screens print the narrative and then the ledger lines that actually applied, so an overreaching narrative is visible as such.
9. **Cost discipline.** Clicked suggestions bypass the LLM. Low-stakes minister lines use trait-tinted templates with no API call. The flagship model is only for rare confrontation/betrayal scenes.
10. **The columns divide by kind.** The LEFT column is FACTS (the realm card, the hovered country, the host, the card of whatever is clicked on the map — a click replaces the left column, never the right); the RIGHT slot is PEOPLE (the council column and the record of what was said). The talk itself is the **audience window** centred over the map; events and the opening narration stand in the same window. A map click never displaces the talk. The left column's width is fixed (`ScreenLayout.LEFT_WIDTH`): anything in it must wrap and scroll, never widen it. Precedence and `_refresh_left()`: `scripts/ui/CLAUDE.md`.
11. **The economy is whole gold, rounded once, at the manor** (`ManorEconomy.line_of`). Provinces and the realm are sums; growth is an integer per-mille table; iteration order is fixed.

## Rules that cut across every module

- **Design values live in `data/`, never hardcoded in scripts**: CSVs in scene folders (`realm/`, `army/`, `economy/` …, the look under `screens/`), each with its own `balance.csv`, indexed by `data/tables.csv`. Add columns/rows rather than embedding constants (`data/CLAUDE.md`).
- **The LOOK lives in the editor, not in code or CSV** (binding): a screen's static look is authored in its `.tscn` and `.tres` resources so the editor shows what the game draws — never built in `_ready()`, never a `res://` path column in a CSV, never a style assembled in code. A key → art table is an `ArtTable` / typed Resource `.tres` (`GameArt`), the game's Theme is `assets/2D/ui/theme/game_theme.tres` with label kinds (`theme_type_variation`) instead of code colours, custom styles and drawn pieces are `@tool` with `@export`ed fields. Look changes are made THROUGH THE EDITOR (gdai MCP), never by text-editing a `.tscn`, checking every open script buffer against disk before an editor save (a stale buffer clobbers the file). In a `@tool` path read tables through `UiPalette.data()`, never `Game.data`. Guards: `tests/ui/test_editor_owned_look.gd`, `tests/map3d/test_map3d_editor_owned_look.gd`. Details: `scripts/ui/CLAUDE.md`.
- **Asset layout**: every 3D asset the game uses is in `assets/3D/{category}/{object}/` (its sources in that object's git-ignored `model_wip/`), every 2D asset in `assets/2D/{category}/{set}/`. **`assets/` holds art, never a scene**: a model's `.glb` is in `assets/`, its scene in `scenes/models/` (`test_scene_layout.gd`). Staging folders and the Terrain3D build's layout: `tools/CLAUDE.md`.
- **Every `world_*.png` is DATA**: imported lossless, never VRAM compressed, generated by the tools, never hand-edited (`data/CLAUDE.md`).
- **Art sourcing**: ComfyUI's work ends at the IMAGE. **No Hunyuan3D** anywhere (its licence). Tripo 3D is allowed for 3D sources on the owner's PAID plan only.
- **Every visual change** goes through the `visual-review` skill; real-window shots with `tools/snapshot_screen.gd --resolution WxH` are the only faithful check. Headless Godot cannot render 3D (a 3D snapshot hangs) — never run one with `--headless`.
- **In a cloud session** (Codex.ai/code: Linux, headless Godot at `$GODOT`, no editor, no gdai MCP, no window) the tests run but nothing can be looked at. Do the code, data and test part; never text-edit a `.tscn`/`.tres` look or claim a visual change reviewed — end with the editor steps and the `visual-review` pass left for a local session.
- **`scripts/map3d/` and `scripts/war_room/` never read the `Game` autoload** (`map3d_view.gd` and `WarRoomScreen` in `scripts/ui/` are the bridges; a test scans for `Game.`), so their layers draw in the editor from a pack alone.
- **Time**: the clock is driven only by `GameRoot._process` through `Game.advance_day`; there is no End Turn. An order never starts the clock. Space pauses/resumes on every play screen (never from a text box or under the pause menu).
- **Build order** is PRD §6, strictly, except that the 3D map look route (`docs/superpowers/specs/2026-09-24-map3d-humankind-look-gap.md`) runs first. The MVP is ONE complete chapter, the prologue (`docs/design/CHAPTER_0.md`), expanded so PRD §7's three arcs play inside it: every feature, its art and its gameplay, nothing placeholder. Succession, assassination, aging and stages 4–6 for other factions are post-MVP.

## Layout

```
RANDOM_EVENTS.md  # event pool, loaded at runtime — stays at the root
game_story/       # opening narration and chapter documents, loaded at runtime (.gdignore)
data/             # CSVs by scene folder + tables.csv index, the design source of truth (.gdignore); data/maps/<id>/ = pack tables
scripts/          # engine/ llm/ ui/ map3d/ war_room/ ledger3d/ — one nested CLAUDE.md each (table above)
scenes/           # EVERY scene, by kind (screens/, hud/, panels/, models/, map3d/worlds/, tools/, …)
tests/            # GUT, one folder per scripts/ folder, plus fixtures/
tools/            # bakes, importers, snapshots, benches (Godot -s); every tool takes --map
assets/           # art only: 3D/ 2D/ fonts/ audio/ maps/ imagegen/ (the image-generation pipeline)
addons/           # gut, terrain_3d (committed); gdai-mcp-plugin-godot (binaries git-ignored)
docs/             # design/ (PRD, systems, chapter 0), references/, superpowers/specs|plans/, art_team/
```

## Done means

1. Run checks relevant to the owned change on its final code state; pure harness/config/guidance changes run Python/shell/config/guide checks without Godot. Game changes retain targeted GUT, hand-computed formula and relevant save/determinism checks. Follow the actual runner/workflow and `.codex/harness.md`; do not run a full local suite routinely or reuse results after relevant code/data changes.
2. One small step lands through its own PR against `main`, owned only by implementation and its unique Review session. Review merges directly after all required current-HEAD CI and review checks pass; no direct main push, timeout exception or next feature in the same PR. `cicd_procedure.md` describes the checks; skipped/absent required checks are not success.
3. A new engine formula has its hand-computed GUT test; a new rule is written into the right nested `CLAUDE.md` (or its `guide/`), not here.
4. A visual change has been through `visual-review` — or, in a cloud session, the final message says it still needs it.

## Execution discipline and model routing

- **One small problem, one step, one PR.** A session discusses and implements only one bounded, independently testable change. Split an oversized plan step before coding; leave follow-on features and unrelated cleanup for later PRs. Never accumulate several steps in an existing PR.
- **Exactly two responsible sessions per PR:** the implementation session and its unique `<step>-Review` session. No third session, subagent, parallel worker, coordinator or nested reviewer participates in that feature/plan. Review owns in-scope fixes and merges directly to `main` after all current-HEAD required CI and review checks pass; no extra confirmation or timeout exception. Only then may the next independent step begin.
- **One-to-one handoff only.** Implementation → its Review → next authorized step's implementation. At most one predecessor and one fresh successor per session; no broadcasts, fan-in/fan-out, forks, resumes or return loops. Save a short worktree-local checkpoint; create the single successor once and end the source session. Do not reread full history or relaunch approved planning.
- **Use the existing session pair.** Routine implementation/review uses Sol; complex architecture may use Astra within the pair. Role profiles and skill suggestions never authorize an extra architect/reviewer/worker. Do not change permissions, trust, MCP or the selected main model.
- Authoritative delivery, checks, scope and marker rules: `.codex/harness.md` and `.codex/hooks/task-handover.md`. Read only relevant subsystem guidance. Pure harness/config work runs its own syntax and behavioral checks, not game-wide GUT; retain meaningful formula, save/determinism and visual checks for changes that need them.

## Conventions

- GDScript style: `snake_case` files/functions/vars, `PascalCase` classes, signals in past tense (`opinion_changed`).
- UI screens are self-contained scenes signalling up to GameRoot; state mutations only via `Game`.
- The API key comes from a local git-ignored config file — never committed, never shipped.
- Every engine formula (opinion drift, faction power, cohesion) gets a GUT test with hand-computed expected values before UI work uses it.
