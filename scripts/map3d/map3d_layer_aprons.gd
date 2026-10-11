@tool
class_name Map3DLayerAprons
extends Node3D
## The aprons at the houses' feet (owner 2026-10-12: 房屋模型现在硬生生放在地面上，
## 我希望房屋脚下加上一点点小小的过渡，乡村可以是泥土，城市可以是砖头地面; R7):
## packed dirt round a village's houses, brick paving round a fort's, town's,
## city's or capital's. Node World/Aprons, fed by its sibling Houses layer
## (Map3DLayerHouses.aprons): every settlement Houses shows, with the same
## houses and mesh boxes, so an apron never stands without its house.
##
## Each settlement is ONE mesh of its kind, a grid per house draped on the
## ground (Map3DHouseApron.drape — the geometry is map3d_aprons.csv's), built
## the first time it is shown and kept, like the roads' and the houses'
## chunks; a settlement not shown is hidden, and past map3d_lod_houses_m none
## is drawn. The LOOK is the two exported materials (scenes/map3d/materials/
## apron_dirt.tres, apron_brick.tres on house_apron.gdshader): the layer draws
## a copy of each with only its lift (CSV px scaled to the SubViewport), the
## camera's px_per_dist, the render priority (Map3DPriority.APRONS, under the
## roads) and the houses' weather set; a kind with no material is not drawn
## (one warning). Never reaches for the Game autoload.

## The village apron's look (a kind's material is the export `<kind>_material`).
@export var dirt_material: Material
## The town apron's look.
@export var brick_material: Material

var ctx: Map3DContext
## The Houses layer whose weather the aprons wear (its surface_mats / weather).
var houses_layer: Map3DLayerHouses
var _mats: Dictionary = {}    # kind -> the drawn copy, null when the kind has no material
var _nodes: Dictionary = {}   # burg code -> MeshInstance3D, null when it has no apron
var _shown: Dictionary = {}   # burg code -> true, the last show()
var _of: Variant = null       # the houses dictionary the meshes were built from
var _lod_shown := true


func bind(p_ctx: Map3DContext, p_houses: Map3DLayerHouses = null) -> void:
	ctx = p_ctx
	houses_layer = p_houses
	if not ctx.camera_moved.is_connected(_on_camera_moved):
		ctx.camera_moved.connect(_on_camera_moved)


func _on_camera_moved() -> void:
	_lod_shown = Map3DGeometry.lod_shown(_lod_shown, ctx.distance, ctx.repo.bal("map3d_lod_houses_m"),
		ctx.repo.bal("map3d_lod_margin_m"))
	for kind: String in _mats:
		_scale(kind)
	_apply()


## Show the aprons of `codes` (the settlements Houses shows), from `houses`
## (burg code -> its rows) and `boxes` (house type -> its mesh's AABB).
func show_burgs(codes: Array, houses: Dictionary, boxes: Dictionary) -> void:
	if ctx == null:
		return
	if not is_same(_of, houses):
		clear()
		_of = houses
	_shown = {}
	for code: String in codes:
		if not _nodes.has(code):
			_nodes[code] = _build(code, houses.get(code, []), boxes)
		_shown[code] = true
	_apply()


## Forget every mesh and material copy (a preview switched off, another houses set).
func clear() -> void:
	Map3DPreview.clear_generated(self)
	if houses_layer != null:
		for mat: Variant in _mats.values():
			houses_layer.surface_mats.erase(mat)
	_nodes.clear()
	_shown.clear()
	_mats.clear()
	_of = null


func _apply() -> void:
	for code: String in _nodes:
		var mi := _nodes[code] as MeshInstance3D
		if mi != null:
			mi.visible = _lod_shown and _shown.has(code)


func _build(code: String, rows: Array, boxes: Dictionary) -> MeshInstance3D:
	var group := String(ctx.repo.burgs.get(code, {}).get("group", "village"))
	var kind := Map3DHouseApron.kind_of(group, ctx.repo)
	var mat := material_of(kind)
	if mat == null:
		return null
	var row: Dictionary = ctx.repo.map3d_aprons[kind]
	var a := Map3DHouseApron.new_arrays()
	for h: Dictionary in rows:
		var type := String(h["type"])
		if Map3DHouseApron.wears(type, ctx.repo) and boxes.has(type):
			Map3DHouseApron.drape(a, Map3DHouseApron.corners(h, boxes[type], float(row["margin_m"])),
				int(row["grid_n"]), ctx.height_at)
	if (a["v"] as PackedVector3Array).is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, Map3DHouseApron.arrays_of(a))
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "apron_" + code
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("kind", kind)
	mi.set_meta("verts", (a["v"] as PackedVector3Array).size())
	add_child(mi)  # no owner: never saved
	return mi


## The material `kind` is drawn in: a copy of the export `<kind>_material`
## with the code's few values set; null (warned once) when it has none.
func material_of(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var key := kind + "_material"
	var look: Material = get(key) if key in self else null
	if look == null or not ctx.repo.map3d_aprons.has(kind):
		Map3DWorldLoader.warn_once("aprons:" + kind,
			"map3d aprons: no %s on the Aprons node — the %s aprons are not drawn" % [key, kind])
		_mats[kind] = null
		return null
	var mat := look.duplicate() as Material
	mat.render_priority = Map3DPriority.APRONS
	_mats[kind] = mat
	_scale(kind)
	if mat is ShaderMaterial and houses_layer != null:
		for k: String in houses_layer.weather:
			(mat as ShaderMaterial).set_shader_parameter(k, houses_layer.weather[k])
		houses_layer.surface_mats.append(mat)  # Map3DLayerWeather lays each turn on it
	return mat


## `kind`'s lift in SubViewport px and the camera's px_per_dist.
func _scale(kind: String) -> void:
	var mat := _mats.get(kind) as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("lift_px", float(ctx.repo.map3d_aprons[kind]["lift_px"]) * ctx.viewport_px_scale())
	mat.set_shader_parameter("px_per_dist", ctx.px_per_dist())


## Test seam: the vertices drawn per kind (the shown, unhidden settlements).
func vertex_counts() -> Dictionary:
	var out: Dictionary = {}
	for code: String in _nodes:
		var mi := _nodes[code] as MeshInstance3D
		if mi != null and mi.visible:
			var kind := String(mi.get_meta("kind"))
			out[kind] = int(out.get(kind, 0)) + int(mi.get_meta("verts"))
	return out


## Test seam: the shown settlement `code`'s apron node, null when none.
func node_of(code: String) -> MeshInstance3D:
	return _nodes.get(code) as MeshInstance3D
