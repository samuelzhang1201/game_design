@tool
class_name Map3DLayerSea
extends MeshInstance3D
## The 3D map's sea as its own layer (spec 2026-09-20 §1, node Viewport/Sea):
## the scene's OWN flat plane (Task 14: the build no longer makes one) dressed
## at runtime in the banded water, so the palette and bands stay data
## (terrain_palette / balance), not a rebuild. The plane is the pack's size
## times map3d_sea_plane_span, centred on the world origin at the build's
## sea_y — its edge must sit past the far camera's horizon (the old build's
## span * 12). has_water() is false until a world is built.

## The sea's look (shader, ripples, render priority); every number is bound below.
const SEA_MAT := preload("res://scenes/map3d/materials/water_sea.tres")

## Editor preview (Task 22): the banded water over the pack's own plane.
@export var preview := false: set = set_preview

var ctx: Map3DContext
var _mat: ShaderMaterial


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


## The sea as the game dresses it, from `p_ctx` alone — built into an UNOWNED
## twin of this node, never onto the authored one (a mesh or a material set
## here would be saved into the scene). A pack with no 3D build gets the
## placeholder in the same water.
func preview_build(p_ctx: Map3DContext) -> void:
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		ctx = p_ctx
		Map3DPreview.show_placeholder(self, SEA_MAT)
		return
	(Map3DPreview.proxy(self, get_script(), "SeaPreview") as Map3DLayerSea).build(p_ctx)


func build(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	var p: Array = ctx.meta["pack_px"]
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(p[0]), float(p[1])) * float(ctx.meta["m_per_px"]) \
		* ctx.repo.bal("map3d_sea_plane_span")
	mesh = plane
	position = Vector3(0.0, float(ctx.meta.get("sea_y", 0.0)), 0.0)
	_mat = (SEA_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	_mat.render_priority = Map3DPriority.SEA
	var tex_path := ctx.repo.sea_texture_path
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_mat.set_shader_parameter("sea_distance", load(tex_path))
	else:
		Map3DWorldLoader.warn_once("sea:" + tex_path,
			"Map3DView: the pack's sea_texture (%s) is missing — the sea has no bands" % tex_path)
	var o: Array = ctx.meta["pack_origin"]
	_mat.set_shader_parameter("pack_origin", Vector2(float(o[0]), float(o[1])))
	_mat.set_shader_parameter("pack_px", Vector2(float(p[0]), float(p[1])))
	_mat.set_shader_parameter("m_per_px", float(ctx.meta["m_per_px"]))
	# The palette hex goes in RAW (final review, owner 2026-09-18): under GL
	# Compatibility a Color uniform set from GDScript passes straight through
	# to the output — measured 0.5 -> 128 under a Linear tonemap, with or
	# without source_color — so there is no double gamma to undo. What moves
	# a flat unshaded/EMISSION colour is the environment's FILMIC tonemap,
	# which lifts it (0.5 -> 162); map3d_sea_emission_gamma (> 1) is fitted
	# to that tonemap by sampling the rendered bands against these hexes.
	for key: String in ["sea_near", "sea_nearer", "sea_far", "sea_deep"]:
		_mat.set_shader_parameter(key, MapTerrain.palette_color(ctx.repo, key, MapTerrain.FALLBACK))
	_mat.set_shader_parameter("sky",
		MapTerrain.palette_color(ctx.repo, "map3d_sky", MapTerrain.FALLBACK))
	_mat.set_shader_parameter("band_near", ctx.repo.bal("map_sea_band_near_px"))
	_mat.set_shader_parameter("band_nearer", ctx.repo.bal("map_sea_band_nearer_px"))
	_mat.set_shader_parameter("band_far", ctx.repo.bal("map_sea_band_far_px"))
	_mat.set_shader_parameter("soft", ctx.repo.bal("map_sea_band_soft_px"))
	_mat.set_shader_parameter("shore_fade_px", ctx.repo.bal("map3d_sea_shore_fade_px"))
	_mat.set_shader_parameter("ripples", ctx.water_normals())
	_mat.set_shader_parameter("ripple_m", ctx.repo.bal("map3d_sea_ripple_m"))
	_mat.set_shader_parameter("drift_m_s", ctx.repo.bal("map3d_sea_drift_m_s"))
	_mat.set_shader_parameter("emission_share", ctx.repo.bal("map3d_sea_emission_share"))
	_mat.set_shader_parameter("emission_gamma", ctx.repo.bal("map3d_sea_emission_gamma"))
	_mat.set_shader_parameter("roughness", ctx.repo.bal("map3d_sea_roughness"))
	_mat.set_shader_parameter("specular", ctx.repo.bal("map3d_sea_specular"))
	_mat.set_shader_parameter("fresnel_sky_mix", ctx.repo.bal("map3d_sea_fresnel_sky_mix"))
	_mat.set_shader_parameter("horizon_fade_start_px", ctx.repo.bal("map3d_sea_horizon_fade_start_px"))
	_mat.set_shader_parameter("horizon_fade_end_px", ctx.repo.bal("map3d_sea_horizon_fade_end_px"))
	for key: String in ["ripple_near_m", "ripple_lod_near_m", "ripple_lod_far_m",
			"ripple_emission_gain", "emission_share_near", "shore_warp_px", "shore_warp_m"]:
		_mat.set_shader_parameter(key, ctx.repo.bal("map3d_sea_" + key))
	for key: String in ["nat_shallow", "nat_mid", "nat_deep", "foam"]:
		_mat.set_shader_parameter(key,
			MapTerrain.palette_color(ctx.repo, "map3d_sea_" + key, MapTerrain.FALLBACK))
	for key: String in ["nat_shallow_px", "nat_mid_px", "nat_deep_px", "nat_warp_px", "nat_emission_share",
			"nat_roughness", "nat_specular", "nat_fresnel_sky_mix", "foam_px", "foam_strength"]:
		_mat.set_shader_parameter(key, ctx.repo.bal("map3d_sea_" + key))
	material_override = _mat
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)
	_on_camera_moved()


## Natural water near, the bands far (owner 2026-09-24): the share of natural
## water at the camera's distance, 1 at or under map3d_sea_natural_full_m, 0
## at or past map3d_sea_bands_full_m.
static func natural_share(distance_m: float, full_m: float, bands_m: float) -> float:
	if bands_m <= full_m:
		return 1.0 if distance_m <= full_m else 0.0
	return 1.0 - smoothstep(full_m, bands_m, distance_m)


func _on_camera_moved() -> void:
	if _mat == null or ctx == null:
		return
	_mat.set_shader_parameter("natural", natural_share(ctx.distance,
		ctx.repo.bal("map3d_sea_natural_full_m"), ctx.repo.bal("map3d_sea_bands_full_m")))


func material() -> ShaderMaterial:
	return _mat


func has_water() -> bool:
	return mesh != null
