class_name Map3DAssetCache
extends RefCounted
## What every 3D view loads and none of them changes, kept between views
## (2026-10-02), as Map3DWorldCache keeps the world: a screen switch frees its
## view, and the next one loaded it all again — the regiments' and couriers'
## .glb models (~0.5 s), the house meshes with the palaces' 2K maps (~1.1 s),
## the bake's houses.csv (~0.26 s) and the woods' clumps (Map3DLayerTrees,
## ~0.5 s; kept there, by its own inputs) — ~2.4 s a swap, measured.
##
## Only what is read-only is kept: a view still makes its OWN nodes and its
## own materials (the house tints, the weather's uniforms on them), so two
## views never share a material the other one writes.

static var _scenes: Dictionary = {}   # path -> PackedScene, null when missing
static var _models: Dictionary = {}   # path -> a house scene's {mesh, materials}
static var _houses_key := ""
static var _houses_pristine: Dictionary = {}
static var _houses_world := 0
static var _houses: Dictionary = {}


## The PackedScene at `path`, loaded once; null when there is none.
static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


## A house type's scene at `path` (its <type>.tscn, which inherits the .glb),
## loaded once: {mesh, materials} — its first MeshInstance3D's mesh and the
## material each surface wears in the scene (its override, edited there, else
## the mesh's own); {} when there is none.
static func house_model(path: String) -> Dictionary:
	if not _models.has(path):
		var packed := scene(path)
		var out: Dictionary = {}
		if packed != null:
			var node := packed.instantiate()
			var mi := Map3DHouses.first_mesh_instance(node)
			if mi != null:
				var mats: Array[Material] = []
				for i in mi.mesh.get_surface_count():
					mats.append(mi.get_active_material(i))
				out = {"mesh": mi.mesh, "materials": mats}
			node.free()
		_models[path] = out
	return _models[path]


## The bake's houses at `csv_path` (Map3DHouses.load_csv), parsed once per
## file version. The rows carry each house's seat on `world`'s ground
## (Map3DLayerHouses.refresh writes `_seat` into them), so every world gets
## its own copy of the parse: a seat sampled on one world's terrain is never
## read on another's. One world is kept, like Map3DWorldCache's one.
static func houses(csv_path: String, world: Node3D) -> Dictionary:
	var key := "%s@%d" % [csv_path, FileAccess.get_modified_time(csv_path)]
	if key != _houses_key:
		_houses_key = key
		_houses_pristine = Map3DHouses.load_csv(csv_path)
		_houses_world = 0
	var id := world.get_instance_id() if world != null else -1
	if id != _houses_world:
		_houses_world = id
		_houses = _houses_pristine.duplicate(true)
	return _houses


## Forget everything (a test that rebuilds an asset in place).
static func clear() -> void:
	_scenes.clear()
	_models.clear()
	_houses_key = ""
	_houses_pristine = {}
	_houses_world = 0
	_houses = {}
