class_name Map3DWorldCache
extends RefCounted
## One loaded 3D world kept between views (spec 2026-09-20 §3): a screen
## switch frees the view but hands its world back here, and the next view
## re-parents it instead of reloading 44 MB and recompiling the patched
## Terrain3D shader. At most ONE world, lent to one view at a time (Ruling
## 13): a second live view loads its own copy, with its own terrain material.

static var _path := ""
static var _world: Node3D = null
static var _lent := false


## The kept world for `scene_path`, now lent to the caller — or null (load it).
static func take(scene_path: String) -> Node3D:
	if _lent or _path != scene_path or _world == null or not is_instance_valid(_world):
		return null
	_lent = true
	return _world


## The world a view opens at `scene_path`: the kept one when free, else a
## fresh Map3DWorldLoader.instance (adopted) — or the loader's state string
## ("missing" | "stale" | "bad") when the build cannot be opened.
static func lend(scene_path: String) -> Variant:
	var kept := take(scene_path)
	if kept != null:
		return kept
	var state := String(Map3DWorldLoader.status(scene_path)["state"])
	if state != "ok" and state != "legacy":
		return state
	var world := Map3DWorldLoader.instance(scene_path)
	if world == null:
		return "bad"
	adopt(scene_path, world)
	return world


## A freshly loaded world, lent to the view that loaded it — unless the kept
## one is lent elsewhere, in which case the fresh copy stays unkept.
static func adopt(scene_path: String, world: Node3D) -> void:
	if _lent:
		return
	_drop()
	_path = scene_path
	_world = world
	_lent = true


## A view is done with `world`: keep it detached, or drop it when it is not
## the kept one and the kept one is still lent.
static func give_back(scene_path: String, world: Node3D) -> void:
	if world == null or not is_instance_valid(world):
		return
	_detach(world)
	if world == _world:
		_lent = false
		return
	if _lent:
		world.free()
		return
	_drop()
	_path = scene_path
	_world = world


static func clear() -> void:
	if not _lent:
		_drop()
	_path = ""
	_world = null
	_lent = false


static func held() -> String:
	return _path


static func lent() -> bool:
	return _lent


static func _drop() -> void:
	if _world != null and is_instance_valid(_world) and _world.get_parent() == null:
		_world.free()
	_world = null



## Out of its view's tree. Its terrain has no collision to outlive the view's
## physics space: Map3DWorldLoader.no_collision took it down at load.
static func _detach(world: Node3D) -> void:
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
