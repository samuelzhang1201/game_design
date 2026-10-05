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
	twin.build(p_ctx, p_ctx.repo.map3d_scene())
	twin.apply_scale()


## The rivers' ribbon arrays and their drawn courses for `scene_path`'s
## rivers.json ({arrays: [] , courses: []} without the file): what build()
## draws and what tools/map3d/bake_layers.gd saves (Task 20).
static func arrays_for(p_ctx: Map3DContext, scene_dir: String) -> Dictionary:
	var path := scene_dir.path_join("rivers.json")
	if not FileAccess.file_exists(path):
		Map3DWorldLoader.warn_once("rivers:" + path,
			"Map3DView: %s is missing — the 3D map draws no rivers (rebuild: tools/map3d/build_pack.sh)" % path)
		return {"arrays": [], "courses": []}
	var drawn := Map3DRivers.parse(FileAccess.get_file_as_string(path),
		p_ctx.repo.bal("map3d_river_split_rise_m"))
	drawn = Map3DRivers.clear_terrain(drawn, p_ctx.height_at, p_ctx.repo.bal("map3d_river_terrain_clear_m"))
	var arrays := Map3DRivers.ribbon_arrays(drawn, p_ctx.repo.bal("map3d_river_end_fade_m"),
		p_ctx.river_step(), p_ctx.repo.bal("map3d_river_mouth_extend_w"),
		float(p_ctx.meta.get("sea_y", 0.0)))
	return {"arrays": arrays, "courses": drawn}


func build(p_ctx: Map3DContext, scene_path: String) -> void:
	ctx = p_ctx
	var got := arrays_for(ctx, Map3DWorldLoader.data_dir(scene_path))
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


## The sea's uniforms the river's mouth turns into (water_sea.gdshaderinc),
## copied under the river's name for each: "sea_" + the sea's, or the
## sea's own when it already starts with "sea_".
const SEA_WATER := ["sea_near", "sea_nearer", "sea_far", "sea_deep", "band_near", "band_nearer",
	"band_far", "soft", "horizon_fade_start_px", "horizon_fade_end_px", "ripple_m", "ripple_near_m",
	"drift_m_s", "ripple_emission_gain", "emission_share", "emission_share_near", "emission_gamma",
	"roughness", "specular", "fresnel_sky_mix", "nat_shallow", "nat_mid", "nat_deep",
	"nat_shallow_px", "nat_mid_px", "nat_deep_px", "nat_warp_px", "nat_emission_share",
	"nat_roughness", "nat_specular", "nat_fresnel_sky_mix", "shore_fade_px", "shore_warp_px",
	"shore_warp_m"]


## The river's own look is water_river.tres (owner 2026-10-02: edited in
## the inspector); what it shares with the sea it READS from the sea's
## material, so a river and its mouth are one water at every zoom — the
## mouth's colour (the sea's nearest band), the sky it reflects, the natural
## shallows its mouth turns to, the ripples' level of detail, and (owner
## 2026-10-05) the sea's whole water, which the river becomes over its last
## stretch — and it turns natural with the sea's own share
## (Map3DContext.sea_natural).
func _make_material() -> void:
	_mat = (RIVER_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	_mat.render_priority = Map3DPriority.RIVERS
	var sea := Map3DLayerSea.SEA_MAT as ShaderMaterial
	for pair: Array in [["mouth_water", "sea_near"], ["sky", "sky"], ["nat_mouth", "nat_shallow"],
			["lod_near_m", "ripple_lod_near_m"], ["lod_far_m", "ripple_lod_far_m"]]:
		_mat.set_shader_parameter(String(pair[0]), sea.get_shader_parameter(String(pair[1])))
	for k: String in SEA_WATER:
		_mat.set_shader_parameter(river_name_of(k), sea.get_shader_parameter(k))
	var from_pack := Map3DLayerSea.pack_params(ctx)
	for k: String in from_pack:
		_mat.set_shader_parameter(river_name_of(k), from_pack[k])
	_mat.set_shader_parameter("ripples", ctx.water_normals())
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)
	_on_camera_moved()


## A sea uniform's name in the river's shader.
static func river_name_of(sea_uniform: String) -> String:
	return sea_uniform if sea_uniform.begins_with("sea_") else "sea_" + sea_uniform


func _on_camera_moved() -> void:
	if _mat == null or ctx == null:
		return
	_mat.set_shader_parameter("natural", ctx.sea_natural)


## The lines' screen-px values in SubViewport px, and the metres per px per
## metre of distance (on load, resize, a tier change).
func apply_scale() -> void:
	if _mat == null:
		return
	var s := ctx.viewport_px_scale()
	var per_dist := ctx.px_per_dist()
	_mat.set_shader_parameter("px_per_dist", per_dist)
	_mat.set_shader_parameter("min_px", float((RIVER_MAT as ShaderMaterial).get_shader_parameter("min_px")) * s)


func material() -> ShaderMaterial:
	return _mat


func courses() -> Array:
	return _courses
