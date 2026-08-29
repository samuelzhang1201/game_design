# Nodes, Scenes, and the SceneTree

## Contents
1. Node taxonomy — choosing the right type
2. Node lifecycle & callbacks
3. Scenes: instancing, ownership, runtime spawning
4. SceneTree operations (change scenes, groups, pause)
5. Authoring .tscn files as text
6. Viewports and CanvasLayers

## 1. Node taxonomy — choosing the right type

The class tree fans out from `Object → Node → (CanvasItem → Node2D/Control) | Node3D`. Pick the *most specific* node that does the job; pick the *most generic* (`Node`) when you need no transform at all (managers, state machines, folder-nodes).

### Physics bodies (2D and 3D mirror each other)
| Node | Use for | Key API |
|---|---|---|
| `StaticBody2D/3D` | Immovable world geometry, floors, walls | collision layers |
| `AnimatableBody2D/3D` | Platforms moved by code/AnimationPlayer that push bodies | `sync_to_physics` |
| `CharacterBody2D/3D` | Player/NPC with scripted kinematic movement | `velocity`, `move_and_slide()`, `is_on_floor()`, `get_slide_collision_count()` |
| `RigidBody2D/3D` | Physics-simulated objects (crates, ragdolls, balls) | `apply_impulse()`, `apply_force()`, `_integrate_forces()` — do NOT set position directly each frame |
| `Area2D/3D` | Detection zones, triggers, pickups, hit/hurtboxes, gravity/audio overrides | `body_entered`, `area_entered` signals, `monitoring` |

Every body needs a `CollisionShape2D/3D` (or Polygon) child with an actual Shape resource. Collision **layer** = "what I am"; **mask** = "what I see". An Area detecting the player: area's mask includes the player's layer.

Since 4.6, 3D physics defaults to **Jolt**. API is the same; behavior/tuning may differ from the old GodotPhysics3D.

### Rendering & visuals
- 2D: `Sprite2D`, `AnimatedSprite2D` (SpriteFrames resource), `TileMapLayer` (4.3+; the monolithic `TileMap` is deprecated — use one `TileMapLayer` node per layer), `Line2D`, `Polygon2D`, `GPUParticles2D`/`CPUParticles2D`, `Camera2D`, `PointLight2D`, `CanvasModulate`.
- 3D: `MeshInstance3D`, `MultiMeshInstance3D` (thousands of identical meshes), `GPUParticles3D`, `Camera3D`, `DirectionalLight3D`/`OmniLight3D`/`SpotLight3D`, `WorldEnvironment` (Environment resource: sky, fog, glow, tonemap), `Decal`, `ReflectionProbe`, `CSG*` nodes (prototyping only — replace with real meshes for production).
- Animation: `AnimationPlayer` (tracks animate ANY property of ANY node, call methods, play audio — the workhorse), `AnimationTree` (state machines/blend spaces over AnimationPlayer clips, for character animation blending), `Tween` (created in code: `create_tween()` — for procedural one-off animation), `Skeleton3D`/`Skeleton2D` + IK modifiers.

### Control (UI) nodes
`Control` subclasses live in a separate layout system (anchors/offsets, not transforms).
- Containers do layout for you — prefer them over manual anchoring: `HBoxContainer`, `VBoxContainer`, `GridContainer`, `MarginContainer`, `PanelContainer`, `ScrollContainer`, `CenterContainer`, `TabContainer`, `SplitContainer`, `FlowContainer`. Children of containers ignore manual position; use `size_flags` (fill/expand/shrink) and `custom_minimum_size`.
- Widgets: `Label`, `RichTextLabel` (BBCode), `Button`/`TextureButton`/`CheckBox`/`OptionButton`, `LineEdit`/`TextEdit`, `TextureRect`, `ProgressBar`/`TextureProgressBar`, `Slider`, `SpinBox`, `ItemList`, `Tree`, `ColorRect`, `NinePatchRect`.
- Style with a single `Theme` resource applied at the UI root; per-control `theme_override_*` only for exceptions. StyleBoxFlat for panels/buttons.
- `mouse_filter` (Stop/Pass/Ignore) controls click-through; full-screen decorative Controls must be `Ignore` or they eat all input.

