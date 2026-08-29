# GDScript for Godot 4

## Contents
1. Script skeleton & annotations
2. Type system
3. Signals & Callables
4. await / coroutines
5. Core global APIs you use constantly
6. Math/geometry toolbox
7. Performance notes
8. Looking up exact signatures ("all functions")
9. Godot 3 → 4 trap list

## 1. Script skeleton & annotations

Conventional member order:

```gdscript
class_name Player                    # registers global type (usable in code + Inspector)
extends CharacterBody2D
## Doc comment for the class (## = docstring, shows in editor help).

signal died
signal health_changed(new_health: int)

enum State { IDLE, RUN, JUMP }

const MAX_LIVES: int = 3
const DashEffect := preload("res://fx/dash.tscn")

@export var move_speed: float = 300.0
@export var stats: PlayerStats
@export_range(0.0, 1.0) var friction: float = 0.2

var health: int = 10:
    set(value):                       # property setter — runs on every assignment
        health = clampi(value, 0, stats.max_health)
        health_changed.emit(health)
var _state: State = State.IDLE        # _prefix = private by convention

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _muzzle: Marker2D = %Muzzle    # % = scene-unique name

func _ready() -> void: ...
func _physics_process(delta: float) -> void: ...
# public methods, then private (_helper) methods, then signal handlers (_on_*)
```

Annotations to know: `@export` (+`_group`, `_subgroup`, `_category`, `_range`, `_enum`, `_flags`, `_file`, `_dir`, `_multiline`, `_color_no_alpha`, `_node_path`, `_custom`), `@onready`, `@tool` (script runs in editor), `@icon("res://...")`, `@warning_ignore(...)`, `@rpc` (multiplayer), `@abstract` (4.5+), `@export_tool_button` (4.4+).

`static func` and `static var` exist; a `class_name`-only script of statics = namespaced utility module. Inner `class Foo:` blocks define nested helper classes.

## 2. Type system

- Always annotate: `var x: int`, `func f(a: float) -> void`. `:=` infers from the right side (`var dir := Vector2.RIGHT`).
- Typed collections: `Array[int]`, `Array[EnemyStats]`; typed dictionaries `Dictionary[String, int]` require **4.4+**.
- Variant is the untyped fallback; `as Type` casts (returns null on failure for objects), `is Type` tests, `is_instance_of()` for dynamic checks.
- Value types (copied on assignment): all math types, packed arrays... but `Array`/`Dictionary` are **passed by reference** — `.duplicate(true)` to copy.
- `StringName` (`&"jump"`) for identifier-like strings (signal/action/anim names) — faster comparison; API accepts plain String too, auto-converted.
- Null safety: only object types can be null; `if node:` truthiness works, but prefer explicit `!= null` / `is_instance_valid()` (a freed node is non-null garbage — `is_instance_valid` is the real check).

## 3. Signals & Callables

Signals are first-class objects; so are function references (Callable).

```gdscript
signal damaged(amount: int, source: Node)

# emit
damaged.emit(5, self)

# connect (idiomatic 4.x — no strings)
enemy.damaged.connect(_on_enemy_damaged)
enemy.damaged.connect(_on_enemy_damaged.bind(extra_arg))       # append args
button.pressed.connect(func() -> void: start_game())            # lambda
timer.timeout.connect(_respawn, CONNECT_ONE_SHOT)               # flags: ONE_SHOT, DEFERRED
if enemy.damaged.is_connected(_on_enemy_damaged): enemy.damaged.disconnect(_on_enemy_damaged)
```

- Connections auto-disconnect when either endpoint is freed — usually no manual cleanup needed.
- `CONNECT_DEFERRED` delays the callback to idle time — the fix when a signal handler mutates physics/tree state.
- Callable tricks: `my_func.call(args)`, `call_deferred()`, `node.call_deferred("method", arg)`, `Callable(obj, "method")`, `array.map(func(x): return x * 2)`, `array.filter(...)`, `array.reduce(...)`, `array.any(...)`/`all(...)`.
- Every Object supports dynamic access: `has_method()`, `get()/set()`, `get_property_list()`, and the universal `property_list_changed`/`script_changed` signals. Duck-type across scenes: `if body.has_method("take_damage"): body.take_damage(1)` — though a shared `class_name` or component child is cleaner.

