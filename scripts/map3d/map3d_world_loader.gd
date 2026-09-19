class_name Map3DWorldLoader
extends RefCounted
## Opens a pack's BUILT world (tools/map3d) for the view (spec 2026-09-20
## §1, Task 14). The build is DATA — terrain, meta, rivers, fields; the sun,
## the sky, the sea and the framing shots belong to the view's authored scene
## (and to tools/map3d/shoot.gd). A build made before 2026-09-20 still carries
## its own Sun, Environment, Sea and cameras: they are removed on load, so a
## world never holds two suns or two skies.
##
## Since Task 15 a build also writes `manifest.json` beside world.tscn (its
## format version, meta, build time and the bake tables' fingerprint), and
## `status` says honestly why there is no 3D map — missing, stale (built by an
## older pipeline, or the manifest describes another world), bad (damaged) —
## with `notice_text` naming the command that fixes it. A build with no
## manifest (before 2026-09-20, and every test fixture) is `legacy` and loads.

## The build's format: 2 is data only (build_terrain.gd writes it into the
## `map3d_world` meta); an older build has none and is stripped on load.
const FORMAT_VERSION := 2
## What a build before format 2 put beside the terrain.
const OLD_BUILD_NODES := ["Sun", "Environment", "Sea", "Camera3D", "CameraMid", "CameraNear"]
## What the view says for each state it cannot load, `%s` the map id.
const NOTICES := {
	"missing": "The 3D map has not been built for this map.\nRun tools/map3d/build_pack.sh --map %s (see tools/map3d/README.md).",
	"stale": "This 3D map was built by an older pipeline.\nRebuild it: tools/map3d/build_pack.sh --map %s",
	"bad": "This 3D map's build is damaged.\nRebuild it: tools/map3d/build_pack.sh --map %s",
}
## The warnings already given, so a missing optional input is said once.
static var _warned: Dictionary = {}


## Whether the build at `scene_path` can be opened: `{state, why, manifest}`,
## state "ok" | "legacy" (no manifest; loads) | "missing" | "stale" | "bad".
static func status(scene_path: String) -> Dictionary:
	if not ResourceLoader.exists(scene_path):
		return {"state": "missing", "why": scene_path + " is not built", "manifest": {}}
	var mpath := scene_path.get_base_dir().path_join("manifest.json")
	if not FileAccess.file_exists(mpath):
		warn_once("legacy:" + scene_path,
			"Map3DWorldLoader: %s has no manifest.json (a build from before 2026-09-20)" % scene_path)
		return {"state": "legacy", "why": "", "manifest": {}}
	var json := JSON.new()  # parse() reports through its return, parse_string() prints an error
	if json.parse(FileAccess.get_file_as_string(mpath)) != OK or not (json.data is Dictionary):
		return {"state": "bad", "why": "manifest.json is not a JSON object", "manifest": {}}
	var m: Dictionary = json.data
	var v := int(m.get("format_version", 0))
	if v != FORMAT_VERSION:
		return {"state": "stale", "why": "built by pipeline v%d; the game reads v%d" % [v, FORMAT_VERSION],
			"manifest": m}
	var sm := scene_meta(scene_path)
	if sm.is_empty():
		return {"state": "bad", "why": "the scene's root carries no map3d_world", "manifest": m}
	var mm: Variant = m.get("meta", {})
	if not (mm is Dictionary) or not same_meta(mm, sm):
		return {"state": "stale", "why": "manifest.json describes another world than the scene",
			"manifest": m}
	if String(m.get("steps_hash", "")) != steps_hash():
		warn_once("steps:" + scene_path,
			"Map3DWorldLoader: the bake tables changed since %s was built — rebuild to see them" % scene_path)
	return {"state": "ok", "why": "", "manifest": m}


## The root's map3d_world meta, read from the packed scene without instancing
## it (the load is cached; instance() reuses it).
static func scene_meta(scene_path: String) -> Dictionary:
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return {}
	var st := ps.get_state()
	if st.get_node_count() == 0:
		return {}
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == &"metadata/map3d_world":
			var value: Variant = st.get_node_property_value(0, i)
			return value if value is Dictionary else {}
	return {}


## The notice for a state the view cannot load (an unknown state reads "bad").
static func notice_text(state: String, map_id: String) -> String:
	return String(NOTICES.get(state, NOTICES["bad"])) % map_id


## The bake inputs' fingerprint: data/map3d_bake.csv and data/map3d_fields.csv.
static func steps_hash() -> String:
	return (FileAccess.get_md5("res://data/map3d_bake.csv")
		+ FileAccess.get_md5("res://data/map3d_fields.csv")).md5_text()


## Two map3d_world metas describe the same world (JSON turns 2560 into 2560.0).
static func same_meta(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["m_per_px", "sea_y"]:
		if not is_equal_approx(float(a.get(key, 0.0)), float(b.get(key, 0.0))):
			return false
	for key: String in ["pack_origin", "pack_px"]:
		var x: Variant = a.get(key, [])
		var y: Variant = b.get(key, [])
		if not (x is Array and y is Array) or (x as Array).size() != (y as Array).size():
			return false
		for i in (x as Array).size():
			if not is_equal_approx(float(x[i]), float(y[i])):
				return false
	return true


## push_warning once per `key` (until clear_warnings).
static func warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)


static func clear_warnings() -> void:
	_warned.clear()


## The world at `scene_path`, stripped and with its own terrain material, or
## null when the file is missing or is not a built world (no `map3d_world` meta).
static func instance(scene_path: String) -> Node3D:
	if not ResourceLoader.exists(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	var w: Node3D = packed.instantiate() as Node3D if packed != null else null
	if w == null or not w.has_meta("map3d_world"):
		if w != null:
			w.free()
		return null
	strip_old_build(w)
	own_terrain_material(w)
	return w


## Removes an old build's sun, sky, sea and framing cameras (none in format 2).
static func strip_old_build(world: Node3D) -> void:
	for node_name: String in OLD_BUILD_NODES:
		var n := world.get_node_or_null(node_name)
		if n != null:
			world.remove_child(n)
			n.free()


## Each instance gets its OWN terrain material: the loaded one is shared, and
## the first view's teardown left the second's ground untinted (owner 2026-09-19).
static func own_terrain_material(world: Node3D) -> void:
	for t in world.find_children("*", "Terrain3D", true, false):
		var m: Resource = t.get("material")
		if m != null:
			t.set("material", m.duplicate(true))
