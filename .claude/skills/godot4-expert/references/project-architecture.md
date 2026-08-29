# Godot 4 Project Architecture

## Folder structure: organize by feature, not by file type

Type-based layouts (`scripts/`, `scenes/`, `sprites/`) scatter one feature across five folders and rot fast. Organize by **feature/domain**: everything the Player needs lives together, so a scene, its script, and its art move, rename, and delete as one unit.

```
res://
├── project.godot
├── main.tscn                    # entry scene: boots managers, loads first level/menu
├── addons/                      # editor plugins (managed by the editor)
├── autoload/                    # singletons — keep these few and boring
│   ├── events.gd                #   global signal bus
│   ├── game_state.gd            #   run-wide state (score, current level)
│   └── audio_manager.tscn       #   autoloads can be scenes (pooled AudioStreamPlayers)
├── entities/                    # things that exist in the world
│   ├── player/
│   │   ├── player.tscn
│   │   ├── player.gd
│   │   ├── player_sprite.png
│   │   └── states/              # player state machine states
│   ├── enemies/
│   │   ├── enemy_base.gd        # shared base (shallow!)
│   │   ├── slime/
│   │   │   ├── slime.tscn
│   │   │   ├── slime.gd
│   │   │   └── slime_stats.tres # instance of EnemyStats resource
│   │   └── bat/ ...
│   └── projectiles/
├── components/                  # reusable capability scenes attached as children
│   ├── health_component.tscn/gd
│   ├── hitbox.tscn/gd
│   ├── hurtbox.tscn/gd
│   └── state_machine/
├── levels/
│   ├── level_01/level_01.tscn
│   └── shared/                  # tilesets, level props
├── ui/
│   ├── hud/hud.tscn
│   ├── main_menu/
│   ├── pause_menu/
│   └── theme/game_theme.tres    # one Theme resource for the whole game
├── resources/                   # custom Resource *scripts* + shared .tres data
│   ├── enemy_stats.gd           #   class_name EnemyStats extends Resource
│   ├── item_definition.gd
│   └── items/sword.tres, potion.tres, ...
├── assets/                      # ONLY truly shared, feature-less art/audio/fonts
│   ├── audio/music/, audio/sfx/
│   └── fonts/
└── shaders/
```

Rules of thumb:
- Asset used by exactly one feature → lives in that feature's folder. Shared by many → `assets/`.
- `snake_case` for files/folders, `PascalCase` for node names and `class_name`s. Scene file name matches its root script (`player.tscn` + `player.gd`).
- Never reorganize files outside the editor context lightly — `.tscn`/`.tres` store `res://` paths. If refactoring outside the editor, grep-and-update every path reference (`grep -rn "old/path" --include="*.tscn" --include="*.tres" --include="*.gd"`), including `.godot/` caches being stale (safe to delete `.godot/`, it regenerates).
- `.godot/` is generated — always gitignore it. Also gitignore `export_presets.cfg` if it contains keystore credentials.

## project.godot: what to configure deliberately

- **Main scene**: `run/main_scene`. Keep `main.tscn` thin — it wires managers and hands off.
- **Autoloads** in `[autoload]` — load order = declaration order; later autoloads can reference earlier ones in `_ready`.
- **Input map** in `[input]`: define semantic actions (`"jump"`, `"interact"`) — never check raw keys in gameplay code. `Input.is_action_just_pressed("jump")`.
- **Physics layers**: name every 2D/3D physics layer under Layer Names (`world`, `player`, `enemy`, `player_hurtbox`, `enemy_hitbox`, `pickups`...). Named layers make collision matrices reviewable.
- **Display**: window size, stretch mode (`canvas_items` + aspect `keep` for pixel-perfect 2D; `viewport` for integer-scaled pixel art), and `textures/canvas_textures/default_texture_filter = "Nearest"` for pixel art.
- **Rendering method**: `forward_plus` (desktop 3D), `mobile`, or `gl_compatibility` (web/low-end, 2D games). Affects available graphics features — check before writing shaders.

## Autoload (singleton) discipline

Autoloads are `Node`s added above the current scene in the tree root, alive for the whole run. They are the right tool for a small set of jobs and the classic way to ruin a codebase when overused.

Good autoloads:
- **Events** — a global signal bus: just signal declarations (`signal coin_collected(value: int)`), no logic. Emitter: `Events.coin_collected.emit(5)`. Listener: `Events.coin_collected.connect(_on_coin)`. Use for cross-scene, cross-cutting notifications only — not as a replacement for direct parent-child wiring.
- **GameState / SaveManager** — run-wide data + persistence.
- **AudioManager** — a scene autoload holding a pool of `AudioStreamPlayer`s so SFX survive scene changes.
- **SceneManager** — handles transitions (fade, load, change) so gameplay code just calls `SceneManager.goto("res://levels/level_02.tscn")`.

Anti-patterns: gameplay logic in autoloads, autoloads referencing nodes inside the current scene (invert it — the scene registers itself), more than ~5 autoloads, using an autoload where a `class_name` with static functions would do (stateless helpers don't need to be in the tree).

A non-tree alternative for pure data/constants: a script with `class_name Config` and constants/static funcs — accessible everywhere with zero tree presence.

## Scene composition model of a game

Think of the running game as a tree of scene instances:

```
root (Window)
├── Events, GameState, AudioManager, SceneManager   (autoloads)
└── Main
    ├── CurrentLevel (swapped by SceneManager)
    │   ├── TileMapLayer(s)
    │   ├── Player (instance of player.tscn)
    │   ├── Enemies/ (Node2D folder-node holding instances)
    │   └── Pickups/
    └── UI (CanvasLayer)
        └── HUD (instance of hud.tscn)
```

- Levels contain *instances* of entity scenes, positioned in the editor. Levels don't script entity behavior; they wire signals and spawn things.
- UI lives on a `CanvasLayer` so camera movement never affects it.
- Use plain `Node`/`Node2D` "folder nodes" (`Enemies`, `Pickups`) to group spawned children — makes `get_children()` iteration and cleanup trivial.

## Scaling up

- **Component scenes** (`components/`): a `HealthComponent` with `@export var max_health: int`, `signal died`, added as a child to any entity — this is Godot's idiomatic ECS-lite. Entities become thin coordinators of their components.
- **Data-driven content**: entity scenes take an `@export var stats: EnemyStats` resource; designers create new enemy variants as `.tres` files without touching code. See `resources.md`.
- **Inherited scenes** (Scene > New Inherited Scene) share structure edits from a base scene; use sparingly — resource-driven variation is usually more flexible than scene inheritance.
- **Addons**: reusable tooling goes in `addons/<name>/` with a `plugin.cfg`; project-specific code never does.