### Sound, timing, paths, misc
`AudioStreamPlayer` (non-positional; music/UI), `AudioStreamPlayer2D/3D` (positional), `Timer` (`timeout` signal, `one_shot`), `Path2D/3D` + `PathFollow2D/3D` (move along curves), `RayCast2D/3D` and `ShapeCast2D/3D` (cheap queries without bodies), `RemoteTransform2D/3D`, `Marker2D/3D` (named positions: spawn points, muzzle), `NavigationRegion2D/3D` + `NavigationAgent2D/3D` (pathfinding; call `agent.get_next_path_position()` each physics frame), `HTTPRequest`, `CanvasLayer`, `SubViewport`.

## 2. Node lifecycle & callbacks

Order for a node entering the tree:
1. `_init()` — constructor; no tree access yet.
2. `_enter_tree()` — parent-first, top-down. Node is in tree; children NOT ready.
3. `_ready()` — **children-first, bottom-up**. All `@onready` vars resolved just before this. Safe to touch children; parent's `_ready` hasn't run yet.
4. Per frame: `_process(delta)` (render tick) and `_physics_process(delta)` (fixed tick, default 60 Hz) — enabled automatically when defined; toggle with `set_process(false)` etc.
5. Input chain (first taker wins): `_input(event)` → Control `_gui_input` → `_shortcut_input` → `_unhandled_key_input` → `_unhandled_input(event)`. **Gameplay input belongs in `_unhandled_input`** so UI naturally consumes clicks first. Call `get_viewport().set_input_as_handled()` to stop propagation. Continuous polling (`Input.is_action_pressed`) goes in `_process`/`_physics_process`.
6. `_exit_tree()` — cleanup; also fires on scene change.
7. `_notification(what)` — low-level hooks: `NOTIFICATION_WM_CLOSE_REQUEST` (save on quit), `NOTIFICATION_APPLICATION_PAUSED` (mobile), `NOTIFICATION_PREDELETE`.

Key facts that prevent bugs:
- A freed node isn't gone until end of frame with `queue_free()`. Guard stored references with `is_instance_valid(ref)`.
- Changing the tree (add/remove/free/reparent) from a physics callback or signal fired during physics (`body_entered`) → use `call_deferred("add_child", n)` / `n.queue_free()` (queue_free is safe) / `set_deferred("monitoring", false)`.
- `await get_tree().process_frame` waits one frame; `await get_tree().create_timer(1.0).timeout` is a one-shot delay; `await some_signal` suspends until emission.
- `_ready` runs once. Re-entering the tree fires `_enter_tree` again but not `_ready` (use `request_ready()` to re-arm).

## 3. Scenes: instancing, ownership, runtime spawning

A scene (`.tscn`/`.scn`) is a serialized node tree = a `PackedScene` resource. Instancing stamps a copy into another tree. Scenes are simultaneously: prefabs, levels, UI screens, components, and the unit of testing (F6 runs the selected scene alone — design scenes to run standalone with sane defaults).

```gdscript
const BULLET: PackedScene = preload("res://entities/projectiles/bullet.tscn")

func shoot() -> void:
    var bullet := BULLET.instantiate() as Bullet
    bullet.global_position = %Muzzle.global_position
    bullet.direction = aim_direction
    get_tree().current_scene.add_child(bullet)   # or a dedicated container node
```

