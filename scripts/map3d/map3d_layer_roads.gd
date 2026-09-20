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

## The roads' and the bridges' looks (spec 2026-09-20 §2): shader, render
## priority and the committed 512 px previews of their textures
## (tools/map3d/make_previews.gd); every tuned number is bound below.
const ROAD_MAT := preload("res://scenes/map3d/materials/road_line.tres")
const BRIDGE_MAT := preload("res://scenes/map3d/materials/bridge_stone.tres")
## The road surface and the bridges' stone at full resolution (Poly Haven,
## packed by tools/map3d/pack_textures.py into the git-ignored textures
## folder): they replace the previews when present (Ruling 15).
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
	var plan := plan_for(ctx, courses)
	for line_name: String in ["Roads", "Trails"]:
		lines.put_mesh(line_name, plan[line_name], road_material(ctx, line_name))
	_place_bridges(bridge_mesh(ctx, plan["bridges"]))


## The build's baked roads, trails and bridges (Map3DLayerBake), drawn as
## they are: the loaded meshes are shared, so they are never edited.
func build_baked(meshes: Dictionary) -> void:
	lines.put_baked("Roads", meshes["roads"], road_material(ctx, "Roads"))
	lines.put_baked("Trails", meshes["trails"], road_material(ctx, "Trails"))
	_place_bridges(meshes["bridges"])  # its meta "bridges" is the list


## What build() draws and tools/map3d/bake_layers.gd saves (Task 20): the
## ribbon arrays of "Roads" and "Trails" (on the ground, or on a bridge deck)
## and "bridges", every bridge where one crosses `courses`, each with its deck_w.
static func plan_for(p_ctx: Map3DContext, courses: Array) -> Dictionary:
	var step := p_ctx.road_step()
	var out: Dictionary = {"bridges": []}
	var rules := bridge_rules_of(p_ctx.repo)
	for group: String in ["roads", "trails"]:
		var key := "road" if group == "roads" else "trail"
		var width_m := p_ctx.repo.bal("map3d_%s_width_m" % key)
		var plan := Map3DBridges.plan(Map3DBorders.route_lines(p_ctx.repo, p_ctx.meta, group, step),
			courses, p_ctx.height_at, rules)
		out[group.capitalize()] = Map3DBorders.ribbon_arrays(plan["lines"], p_ctx.height_at,
			plan["heights"])
		var deck_w := width_m + p_ctx.repo.bal("map3d_bridge_extra_w_m")
		for b: Dictionary in plan["bridges"]:
			b["deck_w"] = deck_w
		(out["bridges"] as Array).append_array(plan["bridges"])
	return out


## balance.csv map3d_bridge_* as Map3DBridges' rules.
func bridge_rules() -> Dictionary:
	return bridge_rules_of(ctx.repo)


static func bridge_rules_of(repo: DataRepository) -> Dictionary:
	var rules: Dictionary = {}
	for key: String in ["abut_m", "clear_m", "clear_per_width", "hump_m", "min_sin", "merge_m",
			"deck_step_m", "deck_m", "parapet_h_m", "parapet_w_m", "arch_max_m", "pier_m",
			"end_over_water_m"]:
		rules[key] = repo.bal("map3d_bridge_" + key)
	return rules


## Test seam: every bridge built, [{a, b, ya, yb, crown, water_y, width, deck_w}].
func bridges() -> Array:
	return _bridges


## A packed Poly Haven pair (<base>_alb_ht / <base>_nrm_rgh), or [] when the
## textures folder has not been built (the material's preview pair stays).
static func texture_pair(base: String) -> Array:
	if not ResourceLoader.exists(base + "_alb_ht.png") or not ResourceLoader.exists(base + "_nrm_rgh.png"):
		Map3DWorldLoader.warn_once("textures:" + base,
			"Map3DView: %s_alb_ht/_nrm_rgh.png are not packed — drawn with the 512 px previews (tools/map3d/pack_textures.py)" % base)
		return []
	return [load(base + "_alb_ht.png"), load(base + "_nrm_rgh.png")]


## The road_line.gdshader material of Lines/Roads or Lines/Trails.
static func road_material(p_ctx: Map3DContext, line_name: String) -> ShaderMaterial:
	var key := "road" if line_name == "Roads" else "trail"
	var colour := MapTerrain.palette_color(p_ctx.repo, "map3d_" + key, MapTerrain.FALLBACK)
	colour.a = p_ctx.repo.bal("map3d_%s_alpha" % key)
	var mat := (ROAD_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	mat.render_priority = Map3DPriority.ROADS
	mat.set_shader_parameter("colour", colour)
	mat.set_shader_parameter("width_m", p_ctx.repo.bal("map3d_%s_width_m" % key))
	mat.set_shader_parameter("edge_soft", p_ctx.repo.bal("map3d_road_edge_soft"))
	mat.set_shader_parameter("fray", p_ctx.repo.bal("map3d_road_fray"))
	mat.set_shader_parameter("tile_m", p_ctx.repo.bal("map3d_road_tile_m"))
	mat.set_shader_parameter("near_mpp", p_ctx.repo.bal("map3d_road_near_mpp"))
	mat.set_shader_parameter("far_mpp", p_ctx.repo.bal("map3d_road_far_mpp"))
	var gain := p_ctx.repo.bal("map3d_road_texture_gain")
	var tint := MapTerrain.palette_color(p_ctx.repo, "map3d_road_surface", Color.WHITE)
	mat.set_shader_parameter("surface_tint", Vector3(tint.r, tint.g, tint.b) * gain)
	var pair := texture_pair(ROAD_TEXTURE)
	if not pair.is_empty():
		mat.set_shader_parameter("surface", pair[0])
		mat.set_shader_parameter("surface_nrm", pair[1])
	mat.set_meta("width_key", "map3d_%s_width_px" % key)
	return mat


## Every bridge in `list` as ONE mesh (a surface per deck width), its meta
## "bridges" the list; no surface when there are none.
static func bridge_mesh(p_ctx: Map3DContext, list: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.set_meta("bridges", list)
	var rules := bridge_rules_of(p_ctx.repo)
	var tile := p_ctx.repo.bal("map3d_bridge_tile_m")
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
	return mesh


## The bridges' stone: medieval_blocks_03, lit and casting shadows like the ground.
func bridge_material() -> StandardMaterial3D:
	# The .tres: double-sided, roughness, the preview textures, anisotropic
	# filtering. Its fade is set here with its distances: the fade mode alone,
	# at Godot's default distances, would blank the editor's preview sphere.
	var mat := (BRIDGE_MAT as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = MapTerrain.palette_color(ctx.repo, "map3d_bridge", Color("#8A7F70"))
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
		mat.normal_texture = pair[1]
	return mat


## `mesh` under Viewport/Bridges in the stone (as its override: a baked mesh
## is shared), replacing any before; cleared when it has no surface.
func _place_bridges(mesh: ArrayMesh) -> void:
	_bridges = mesh.get_meta("bridges", []) if mesh != null else []
	# The authored scene's Viewport/Bridges is filled in place (its mesh null
	# when there are none); a bare viewport gets a node made for it.
	var mi := viewport.get_node_or_null("Bridges") as MeshInstance3D if viewport != null else null
	if mi != null:
		mi.mesh = null
		# The scene's own shared .tres must not stay on this view's node: it is
		# one resource for every view, so nothing may edit it (the stone below
		# is always a duplicate).
		mi.material_override = null
	if mesh == null or mesh.get_surface_count() == 0 or viewport == null:
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Bridges"
		viewport.add_child(mi)
	mi.mesh = mesh
	mi.material_override = bridge_material()
