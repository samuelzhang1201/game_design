# Systems Cookbook — Idiomatic Implementations

Battle-tested patterns for the systems every game needs. Adapt names/details to the project's conventions.

## Contents
1. Node-based state machine
2. Health/Hitbox/Hurtbox components
3. SceneManager with fade transitions
4. Save/load system (JSON)
5. Character controllers (2D platformer, 3D first-person)
6. Spawning & object pooling
7. UI patterns (menus, HUD binding, settings)
8. Audio manager
9. Shaders quick reference

## 1. Node-based state machine

States as child nodes: visible in the editor, per-state scripts, trivially debuggable.

```gdscript
# components/state_machine/state_machine.gd
class_name StateMachine
extends Node
## Children must extend State. First child is the initial state.

@export var actor: Node               # who the states control
var current: State

func _ready() -> void:
    for child in get_children():
        var state := child as State
        state.actor = actor
        state.finished.connect(_transition)
    current = get_child(0)
    current.enter("")

func _physics_process(delta: float) -> void: current.physics_update(delta)
func _process(delta: float) -> void: current.update(delta)
func _unhandled_input(event: InputEvent) -> void: current.handle_input(event)

func _transition(target: String) -> void:
    var next := get_node_or_null(target) as State
    if next == null:
        push_error("Unknown state: " + target); return
    var prev := current.name
    current.exit()
    current = next
    current.enter(prev)
```

```gdscript
# components/state_machine/state.gd
class_name State
extends Node

signal finished(next_state: String)

var actor: Node

func enter(_prev: String) -> void: pass
func exit() -> void: pass
func update(_delta: float) -> void: pass
func physics_update(_delta: float) -> void: pass
func handle_input(_event: InputEvent) -> void: pass
```

A state transitions with `finished.emit("Jump")`. For 2–3 trivial states, a plain `enum + match` in one script is fine — don't over-engineer.

## 2. Health/Hitbox/Hurtbox components

```gdscript
# components/health_component.gd
class_name HealthComponent
extends Node

signal health_changed(current: int, max: int)
signal died

@export var max_health: int = 10
var health: int:
    set(v):
        var prev := health
        health = clampi(v, 0, max_health)
        if health != prev: health_changed.emit(health, max_health)
        if health == 0 and prev > 0: died.emit()

func _ready() -> void: health = max_health
func damage(amount: int) -> void: health -= amount
func heal(amount: int) -> void: health += amount
```

Hitbox (deals damage) = `Area2D` with `@export var damage: int`; Hurtbox (receives) = `Area2D` that on `area_entered` reads `area.damage` and forwards to its owner's HealthComponent. Put hitboxes and hurtboxes on **separate collision layers** (e.g., `player_hurtbox` masks `enemy_hitbox` only) — this makes friendly fire, i-frames (`set_deferred("monitoring", false)`), and team logic pure layer configuration. Owner wires it: `hurtbox.hurt.connect(health_component.damage)`, `health_component.died.connect(_on_died)`.

## 3. SceneManager with fade transitions

```gdscript
# autoload/scene_manager.gd  (autoload as a SCENE: root Node + CanvasLayer(layer=100) + ColorRect)
extends Node

@onready var _fade: ColorRect = $CanvasLayer/ColorRect   # black, full-rect, mouse_filter=IGNORE
var _busy := false

func goto(scene_path: String) -> void:
    if _busy: return
    _busy = true
    var tw := create_tween()
    tw.tween_property(_fade, "modulate:a", 1.0, 0.25)
    await tw.finished
    get_tree().change_scene_to_file(scene_path)
    await get_tree().process_frame            # let new scene enter
    tw = create_tween()
    tw.tween_property(_fade, "modulate:a", 0.0, 0.25)
    await tw.finished
    _busy = false
```

For large levels, swap `change_scene_to_file` for `ResourceLoader.load_threaded_request()` + a polling loop updating a ProgressBar, then `change_scene_to_packed(ResourceLoader.load_threaded_get(path))`.

## 4. Save/load system (JSON)

```gdscript
# autoload/save_manager.gd
extends Node

const SAVE_PATH := "user://save_%d.json"
const VERSION := 1

func save_game(slot: int) -> void:
    var data := {
        "version": VERSION,
        "timestamp": Time.get_unix_time_from_system(),
        "player": {"health": GameState.player_health, "position": _v2(GameState.player_pos)},
        "level": GameState.current_level,
        "flags": GameState.flags,          # Dictionary of story/progress flags
    }
    var f := FileAccess.open(SAVE_PATH % slot, FileAccess.WRITE)
    if f == null:
        push_error("Save failed: %s" % FileAccess.get_open_error()); return
    f.store_string(JSON.stringify(data, "\t"))

func load_game(slot: int) -> bool:
    var path := SAVE_PATH % slot
    if not FileAccess.file_exists(path): return false
    var parsed = JSON.parse_string(FileAccess.get_as_text(FileAccess.open(path, FileAccess.READ)))
    if parsed == null or typeof(parsed) != TYPE_DICTIONARY: return false
    var data: Dictionary = _migrate(parsed)
    GameState.apply(data)
    return true

func _migrate(d: Dictionary) -> Dictionary:
    match int(d.get("version", 0)):
        0: d["flags"] = {}; d["version"] = 1
    return d

func _v2(v: Vector2) -> Array: return [v.x, v.y]   # JSON has no Vector2
```

