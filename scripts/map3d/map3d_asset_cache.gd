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
static var _meshes: Dictionary = {}   # path -> the first Mesh of its scene
static var _houses_key := ""
static var _houses_pristine: Dictionary = {}
static var _houses_world := 0
static var _houses: Dictionary = {}


## The PackedScene at `path`, loaded once; null when there is none.
static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


## The first Mesh of the scene at `path` (a house type's .glb), loaded once.
static func mesh(path: String) -> Mesh:
	if not _meshes.has(path):
		var packed := scene(path)
		var out: Mesh = null
		if packed != null:
			var node := packed.instantiate()
			out = Map3DHouses.first_mesh(node)
			node.free()
		_meshes[path] = out
	return _meshes[path]


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
	_meshes.clear()
	_houses_key = ""
	_houses_pristine = {}
	_houses_world = 0
	_houses = {}