## 4. await / coroutines

`await` suspends the current function until a signal fires or an awaited coroutine returns.

```gdscript
await get_tree().create_timer(0.5).timeout        # delay (respects pause by default)
await get_tree().process_frame                    # next frame
await animation_player.animation_finished
var result: int = await fetch_score()             # awaiting a coroutine

func flash() -> void:
    for i in 3:
        _sprite.modulate = Color.RED
        await get_tree().create_timer(0.1).timeout
        _sprite.modulate = Color.WHITE
        await get_tree().create_timer(0.1).timeout
```

Danger: after an `await`, `self` may have been freed (scene changed). Guard long waits: `if not is_inside_tree(): return`. Functions containing `await` return a coroutine — callers that ignore it continue immediately (fire-and-forget is fine and common).

Tweens (procedural animation, replaces most await-loops):

```gdscript
var tw := create_tween()
tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
tw.tween_property(self, "position", target, 0.3)
tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)   # runs alongside previous
tw.tween_callback(queue_free)                                 # then this
```
`tween_interval()`, `tween_method()` (animate any function), `set_loops()`, `chain()`, `kill()`. Store the tween and `kill()` before starting a replacement to avoid stacking.

## 5. Core global APIs you use constantly

- **Input**: `Input.is_action_pressed/just_pressed/just_released("jump")`, `Input.get_axis("left","right")`, `Input.get_vector("left","right","up","down")` (normalized), `Input.mouse_mode = Input.MOUSE_MODE_CAPTURED`, event objects in `_unhandled_input`: `event.is_action_pressed("jump")`, `event is InputEventMouseMotion` → `event.relative`.
- **Node**: `add_child`, `remove_child`, `queue_free`, `reparent(new_parent)`, `get_node`/`$`/`%`, `get_node_or_null`, `find_child(pattern)`, `get_parent`, `get_children`, `get_tree`, `is_inside_tree`, `add_to_group`, `move_child`, `duplicate()`, `set_process(bool)`, `owner`, `name`, `process_mode`, `scene_file_path`.
- **Node2D/3D transforms**: `position` vs `global_position`, `rotation` (radians), `scale`, `look_at(point)`, `to_local()`/`to_global()`, `Node3D.basis`, `transform`, `global_transform`.
- **OS/Engine/Time**: `OS.get_name()`, `OS.has_feature("mobile")`, `Time.get_ticks_msec()`, `Time.get_unix_time_from_system()`, `Engine.is_editor_hint()` (inside @tool), `Engine.get_frames_per_second()`.
- **Random**: `randf()`, `randi_range(a,b)`, `randf_range`, `randfn` (gaussian), `array.pick_random()`, `array.shuffle()`; seedable via `RandomNumberGenerator` instance.
- **FileAccess/DirAccess**: `FileAccess.open("user://f.json", FileAccess.WRITE)`, `.store_string()`, `.get_as_text()`, `FileAccess.file_exists()`, `DirAccess.make_dir_recursive_absolute()`.
- **Debug**: `print`, `print_rich("[color=red]hi[/color]")`, `push_warning`, `push_error`, `assert(cond, "msg")` (debug builds only), `print_debug`, `get_stack()`, `print_tree_pretty()`; breakpoints via `breakpoint` keyword.
- **Physics queries (no nodes needed)**:
```gdscript
var space := get_world_2d().direct_space_state
var q := PhysicsRayQueryParameters2D.create(from, to, collision_mask)
var hit: Dictionary = space.intersect_ray(q)     # {} if none; keys: position, normal, collider...
```
Only valid inside `_physics_process`. Also `intersect_shape`, `intersect_point`.

## 6. Math/geometry toolbox

Types: `Vector2/2i/3/3i/4/4i`, `Rect2/2i`, `AABB`, `Transform2D`, `Transform3D`, `Basis`, `Quaternion`, `Plane`, `Color`, `PackedFloat32Array` etc.

