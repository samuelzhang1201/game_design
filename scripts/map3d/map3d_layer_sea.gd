@tool
class_name Map3DLayerSea
extends MeshInstance3D
## The 3D map's sea as its own layer (spec 2026-09-20 §1, node Sea of
## scenes/map3d/map3d_world.tscn): the scene's OWN flat plane (Task 14: the
## build no longer makes one) in the banded water. The water's LOOK is
## scenes/map3d/materials/water_sea.tres (owner 2026-10-02: edited in the
## inspector — the four bands and their widths, the natural water, the
## ripples, the glint, the foam); the layer sets only what comes from the
## pack (its sea distance, origin, size and scale) and how natural the water
## reads at the camera's distance. The plane is the pack's size times
## `plane_span`, centred on the world origin at the build's sea_y — its edge
## must sit past the far camera's horizon. has_water() is false until a
## world is built. The rivers wear the same water (Map3DLayerRivers reads
## this material), so a river and its mouth are one water.

## The sea's look (shader, colours, bands, ripples, render priority).
const SEA_MAT := preload("res://scenes/map3d/materials/water_sea.tres")

## Editor preview (Task 22): the banded water over the pack's own plane.
@export var preview := false: set = set_preview
## The plane's side in packs: past the far camera's horizon.
@export var plane_span := 12.0
## Natural water up close, the bands far out (owner 2026-09-24): all natural
## at or under `natural_full_m` of camera distance, all bands at or past
## `bands_full_m`.
@export var natural_full_m := 40000.0
@export var bands_full_m := 100000.0

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
	plane.size = Vector2(float(p[0]), float(p[1])) * float(ctx.meta["m_per_px"]) * plane_span
	mesh = plane
	position = Vector3(0.0, float(ctx.meta.get("sea_y", 0.0)), 0.0)
	_mat = (SEA_MAT as ShaderMaterial).duplicate() as ShaderMaterial
	_mat.render_priority = Map3DPriority.SEA
	var tex_path := ctx.repo.sea_texture_path
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		Map3DWorldLoader.warn_once("sea:" + tex_path,
			"Map3DView: the pack's sea_texture (%s) is missing — the sea has no bands" % tex_path)
	var from_pack := pack_params(ctx)
	for k: String in from_pack:
		_mat.set_shader_parameter(k, from_pack[k])
	_mat.set_shader_parameter("ripples", ctx.water_normals())
	material_override = _mat
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)
	_on_camera_moved()


## What the sea's shader takes from the pack rather than water_sea.tres —
## its distance-from-shore map (absent: left unset), origin, size and scale —
## by uniform name. The rivers' mouths read the same (Map3DLayerRivers).
static func pack_params(p_ctx: Map3DContext) -> Dictionary:
	var p: Array = p_ctx.meta["pack_px"]
	var o: Array = p_ctx.meta["pack_origin"]
	var out := {"pack_origin": Vector2(float(o[0]), float(o[1])),
		"pack_px": Vector2(float(p[0]), float(p[1])), "m_per_px": float(p_ctx.meta["m_per_px"])}
	var tex_path := p_ctx.repo.sea_texture_path
	if tex_path != "" and ResourceLoader.exists(tex_path):
		out["sea_distance"] = load(tex_path)
	return out


## Natural water near, the bands far (owner 2026-09-24): the share of natural
## water at the camera's distance, 1 at or under map3d_sea_natural_full_m, 0
## at or past map3d_sea_bands_full_m.
static func natural_share(distance_m: float, full_m: float, bands_m: float) -> float:
	if bands_m <= full_m:
		return 1.0 if distance_m <= full_m else 0.0
	return 1.0 - smoothstep(full_m, bands_m, distance_m)


## The share of natural water at the camera's distance, kept on the context
## for the rivers, which turn with the sea.
func _on_camera_moved() -> void:
	if _mat == null or ctx == null:
		return
	ctx.sea_natural = natural_share(ctx.distance, natural_full_m, bands_full_m)
	_mat.set_shader_parameter("natural", ctx.sea_natural)


func material() -> ShaderMaterial:
	return _mat


func has_water() -> bool:
	return mesh != null
