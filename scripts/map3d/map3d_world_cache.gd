class_name Map3DWorldCache
extends RefCounted
## One loaded 3D world kept between views (spec 2026-09-20 §3): a screen
## switch frees the view but hands its world back here, and the next view
## re-parents it instead of reloading 44 MB and recompiling the patched
## Terrain3D shader. At most ONE world, lent to one view at a time (Ruling
## 13): a second live view loads its own copy, with its own terrain material.

## Where _detach keeps a terrain's collision mode while the world is unlent.
const COLLISION_META := &"map3d_cache_collision_mode"

static var _path := ""
static var _world: Node3D = null
static var _lent := false


## The kept world for `scene_path`, now lent to the caller — or null (load it).
static func take(scene_path: String) -> Node3D:
	if _lent or _path != scene_path or _world == null or not is_instance_valid(_world):
		return null
	_lent = true
	_reattach(_world)
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



## Out of its view's tree, its terrain's collision taken down while the old
## view's physics space still lives: Terrain3D 1.0.2 keeps its collision body
## across a tree exit, and freeing it later — once that space died with the
## old SubViewport's World3D — crashed the engine on the next add_child
## (found 2026-09-20). take() puts the mode back; the camera Terrain3D lets
## go of by itself on exit and grabs the new view's on its next frame.
static func _detach(world: Node3D) -> void:
	for t in world.find_children("*", "Terrain3D", true, false):
		if "collision_mode" in t:
			if not t.has_meta(COLLISION_META):
				t.set_meta(COLLISION_META, int(t.get("collision_mode")))
			t.set("collision_mode", 0)
	if world.get_parent() != null:
		world.get_parent().remove_child(world)


## The collision mode _detach took down, put back once the borrower has put
## the world in its tree (deferred: Terrain3D builds collision only in a world).
static func _reattach(world: Node3D) -> void:
	for t in world.find_children("*", "Terrain3D", true, false):
		if t.has_meta(COLLISION_META):
			t.set.call_deferred("collision_mode", int(t.get_meta(COLLISION_META)))
			t.remove_meta(COLLISION_META)
