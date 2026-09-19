class_name Map3DLayerRoads
extends RefCounted
## Roads, trails and their bridges as one builder (spec 2026-09-20 §1): the
## pack's land routes, smoothed as the 2D map smooths them, draped on the
## relief through Map3DLayerLines (Lines/Roads, Lines/Trails), each drawn at
## its REAL width in the rocky_trail_02 texture up close, fading to the
## worn-sand palette colour far away (road_line.gdshader); and wherever one
## crosses a river it runs over a stone BRIDGE (Map3DBridges), built here as
## ONE mesh under Viewport/Bridges in the medieval_blocks_03 stone. Routes
## never move, so they are built once, after the rivers — the risk this task
## guards (bridges read the river courses).

const ROAD_SHADER := preload("res://scripts/map3d/road_line.gdshader")
## The road surface and the bridges' stone (Poly Haven, packed by
## tools/map3d/pack_textures.py into the git-ignored textures folder): a
## checkout without them draws flat roads and untextured stone.
const ROAD_TEXTURE := "res://assets/map3d/textures/rocky_trail_02"
const BRIDGE_TEXTURE := "res://assets/map3d/textures/medieval_blocks_03"

var ctx: Map3DContext
var lines: Map3DLayerLines
var viewport: SubViewport
## Every bridge built (Map3DBridges.plan's, each with its deck_w).
var _bridges: Array = []


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_viewport: SubViewport) -> void:
	ctx = p_ctx
	lines = p_lines
	viewport = p_viewport


## Roads and trails (each its own ribbon layer, Lines/Roads and Lines/Trails)
## and every bridge where one crosses `courses` (the rivers' own drawn
## courses — the rivers must already be built).
func build(courses: Array) -> void:
	var step := ctx.road_step()
	var all_bridges: Array = []
	for group: String in ["roads", "trails"]:
		var key := "road" if group == "roads" else "trail"
		var colour := MapTerrain.palette_color(ctx.repo, "map3d_" + key, MapTerrain.FALLBACK)
		colour.a = ctx.repo.bal("map3d_%s_alpha" % key)
		var width_m := ctx.repo.bal("map3d_%s_width_m" % key)
		var plan := Map3DBridges.plan(Map3DBorders.route_lines(ctx.repo, ctx.meta, group, step),
			courses, ctx.height_at, bridge_rules())
		_set_road(group.capitalize(), plan["lines"], plan["heights"], colour,
			"map3d_%s_width_px" % key, width_m)
		var deck_w := width_m + ctx.repo.bal("map3d_bridge_extra_w_m")
		for b: Dictionary in plan["bridges"]:
			b["deck_w"] = deck_w
		all_bridges.append_array(plan["bridges"])
	_build_bridges(all_bridges)


## balance.csv map3d_bridge_* as Map3DBridges' rules.
func bridge_rules() -> Dictionary:
	var rules: Dictionary = {}
	for key: String in ["abut_m", "clear_m", "clear_per_width", "hump_m", "min_sin", "merge_m",
			"deck_step_m", "deck_m", "parapet_h_m", "parapet_w_m", "arch_max_m", "pier_m",
			"end_over_water_m"]:
		rules[key] = ctx.repo.bal("map3d_bridge_" + key)
	return rules


## Test seam: every bridge built, [{a, b, ya, yb, crown, water_y, width, deck_w}].
func bridges() -> Array:
	return _bridges


## A packed Poly Haven pair (<base>_alb_ht / <base>_nrm_rgh), or [] when the
## textures folder has not been built.
static func texture_pair(base: String) -> Array:
	if not ResourceLoader.exists(base + "_alb_ht.png") or not ResourceLoader.exists(base + "_nrm_rgh.png"):
		Map3DWorldLoader.warn_once("textures:" + base,
			"Map3DView: %s_alb_ht/_nrm_rgh.png are not packed — drawn flat (tools/map3d/pack_textures.py)" % base)
		return []
	return [load(base + "_alb_ht.png"), load(base + "_nrm_rgh.png")]


## One road layer under Lines/<name>, replacing any before: the ribbons of
## `route_lines` on the ground (or on a bridge deck where `heights` says so).
func _set_road(line_name: String, route_lines: Array, heights: Array, colour: Color,
		width_key: String, width_m: float) -> void:
	var arrays := Map3DBorders.ribbon_arrays(route_lines, ctx.height_at, heights)
	var mat := ShaderMaterial.new()
	mat.shader = ROAD_SHADER
	mat.render_priority = Map3DPriority.ROADS
	mat.set_shader_parameter("colour", colour)
	mat.set_shader_parameter("width_m", width_m)
	mat.set_shader_parameter("edge_soft", ctx.repo.bal("map3d_road_edge_soft"))
	mat.set_shader_parameter("fray", ctx.repo.bal("map3d_road_fray"))
	mat.set_shader_parameter("tile_m", ctx.repo.bal("map3d_road_tile_m"))
	mat.set_shader_parameter("near_mpp", ctx.repo.bal("map3d_road_near_mpp"))
	mat.set_shader_parameter("far_mpp", ctx.repo.bal("map3d_road_far_mpp"))
	var gain := ctx.repo.bal("map3d_road_texture_gain")
	var tint := MapTerrain.palette_color(ctx.repo, "map3d_road_surface", Color.WHITE)
	mat.set_shader_parameter("surface_tint", Vector3(tint.r, tint.g, tint.b) * gain)
	var pair := texture_pair(ROAD_TEXTURE)
	mat.set_shader_parameter("has_surface", not pair.is_empty())
	if not pair.is_empty():
		mat.set_shader_parameter("surface", pair[0])
		mat.set_shader_parameter("surface_nrm", pair[1])
	mat.set_meta("width_key", width_key)
	lines.put_mesh(line_name, arrays, mat)


## Every bridge as ONE mesh in the medieval_blocks_03 stone, lit and casting
## shadows like the ground; replaces any before.
func _build_bridges(list: Array) -> void:
	_bridges = list
	# The authored scene's Viewport/Bridges is filled in place (its mesh null
	# when there are none); a bare viewport gets a node made for it.
	var mi := viewport.get_node_or_null("Bridges") as MeshInstance3D if viewport != null else null
	if mi != null:
		mi.mesh = null
	if list.is_empty() or viewport == null:
		return
	var rules := bridge_rules()
	var tile := ctx.repo.bal("map3d_bridge_tile_m")
	var mesh := ArrayMesh.new()
	# one deck width per group, so one mesh per width
	var by_w: Dictionary = {}
	for b: Dictionary in list:
		var w := float(b["deck_w"])
		if not by_w.has(w):
			by_w[w] = []
		(by_w[w] as Array).append(b)
	for w: float in by_w:
		var arrays := Map3DBridges.mesh_arrays(by_w[w], w, rules, tile)
		if not arrays.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() == 0:
		return
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = MapTerrain.palette_color(ctx.repo, "map3d_bridge", Color("#8A7F70"))
	mat.roughness = 0.9
	# Fade out far away, per pixel (the mesh spans the world, so a
	# visibility range, measured to its centre, would hide every bridge):
	# a min distance past the max inverts Godot's distance fade.
	var far := ctx.repo.bal("map3d_bridge_max_view_m")
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_min_distance = far
	mat.distance_fade_max_distance = far * 0.8
	var pair := texture_pair(BRIDGE_TEXTURE)
	if not pair.is_empty():
		mat.albedo_texture = pair[0]
		mat.normal_enabled = true
		mat.normal_texture = pair[1]
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, mat)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Bridges"
		viewport.add_child(mi)
	mi.mesh = mesh