JSON caveats: no Vector2/Color (encode as arrays/hex), all numbers come back as float (cast with `int()`), keys are Strings. For settings (volume, keybinds) prefer `ConfigFile` (`set_value("audio","master",0.8)`, `save("user://settings.cfg")`). What to save for world state: iterate a `"persist"` group and ask each node for `get_save_data() -> Dictionary`.

## 5. Character controllers

**2D platformer** (the canonical shape):
```gdscript
extends CharacterBody2D

@export var speed := 300.0
@export var jump_velocity := -420.0
@export var coyote_time := 0.1
@export var jump_buffer := 0.1

var _coyote := 0.0
var _buffer := 0.0

func _physics_process(delta: float) -> void:
    velocity += get_gravity() * delta
    _coyote = coyote_time if is_on_floor() else _coyote - delta
    _buffer = jump_buffer if Input.is_action_just_pressed("jump") else _buffer - delta

    if _buffer > 0.0 and _coyote > 0.0:
        velocity.y = jump_velocity
        _buffer = 0.0; _coyote = 0.0
    if Input.is_action_just_released("jump") and velocity.y < 0.0:
        velocity.y *= 0.5                        # variable jump height

    var dir := Input.get_axis("move_left", "move_right")
    velocity.x = move_toward(velocity.x, dir * speed, speed * 10.0 * delta)
    move_and_slide()
```
`get_gravity()` (4.x) reads project/area gravity. Coyote time + jump buffering are the difference between "floaty" and "tight" — include them by default.

**3D first-person**: `CharacterBody3D` → `CollisionShape3D` (capsule) + `Node3D "Head"` → `Camera3D`. Mouse look in `_unhandled_input` on `InputEventMouseMotion`: yaw rotates body (`rotate_y(-event.relative.x * sens)`), pitch rotates head, `head.rotation.x = clampf(head.rotation.x, -PI/2, PI/2)`. Movement: `var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()` then set `velocity.x/z`, gravity on `y`, `move_and_slide()`. Capture mouse: `Input.mouse_mode = Input.MOUSE_MODE_CAPTURED`.

## 6. Spawning & object pooling

Plain spawning (default — fine for most games): see nodes-and-scenes.md §3. Wire the spawn point with `Marker2D`s and a `Timer`.

Pooling (only for very high churn — bullet-hell, particles-as-scenes):
```gdscript
class_name Pool
extends Node

@export var scene: PackedScene
@export var initial: int = 32
var _free: Array[Node] = []

func _ready() -> void:
    for i in initial: _free.append(_make())

func _make() -> Node:
    var n := scene.instantiate()
    n.set_meta("pool", self)
    return n

func acquire() -> Node:
    return _free.pop_back() if not _free.is_empty() else _make()

func release(n: Node) -> void:
    if n.get_parent(): n.get_parent().remove_child(n)
    _free.append(n)
```
Pooled scenes need a `reset()` convention instead of relying on `_ready`. Deactivate with `hide()` + `set_deferred("process_mode", PROCESS_MODE_DISABLED)` rather than freeing.

## 7. UI patterns

- **HUD binds to signals, never polls**: `Events.health_changed.connect(func(h, m): _bar.max_value = m; _bar.value = h)`. HUD knows about game state; game never knows about HUD.
- **Menus**: each screen its own scene under a `UI` CanvasLayer; a thin `ui_root.gd` shows/hides screens (or a stack for push/pop navigation). Buttons: `pressed.connect`. Keyboard/controller nav: set focus neighbors or rely on containers + `_root_button.grab_focus()` when the menu opens; the `ui_*` built-in actions (ui_accept, ui_cancel, ui_up...) drive it automatically.
- **Pause menu**: root Control `process_mode = PROCESS_MODE_WHEN_PAUSED`; toggling: `get_tree().paused = true; show()`. Its buttons work because WHEN_PAUSED nodes process during pause.
- **Responsive layout**: full-rect anchor the screen root; nest containers; never hardcode pixel positions for UI. Test with different window sizes early.
- **Settings screen**: sliders write `AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(value))`; persist via ConfigFile.

## 8. Audio manager

Buses (Audio panel): `Master ← Music, SFX`. Autoload scene with a `Music: AudioStreamPlayer (bus=Music)` and N pooled `AudioStreamPlayer (bus=SFX)` children:

```gdscript
func play_sfx(stream: AudioStream, pitch_jitter := 0.1) -> void:
    for p in $SFX.get_children():
        if not p.playing:
            p.stream = stream
            p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
            p.play()
            return
```
Positional sound: `AudioStreamPlayer2D/3D` on the entity itself. Music crossfade: two players + tween their `volume_db` (use `linear_to_db`; -80 db ≈ silent). Random variation: `AudioStreamRandomizer` resource.

## 9. Shaders quick reference

Godot's shading language is GLSL-like; `shader_type canvas_item;` (2D) or `spatial;` (3D). Attach via ShaderMaterial.

```glsl
shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    COLOR = mix(tex, vec4(1.0, 1.0, 1.0, tex.a), flash_amount);
}
```
Drive uniforms from GDScript: `(_sprite.material as ShaderMaterial).set_shader_parameter("flash_amount", 1.0)`. Remember `resource_local_to_scene = true` on the material if each instance flashes independently. `hint_range`, `source_color`, `instance uniforms` (per-instance without duplicating material, spatial only) are the hints you'll reach for. VisualShaders exist but hand-written `.gdshader` files are easier to review and diff.
