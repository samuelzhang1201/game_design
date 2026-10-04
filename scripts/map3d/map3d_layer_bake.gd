class_name Map3DLayerBake
extends RefCounted
## The build's baked static layers (spec 2026-09-20 §2): rivers, roads,
## trails and bridges never move, so tools/map3d/bake_layers.gd saves their
## ArrayMeshes beside the world, one set per distinct step set of
## data/graphics_quality.csv (Ruling 14), with layers/manifest.json naming the
## key each was baked under. The runtime uses a set only when it is complete
## and its key matches every input today; otherwise it builds as before.

## Versions the OUTPUT of GEOMETRY_SOURCES: the runtime key cannot hash the
## scripts (an exported build need not ship the .gd sources), so a change to
## any of them bumps this, and tests/map3d/test_map3d_layer_bake.gd holds
## GEOMETRY_MD5 to their text so the bump cannot be forgotten.
## THE ONE EXCEPTION (Task 22): an edit to those files that cannot reach the
## baked vertices — a `@tool` line, editor-only preview code, a comment —
## updates GEOMETRY_MD5 ALONE and leaves FORMAT and the bakes as they are.
const FORMAT := 1
## Every script the baked meshes' vertices come from: the layers' arrays_for /
## plan_for / bridge_mesh, the river, bridge and ribbon builders, the pack ->
## world maths and the route smoothing, and the context's heights and steps.
const GEOMETRY_SOURCES := ["res://scripts/map3d/map3d_layer_rivers.gd",
	"res://scripts/map3d/map3d_layer_roads.gd", "res://scripts/map3d/map3d_rivers.gd",
	"res://scripts/map3d/map3d_bridges.gd", "res://scripts/map3d/map3d_borders.gd",
	"res://scripts/map3d/map3d_geometry.gd", "res://scripts/map3d/map3d_context.gd",
	"res://scripts/engine/map_geometry.gd"]
## The md5 of GEOMETRY_SOURCES' text, concatenated in list order.
const GEOMETRY_MD5 := "7fbaad56b8bcdac020a7f95bd9b16ab0"
const LAYERS := ["rivers", "roads", "trails", "bridges"]
const KEYS := ["map3d_road_step_m", "map3d_river_mesh_step_m", "map3d_river_split_rise_m",
	"map3d_river_terrain_clear_m", "map3d_river_end_fade_m", "map3d_road_width_m",
	"map3d_trail_width_m", "map_route_smoothing_steps", "map3d_bridge_abut_m",
	"map3d_bridge_clear_m", "map3d_bridge_clear_per_width", "map3d_bridge_hump_m",
	"map3d_bridge_min_sin", "map3d_bridge_merge_m", "map3d_bridge_deck_step_m",
	"map3d_bridge_deck_m", "map3d_bridge_extra_w_m", "map3d_bridge_parapet_h_m",
	"map3d_bridge_parapet_w_m", "map3d_bridge_arch_max_m", "map3d_bridge_pier_m",
	"map3d_bridge_tile_m", "map3d_bridge_end_over_water_m"]


static func step_set(row: Dictionary) -> String:
	return "r%d_v%d" % [roundi(Map3DQuality.num(row, "road_step_mul") * 100.0),
		roundi(Map3DQuality.num(row, "river_step_mul") * 100.0)]


static func key(repo: DataRepository, scene_dir: String, row: Dictionary) -> String:
	var parts: Array = [FORMAT, step_set(row)]
	for k: String in KEYS:
		parts.append(repo.bal(k))
	parts.append(FileAccess.get_md5(scene_dir.path_join("rivers.json")))
	var data_dir := String((repo.maps.get(repo.map_id, {}) as Dictionary).get("data_dir", ""))
	parts.append(FileAccess.get_md5(data_dir.path_join("geography/routes.csv")))
	var built := ""
	var man := scene_dir.path_join("manifest.json")
	if FileAccess.file_exists(man):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(man))
		if m is Dictionary:
			built = String((m as Dictionary).get("built_at", ""))
	parts.append(built)
	return var_to_str(parts).md5_text()


static func file(scene_dir: String, layer: String, row: Dictionary) -> String:
	return scene_dir.path_join("layers/%s_%s.res" % [layer, step_set(row)])


static func _manifest(scene_dir: String) -> Dictionary:
	var path := scene_dir.path_join("layers/manifest.json")
	if not FileAccess.file_exists(path):
		return {}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return m if m is Dictionary else {}


static func complete(scene_dir: String, row: Dictionary, bake_key: String) -> bool:
	if String(_manifest(scene_dir).get(step_set(row), "")) != bake_key:
		return false
	for layer: String in LAYERS:
		if not ResourceLoader.exists(file(scene_dir, layer, row)):
			return false
	return true


static func load_all(scene_dir: String, row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for layer: String in LAYERS:
		out[layer] = load(file(scene_dir, layer, row)) as ArrayMesh
	return out


static func save(scene_dir: String, row: Dictionary, bake_key: String, meshes: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scene_dir.path_join("layers")))
	for layer: String in LAYERS:
		var mesh: ArrayMesh = meshes.get(layer, ArrayMesh.new())
		var err := ResourceSaver.save(mesh, file(scene_dir, layer, row))
		if err != OK:
			return err
	var m := _manifest(scene_dir)
	m[step_set(row)] = bake_key
	var f := FileAccess.open(scene_dir.path_join("layers/manifest.json"), FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_string(JSON.stringify(m, "  "))
	f.close()
	return OK


static func mesh_of(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The view's rivers, roads, trails and bridges: the build's bake when it is
## complete and its key matches every input today, else built now as before.
## True when the bake was used. The roads must be bound to their lines.
static func build_layers(ctx: Map3DContext, scene_path: String, rivers: Map3DLayerRivers,
		roads: Map3DLayerRoads) -> bool:
	var dir := Map3DWorldLoader.data_dir(scene_path)
	var row := ctx.q()
	if complete(dir, row, key(ctx.repo, dir, row)):
		var m := load_all(dir, row)
		rivers.build_baked(ctx, m["rivers"])
		roads.build_baked(m)
		return true
	if FileAccess.file_exists(dir.path_join("layers/manifest.json")):
		Map3DWorldLoader.warn_once("layers:" + dir,
			"Map3DLayerBake: %s/layers is stale for step set %s — built at load instead; run tools/map3d/bake_layers.gd"
			% [dir, step_set(row)])
	rivers.build(ctx, scene_path)
	roads.build(rivers.courses())
	return false
