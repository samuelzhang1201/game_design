@tool
class_name Map3DLayerLines
extends Node3D
## The ribbon host (spec 2026-09-20 §1): Roads, Trails, ManorEdges, Seams, the supply lines,
## KingdomBand, KingdomHalo, Kingdoms, Hover and Selection, each ONE
## MeshInstance3D named for its line, draped on the relief
## (Map3DBorders.ribbon_arrays) and kept a constant SCREEN width by its shader.
## An empty line leaves no node, so line_mesh() is null for it.

## The ribbons' look (shader, render priority 0 until a style binds its own).
const BORDER_MAT := preload("res://scenes/map3d/materials/border_line.tres")
## Each line's LOOK (owner 2026-10-02: edited in the inspector): its colours,
## its widths, dash and gap in design px, its lift, its soft edge, and the
## band's one-sided fade — border_line.gdshader in a .tres per kind.
const KINGDOM_BAND := preload("res://scenes/map3d/materials/lines/kingdom_band.tres")
const KINGDOM_HALO := preload("res://scenes/map3d/materials/lines/kingdom_halo.tres")
const KINGDOM_INK := preload("res://scenes/map3d/materials/lines/kingdom_ink.tres")
const SEAM := preload("res://scenes/map3d/materials/lines/seam.tres")
const HOVER := preload("res://scenes/map3d/materials/lines/hover.tres")
const SELECTION_MANOR := preload("res://scenes/map3d/materials/lines/selection_manor.tres")
const SELECTION_PROVINCE := preload("res://scenes/map3d/materials/lines/selection_province.tres")
const MANOR_EDGE := preload("res://scenes/map3d/materials/lines/manor_edge.tres")
## The supply lines (Map3DSupplyLines): a flowing line, the pick's lit and
## greyed town rings, the chosen town's road.
const SUPPLY_LINE := preload("res://scenes/map3d/materials/lines/supply_line.tres")
const SUPPLY_PICK := preload("res://scenes/map3d/materials/lines/supply_pick.tres")
const SUPPLY_PICK_OFF := preload("res://scenes/map3d/materials/lines/supply_pick_off.tres")
const SUPPLY_PREVIEW := preload("res://scenes/map3d/materials/lines/supply_preview.tres")
## The px values a line's look gives in DESIGN px, scaled to the SubViewport.
const PX_PARAMS := ["width_px", "dash_px", "gap_px", "lift_px"]

## Editor preview (Task 22): the borders, the seams and the pack's roads,
## drawn from the data alone. Nothing it makes is ever saved (no owner).
@export var preview := false: set = set_preview

var ctx: Map3DContext


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


## Build the layer as the game does, from `p_ctx` alone — no autoload, no
## view: the kingdom band, its halo and ink, the province seams and the
## pack's roads and trails. A pack with no 3D build gets the placeholder.
func preview_build(p_ctx: Map3DContext) -> void:
	bind(p_ctx)
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		Map3DPreview.show_placeholder(self, BORDER_MAT)
		return
	Map3DPreview.clear_generated(self)
	var borders := Map3DLayerBorders.new()
	borders.bind(p_ctx, self)
	borders.refresh()
	# The bridges hang off this layer's SIBLING (Viewport/Bridges), so a lines
	# preview draws the roads themselves and no bridges.
	var roads := Map3DLayerRoads.new()
	roads.bind(p_ctx, self, null)
	roads.build([])
	apply_scale()


## One ribbon layer wearing `look` (one of the line .tres above), drawn in
## `priority`'s row, a colour per line from `colours` when the look takes
## vertex colours (the realm band); replacing any before.
func set_lines(line_name: String, lines: Array, look: ShaderMaterial, priority: int,
		colours: Array = []) -> void:
	var one_sided := float(look.get_shader_parameter("one_sided")) > 0.5
	var arrays := Map3DBorders.ribbon_arrays(lines, ctx.height_at, [], one_sided, colours)
	var mat := look.duplicate() as ShaderMaterial
	mat.render_priority = priority
	var base := {}
	for k: String in PX_PARAMS:
		base[k] = float(look.get_shader_parameter(k))
	mat.set_meta("base_px", base)
	put_mesh(line_name, arrays, mat)


## Any ribbon mesh (the roads bring their own material), replacing any
## before; nothing when `arrays` is empty.
func put_mesh(line_name: String, arrays: Array, mat: ShaderMaterial) -> void:
	var old := get_node_or_null(line_name)
	if old != null:
		remove_child(old)
		old.queue_free()
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	_add_line(line_name, mesh, null)
	_scale_material(mat)


## One line's node: `mesh`, and `override` over its own material when given.
func _add_line(line_name: String, mesh: ArrayMesh, override: ShaderMaterial) -> void:
	var mi := MeshInstance3D.new()
	mi.name = line_name
	mi.mesh = mesh
	mi.material_override = override
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lines are thin and long: never culled by a box the relief lift pushes them out of.
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	if override != null:
		_scale_material(override)


## A baked ribbon mesh (Map3DLayerBake) with `mat` as its override: the
## loaded resource is shared, so it is never edited. Nothing without a surface.
func put_baked(line_name: String, mesh: ArrayMesh, mat: ShaderMaterial) -> void:
	var old := get_node_or_null(line_name)
	if old != null:
		remove_child(old)
		old.queue_free()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	_add_line(line_name, mesh, mat)


func line_mesh(line_name: String) -> ArrayMesh:
	var mi := get_node_or_null(line_name) as MeshInstance3D
	return mi.mesh as ArrayMesh if mi != null else null


## Every line's screen-px values in SubViewport px (on load, resize, a tier change).
func apply_scale() -> void:
	for mi: MeshInstance3D in get_children():
		# a baked mesh (Task 20) carries its material as an override
		var mat := (mi.material_override if mi.material_override != null
			else mi.mesh.surface_get_material(0)) as ShaderMaterial
		if mat != null:
			_scale_material(mat)


func _scale_material(mat: ShaderMaterial) -> void:
	if ctx == null:
		return
	var s := ctx.viewport_px_scale()
	mat.set_shader_parameter("px_per_dist", ctx.px_per_dist())
	# a line's look gives its px in design px (set_lines, the roads' own)
	var base: Dictionary = mat.get_meta("base_px", {})
	for k: String in base:
		mat.set_shader_parameter(k, float(base[k]) * s)
