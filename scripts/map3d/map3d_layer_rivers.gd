@tool
class_name Map3DLayerRivers
extends MeshInstance3D
## The 3D map's rivers as their own layer (spec 2026-09-20 §1, node
## Viewport/Rivers): rivers.json beside the built scene (tools/map3d), drawn
## as one ribbon mesh in water_river.gdshader; none without the file. Split
## at each lake exit (Map3DRivers.parse) so a jump in the water line never
## draws as a vertical wall, then clear_terrain lifts any point whose flat,
## sparsely-sampled cross-section would otherwise dip below the real, denser
## terrain on a steep stretch (fix round 3) — the carved riverbed's own
## ground would show through instead of the water.

## The rivers' look (shader, ripples, render priority); every number is bound below.
const RIVER_MAT := preload("res://scenes/map3d/materials/water_river.tres")

## Editor preview (Task 22): the build's rivers.json, drawn as the game draws it.
@export var preview := false: set = set_preview

var ctx: Map3DContext
var _mat: ShaderMaterial
## The river courses as drawn (Map3DRivers.parse, cleared of the terrain):
## the bridges look for them.
var _courses: Array = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lines are thin and long: never culled by a box the relief lift pushes them out of.
	extra_cull_margin = 16384.0


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


## The rivers as the game draws them, from `p_ctx` and the pack's own build —
## into an UNOWNED twin of this node, never onto the authored one (a mesh set
## here would be saved into the scene). A pack with no 3D build gets the
## placeholder in the same water.
func preview_build(p_ctx: Map3DContext) -> void:
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		ctx = p_ctx
		Map3DPreview.show_placeholder(self, RIVER_MAT)
		return
	var twin := Map3DPreview.proxy(self, get_script(), "RiversPreview") as Map3DLayerRivers
	twin.build(p_ctx, p_ctx.repo.map3d_dir().path_join("world.tscn"))
	twin.apply_scale()


## The rivers' ribbon arrays and their drawn courses for `scene_path`'s
## rivers.json ({arrays: [] , courses: []} without the file): what build()
## draws and what tools/map3d/bake_layers.gd saves (Task 20).
static func arrays_for(ctx: Map3DContext, scene_dir: String) -> Dictionary:
	var path := scene_dir.path_join("rivers.json")
	if not FileAccess.file_exists(path):
		Map3DWorldLoader.warn_once("rivers:" + path,
			"Map3DView: %s is missing — the 3D map draws no rivers (rebuild: tools/map3d/build_pack.sh)" % path)
		return {"arrays": [], "courses": []}
	var courses := Map3DRivers.parse(FileAccess.get_file_as_string(path),
		ctx.repo.bal("map3d_river_split_rise_m"))
	courses = Map3DRivers.clear_terrain(courses, ctx.height_at, ctx.repo.bal("map3d_river_terrain_clear_m"))
	var arrays := Map3DRivers.ribbon_arrays(courses, ctx.repo.bal("map3d_river_end_fade_m"),
		ctx.river_step())
	return {"arrays": arrays, "courses": courses}


func build(p_ctx: Map3DContext, scene_path: String) -> void:
	ctx = p_ctx
	var got := arrays_for(ctx, scene_path.get_base_dir())
	_courses = got["courses"]
	var arrays: Array = got["arrays"]
	if arrays.is_empty():
		# No rivers: the scene's own shared .tres must not stay on this view
		# (it is one resource for every view — nothing may edit it).
		mesh = null
		_mat = null
		material_override = null
		return
	_make_material()
	mesh = Map3DLayerBake.mesh_of(arrays)
	material_override = _mat


## The build's baked rivers (Map3DLayerBake): drawn as they are, the
## loaded resource shared and never edited; no courses kept (the bridges
## were baked with them).
func build_baked(p_ctx: Map3DContext, baked: ArrayMesh) -> void:
	ctx = p_ctx
	_courses = []
	_make_material()
	mesh = baked if baked != null and baked.get_surface_count() > 0 else null
	material_override = _mat


func _make_material() -> void:
	_mat = (RIVER_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	_mat.render_priority = Map3DPriority.RIVERS
	# The palette hex goes in RAW, as the sea's does (see Map3DLayerSea.build).
	_mat.set_shader_parameter("water",
		MapTerrain.palette_color(ctx.repo, "river", MapTerrain.FALLBACK))
	_mat.set_shader_parameter("mouth_water",
		MapTerrain.palette_color(ctx.repo, "sea_near", MapTerrain.FALLBACK))
	_mat.set_shader_parameter("sky",
		MapTerrain.palette_color(ctx.repo, "map3d_sky", MapTerrain.FALLBACK))
	_mat.set_shader_parameter("ripples", ctx.water_normals())
	_mat.set_shader_parameter("ripple_m", ctx.repo.bal("map3d_river_ripple_m"))
	_mat.set_shader_parameter("flow_m_s", ctx.repo.bal("map3d_river_flow_m_s"))
	_mat.set_shader_parameter("opacity", ctx.repo.bal("map3d_river_opacity"))
	_mat.set_shader_parameter("edge_soft_floor", ctx.repo.bal("map3d_river_edge_soft_floor"))
	_mat.set_shader_parameter("emission_share", ctx.repo.bal("map3d_river_emission_share"))
	_mat.set_shader_parameter("emission_gamma", ctx.repo.bal("map3d_river_emission_gamma"))
	for key: String in ["fresnel_sky_mix", "fresnel_power", "roughness", "specular", "normal_depth",
			"ripple_emission_gain", "bank_wobble_m", "bank_wobble_amp"]:
		_mat.set_shader_parameter(key, ctx.repo.bal("map3d_river_" + key))
	# One LOD for both waters: the river's near detail comes and goes with the sea's.
	_mat.set_shader_parameter("lod_near_m", ctx.repo.bal("map3d_sea_ripple_lod_near_m"))
	_mat.set_shader_parameter("lod_far_m", ctx.repo.bal("map3d_sea_ripple_lod_far_m"))


## The lines' screen-px values in SubViewport px, and the metres per px per
## metre of distance (on load, resize, a tier change).
func apply_scale() -> void:
	if _mat == null:
		return
	var s := ctx.viewport_px_scale()
	var per_dist := ctx.px_per_dist()
	_mat.set_shader_parameter("px_per_dist", per_dist)
	_mat.set_shader_parameter("min_px", ctx.repo.bal("map3d_river_min_px") * s)


func material() -> ShaderMaterial:
	return _mat


func courses() -> Array:
	return _courses
