---
name: godot4-expert
description: Expert Godot 4 game development — GDScript, scene/node architecture, resources, project folder structure, physics, UI, and common game systems. Use this skill whenever the user mentions Godot, GDScript, .tscn/.tres files, a project.godot file, or asks to build, debug, refactor, or architect any 2D/3D game, game mechanic, or game system that runs in Godot — even if they don't say "Godot" but the repo contains Godot project files. Also use when reviewing Godot code, designing a game's folder structure, deciding between scenes vs resources, or writing custom nodes, autoloads, shaders, or editor tools.
---

# Godot 4 Expert

Build games the way an experienced Godot developer does: composition-first scene design, typed GDScript, resources for data, signals for decoupling, and a folder structure organized by feature.

**Version assumption:** Godot 4.x (current stable is the 4.6/4.7 line — Jolt is the default 3D physics engine since 4.6). Never use Godot 3 idioms (`onready var`, `export(int)`, `yield()`, `connect("sig", self, "_fn")`, KinematicBody). If the project's `project.godot` declares `config/features=PackedStringArray("4.3")` etc., match that minor version's API.

## Reference files — read before working

Load the reference that matches the task. For any non-trivial task, read `nodes-and-scenes.md` and `project-architecture.md` first — they encode the core design decisions everything else depends on.

| File | Read when |
|---|---|
| `references/project-architecture.md` | Starting/restructuring a project, adding features, autoloads, folder layout |
| `references/nodes-and-scenes.md` | Choosing node types, scene composition, instancing, lifecycle, SceneTree |
| `references/resources.md` | Data modeling, custom resources, save/load, .tres files, when resource-vs-node |
| `references/gdscript.md` | Writing any GDScript — language features, signals, key APIs, doc lookup |
| `references/systems-cookbook.md` | State machines, input, save systems, object pooling, scene transitions, UI patterns |

## Core decision frameworks

### Node vs Resource vs plain Object (the most important call you'll make)

- **Node** — it exists in the world, ticks every frame, or needs the tree (position, rendering, physics, input, timers, lifetime tied to a scene). Nodes are *behavior + presence*.
- **Resource** — it is *data*: stats, configs, item definitions, dialogue, curves, anything you'd want to edit in the Inspector, save to disk as `.tres`, and share between many nodes. Resources are reference-counted, serializable, and load once/shared by default.
- **RefCounted** — pure runtime logic/state with no serialization or tree needs (a pathfinding result, a request object).
- If you're making a Node that never enters the tree, or a Resource with `_process`-like behavior, you've picked wrong.

### When to break something into its own scene

Make it a `.tscn` when it is **reused**, **instanced at runtime**, **owned by a different team member/concern**, or **independently testable** (you can hit F6 and run just it). A Player, Enemy, Bullet, Pickup, HUD, Menu, Level — each its own scene. A node that only ever exists as a child of one parent and has no independent meaning stays inline.

### Communication rule: "call down, signal up"

Parents may call methods on children they own. Children/siblings never reach up or across with `get_parent()` or `get_node("../..")` — they emit signals, and the owning scene wires them. Cross-cutting concerns (score changed, game paused) go through an autoload event bus. This single rule prevents most Godot spaghetti.

### Composition over inheritance

Deep `class_name` inheritance chains are a smell. Prefer attaching capability as child nodes/scenes (a `Hitbox`, a `HealthComponent`, a `StateMachine` node) or as exported Resources (a `MovementStats` resource). Inherit only for true is-a relationships one level deep (e.g., `Enemy extends CharacterBody2D`).

## Non-negotiable code standards

1. **Static typing everywhere**: `var speed: float = 300.0`, `func take_damage(amount: int) -> void:`. It catches bugs at parse time and runs faster.
2. **`@onready var` + `%UniqueName` or `$Path`** for node refs; export NodePaths or, better, `@export var target: Node2D` for cross-scene wiring.
3. **Signals connected in code** for logic (`health_changed.connect(_on_health_changed)`), editor connections only for UI-to-script in the same scene.
4. **`preload()` for scenes/resources known at parse time**; `load()` only for dynamic paths. Instantiate with `.instantiate()`.
5. **Physics in `_physics_process`, visuals/input polling in `_process`.** `CharacterBody2D/3D` uses the `velocity` property + `move_and_slide()` (no arguments in Godot 4).
6. **Never hardcode `res://` paths in many places** — preload at the top of the file or route through a resource/autoload registry.
7. **Errors**: check `is_instance_valid()` before touching freed nodes; use `queue_free()` not `free()` for tree nodes; `call_deferred()`/`set_deferred()` when mutating physics state or the tree during signal callbacks or physics callbacks.

## API accuracy discipline

You cannot hold "all functions" in your head reliably across Godot minor versions — but the project can. When unsure about an exact method/property/constant:

1. **Check the installed docs**: the class reference ships in the editor, and online at `https://docs.godotengine.org/en/stable/classes/class_<lowercase_name>.html` (e.g. `class_charactebody2d` → `class_characterbody2d`). Fetch it rather than guessing.
2. **Grep the project**: existing code in the repo shows which API surface/version is actually in use.
3. **Headless verification**: if the Godot binary is available, `godot --headless --check-only --script file.gd` parses a script without running the game; `godot --headless --doctool <dir>` dumps the full XML class reference for the exact installed version — grep it for signatures.
4. Prefer APIs stable since 4.0–4.2 unless the project targets newer; call out when you use a 4.3+/4.6+ API (e.g., typed dictionaries `Dictionary[String, int]` are 4.4+).

## Workflow for game tasks

1. **Orient**: read `project.godot` (main scene, autoloads, features, input map), skim the folder tree, and open the main scene's `.tscn` to learn conventions already in place. Match them.
2. **Design before writing**: for a new feature, decide scene boundaries, node types, resource types, and signal flow first — state it in one short paragraph or a small tree diagram.
3. **Implement** scene-by-scene: `.tscn` structure (you can author `.tscn` text directly — format is documented in `nodes-and-scenes.md`), then the script, then wiring.
4. **Verify**: run `godot --headless --check-only --script` on new scripts if the binary exists; otherwise re-read for Godot-3-isms and type errors. Confirm every `$Path`/`%Name` reference matches the scene tree you authored.
5. **Explain the architecture** briefly to the user: what's a scene, what's a resource, how signals flow — so they can extend it.