- Set properties BEFORE `add_child()` when `_ready` depends on them, or add an explicit `setup()` method convention.
- Spawned projectiles/pickups usually should NOT be children of their spawner (they'd move/die with it) — parent them to the level.
- **Editable Children** (right-click an instance) lets a level override an instance's internals — use rarely; prefer exported properties on the scene root as its public API.
- The **scene root's script is the scene's interface**: `@export` vars for configuration, methods for commands, signals for events. Internal nodes are private — outside code never `get_node()`s into another scene's guts. Enforce with **scene unique names**: mark internal nodes `%` (Access as Unique Name) and reference as `%HealthBar` — survives internal restructuring.
- `owner`: nodes saved with a scene have `owner` = scene root. Runtime-added children need `child.owner = root` only if you plan to re-pack with `PackedScene.pack(root)` (e.g., saving a built level).

## 4. SceneTree operations

```gdscript
get_tree().change_scene_to_packed(preload("res://levels/level_02.tscn"))  # deferred, safe
get_tree().change_scene_to_file("res://levels/level_02.tscn")
get_tree().reload_current_scene()
get_tree().paused = true
get_tree().quit()
```
For transitions with fades/loading screens, don't use change_scene at all — a SceneManager autoload frees the old level node and adds the new one under a persistent root (see systems-cookbook.md).

**Pause**: `get_tree().paused = true` halts nodes per their `process_mode`: `PROCESS_MODE_INHERIT` (default), `PAUSABLE`, `WHEN_PAUSED` (pause menu!), `ALWAYS`, `DISABLED`. Set the pause menu's root to `WHEN_PAUSED`.

**Groups** — tag nodes across scenes (`add_to_group("enemies")` or in the editor):
```gdscript
get_tree().call_group("enemies", "alert", player.global_position)
var enemies := get_tree().get_nodes_in_group("enemies")
if body.is_in_group("player"): ...
```
Groups are Godot's answer to "find all X" — cheaper and cleaner than tree traversal.

**Timing**: `Engine.time_scale` (slow-mo), `Engine.physics_ticks_per_second`, `Engine.max_fps`.

## 5. Authoring .tscn files as text

`.tscn` is a readable INI-like format — you can write scenes directly, which is essential when working headless. Anatomy:

```
[gd_scene load_steps=4 format=3 uid="uid://c8x2v4qk7nfa3"]

[ext_resource type="Script" path="res://entities/player/player.gd" id="1_a2bcd"]
[ext_resource type="Texture2D" path="res://entities/player/player_sprite.png" id="2_e3fgh"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]
size = Vector2(14, 28)

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1_a2bcd")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2_e3fgh")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_1")

[node name="Muzzle" type="Marker2D" parent="."]
unique_name_in_owner = true
position = Vector2(10, 0)
```

Rules when writing by hand:
- `load_steps` = ext_resources + sub_resources + 1. `format=3` for Godot 4.
- `uid="uid://..."` — omit the whole attribute if you can't generate one; Godot assigns on next editor open. Never invent a uid that might collide; never duplicate an existing uid.
- Instancing another scene: declare it as ext_resource (`type="PackedScene"`) then `[node name="Hud" parent="UI" instance=ExtResource("3_hud")]`.
- Only non-default property values are written.
- Signal connections: `[connection signal="pressed" from="StartButton" to="." method="_on_start_pressed"]` — placed at file end.
- `parent="."` = root; deeper paths like `parent="UI/HUD"`.

## 6. Viewports and CanvasLayers

- `CanvasLayer` renders its children in screen space, ignoring Camera2D — HUD, menus, transition fades (`layer` property orders them; use e.g. 100 for the fade layer).
- `SubViewport` (+`SubViewportContainer` or as a ViewportTexture) = render-to-texture: minimaps, 3D character in 2D UI, split-screen, in-world screens.
- The root `Window` is a Viewport; `get_viewport().get_visible_rect().size` for screen size in 2D, `get_window().size` for the OS window.
- World coordinates ↔ screen: `get_global_mouse_position()` (2D world), `camera.unproject_position()` / `project_ray_origin()` (3D↔screen).