Functions that solve 90% of gameplay math:
- `lerp(a, b, t)`, `lerpf`, `Vector2.lerp`, `lerp_angle`, `inverse_lerp`, `remap(v, imin, imax, omin, omax)`
- Framerate-independent smoothing: `pos = pos.lerp(target, 1.0 - exp(-decay * delta))` or `move_toward(current, target, max_delta)`
- `clamp/clampi/clampf`, `wrapf/wrapi`, `sign`, `absf`, `snappedf` (grid snap), `pingpong`
- Vectors: `.normalized()`, `.length()`/`.length_squared()` (compare squared!), `.distance_to()`, `.direction_to()`, `.dot()` (facing checks), `.cross()`, `.angle()`, `.angle_to()`, `.rotated(rad)`, `.bounce(normal)`, `.slide(normal)`, `.limit_length(max)`
- Angles: `deg_to_rad`/`rad_to_deg`, `atan2(y, x)` → `Vector2.angle()`
- `Color.from_hsv()`, `color.lerp()`, `Color(1,1,1,0.5)`; constants like `Color.RED`

## 7. Performance notes

- Godot philosophy: nodes are cheap-ish but not free. Thousands of moving things → `MultiMeshInstance`, particles, or servers (`RenderingServer`/`PhysicsServer2D` directly — the "server pattern" skips nodes entirely).
- Cache node lookups in `@onready`; never `get_node()` in `_process`.
- `length_squared()` over `length()` in comparisons; avoid per-frame allocations (reuse arrays, avoid string building).
- Profiler lives in the Debugger panel; `--debug` + Monitors tab for draw calls, physics time.
- Static typing measurably speeds up GDScript. For hot inner loops beyond that: C# or GDExtension.
- Object pooling is usually unnecessary in Godot unless spawning hundreds/sec — measure first (pattern in systems-cookbook.md).

## 8. Looking up exact signatures ("all functions")

The full class reference is enormous and version-specific; verify rather than recall:

1. Online: `https://docs.godotengine.org/en/stable/classes/class_<classname_lowercase>.html` (swap `stable` for `4.6`, `4.7` etc. to pin a version). Fetch this when unsure about a signature, enum name, or property.
2. Installed truth: `godot --headless --doctool /tmp/godot_docs` dumps XML for the exact binary version; `grep -rl "method name=\"move_and_slide\"" /tmp/godot_docs`.
3. `godot --headless --check-only --script res://path.gd` validates a script compiles (catches typos in API names) without running the game. Note: scripts referencing autoloads/class_names need to be checked from the project directory.
4. In-repo: grep the project and installed addons for prior usage.

## 9. Godot 3 → 4 trap list

Never emit these Godot-3-isms (auto-red-flag your own output for them):

| Godot 3 (wrong) | Godot 4 (right) |
|---|---|
| `onready var x = $X` | `@onready var x: T = $X` |
| `export(int) var hp` | `@export var hp: int` |
| `yield(obj, "sig")` | `await obj.sig` |
| `connect("pressed", self, "_on")` | `pressed.connect(_on)` |
| `emit_signal("died")` | `died.emit()` |
| `instance()` | `instantiate()` |
| `KinematicBody2D` + `move_and_slide(velocity, UP)` | `CharacterBody2D`, set `velocity`, call `move_and_slide()` |
| `Spatial`, `Sprite`, `Area` (3D) | `Node3D`, `Sprite2D`/`Sprite3D`, `Area3D` |
| `rand_range()` | `randf_range()` / `randi_range()` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `deg2rad` / `linear2db` | `deg_to_rad` / `linear_to_db` |
| `File`/`Directory` classes | `FileAccess`/`DirAccess` statics |
| `PoolStringArray` etc. | `PackedStringArray` etc. |
| `tool` keyword | `@tool` |
| `setget get_x, set_x` | property `set(value):` / `get:` blocks |
| `change_scene(path)` | `change_scene_to_file(path)` |
| `Tween` node | `create_tween()` |
| `TileMap` (in 4.3+ projects) | `TileMapLayer` per layer |
