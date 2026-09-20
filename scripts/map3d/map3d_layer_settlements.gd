@tool
class_name Map3DLayerSettlements
extends Node3D
## Settlement markers as their own layer (spec 2026-09-20 §1, node
## Viewport/Markers): one MultiMesh of billboard rings per settlement group,
## each over the ground under its burg, plus a hidden gold ring for the
## current selection (was Map3DView._place_markers / _ring_material /
## _show_selected_ring / _sorted_burgs).

## The tier rings' and the selection ring's looks (one shader); each ring's
## colour, sizes, fade and render priority are bound per group below.
const RING_MAT := preload("res://scenes/map3d/materials/settlement_ring.tres")
const SELECTION_RING_MAT := preload("res://scenes/map3d/materials/selection_ring.tres")
## The selection ring never thins by distance (fix round 1, owner 2026-09-18):
## whatever the player clicked stays marked regardless of zoom.
const SELECTED_RING_ALWAYS_M := 1000000.0

## Editor preview (Task 22): every marked burg's ring, from the pack alone.
@export var preview := false: set = set_preview

var ctx: Map3DContext
var _ring_mats: Array[ShaderMaterial] = []
var _selected_ring: MultiMeshInstance3D


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		_ring_mats.clear()
		_selected_ring = null
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


## The markers as the game builds them, from `p_ctx` alone; a pack with no
## 3D build gets the placeholder.
func preview_build(p_ctx: Map3DContext) -> void:
	bind(p_ctx)
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		Map3DPreview.show_placeholder(self, RING_MAT)
		return
	build()


## One MultiMesh of billboard rings per settlement group, each over the
## ground under its burg, plus a hidden gold ring for the current selection.
## Codes are sorted so the placement is the same every run. Render priority
## rises with tier (village lowest, capital highest — by drawn_px, the
## table's own measure of the marker's ON-SCREEN size) so a bigger
## settlement's mark never gets buried under a smaller neighbour's (fix
## round 1, owner 2026-09-18); the selection ring sits above every tier.
## Replaces any markers before.
func build() -> void:
	_ring_mats.clear()
	# Only what a build (or a preview) made: an AUTHORED child is never
	# touched, so its deletion could never be saved (Task 22 review).
	Map3DPreview.clear_generated(self)
	_selected_ring = null
	var by_group: Dictionary = {}
	for code: String in ctx.marked_burgs():
		var burg: Dictionary = ctx.repo.burgs[code]
		var group := String(burg.get("group", ""))
		if not by_group.has(group):
			by_group[group] = []
		(by_group[group] as Array).append(ctx.burg_ground(code))
	var groups: Array = by_group.keys()
	groups.sort()
	var by_size: Array = groups.duplicate()
	by_size.sort_custom(func(a: String, b: String) -> bool:
		var ra := drawn_px(ctx.repo.map3d_settlements[a])
		var rb := drawn_px(ctx.repo.map3d_settlements[b])
		return ra < rb if ra != rb else a < b)
	var min_view_m := ctx.repo.bal("map3d_dot_min_view_m")
	for group: String in groups:
		var spec: Dictionary = ctx.repo.map3d_settlements[group]
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		mesh.material = _ring_material(Color(String(spec["color"])),
			float(spec["ring_px"]), float(spec["line_px"]), float(spec["max_view_m"]),
			Map3DPriority.RING_BASE + by_size.find(group), float(spec.get("dot_px", 0.0)),
			RING_MAT, float(spec.get("inner_px", 0.0)), min_view_m)
		var pts: Array = by_group[group]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = group.capitalize()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The vertex shader grows geometry far past the mesh's own 1x1 AABB
		# (Map3DBorders' lines use the same margin, for the same reason).
		mmi.extra_cull_margin = 16384.0
		add_child(mmi)
	var sel := QuadMesh.new()
	sel.size = Vector2.ONE
	sel.material = _ring_material(MapPalette.named(ctx.repo, "map3d_selection"), 0.0, 0.0,
		SELECTED_RING_ALWAYS_M, Map3DPriority.RING_BASE + groups.size(), 0.0, SELECTION_RING_MAT)
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = sel
	smm.instance_count = 1
	_selected_ring = MultiMeshInstance3D.new()
	_selected_ring.name = "Selected"
	_selected_ring.multimesh = smm
	_selected_ring.visible = false
	_selected_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selected_ring.extra_cull_margin = 16384.0
	add_child(_selected_ring)
	apply_scale()


## Show the gold ring on a burg (or hide it with ""). It keeps the base
## stroke width at a larger diameter (fix round 1, owner 2026-09-18: the old
## 1.5x line width smeared it into a fat band over the tier ring instead of
## reading as a second crisp ring).
func show_selected(code: String) -> void:
	if _selected_ring == null:
		return
	_selected_ring.visible = code != ""
	if code == "":
		return
	var burg: Dictionary = ctx.repo.burgs[code]
	var spec: Dictionary = ctx.repo.map3d_settlements[String(burg.get("group", ""))]
	_selected_ring.multimesh.set_instance_transform(0,
		Transform3D(Basis.IDENTITY, ctx.burg_ground(code)))
	var mat := _selected_ring.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var k := ctx.repo.bal("map3d_selected_ring_scale")
	# A gold ring round the dot (or round the capital's own ring).
	mat.set_meta("ring_px", maxf(float(spec["ring_px"]), float(spec.get("dot_px", 0.0)) * 2.0) * k)
	mat.set_meta("line_px", maxf(float(spec["line_px"]), 2.0))
	apply_scale()


## Whether the clicked settlement's gold ring is currently shown.
func selected_visible() -> bool:
	return _selected_ring != null and _selected_ring.visible


## Settlement markers per group: {group: count}.
func counts() -> Dictionary:
	var out: Dictionary = {}
	for mmi: MultiMeshInstance3D in get_children():
		if mmi.name == "Selected":
			continue
		out[mmi.name.to_lower()] = mmi.multimesh.instance_count
	return out


## The dot's near threshold, world metres (owner 2026-09-21 ruling): NOT the
## absolute balance.csv value it replaces (map3d_dot_min_view_m, which once
## sat past a ceiling the camera could never reach — see
## task-dot-threshold-report.md), but the farthest map3d_dot_min_view_share
## of the RIGHT-NOW reachable range, counted down from the same ceiling
## Map3DCameraRig.max_distance computes toward map3d_zoom_min_m. It depends
## on the view's own height (the ceiling does, through the scale bar's own
## cap), so it must be recomputed whenever the view resizes, not just once
## at build — see apply_scale.
static func dot_min_view_m(repo: DataRepository, meta: Dictionary, view_height_px: float) -> float:
	var ceiling := Map3DGeometry.zoom_ceiling_m(repo.bal("map3d_zoom_max_m"),
		repo.bal("map3d_zoom_max_scale"), Map3DGeometry.map_units_per_metre(repo.map_info, meta),
		repo.bal("map_scale_bar_max_px"), repo.bal("map3d_fov_deg"), view_height_px)
	return Map3DGeometry.dot_min_view_m(ceiling, repo.bal("map3d_zoom_min_m"),
		repo.bal("map3d_dot_min_view_share"))


## A ring material; its sizes are design px, turned into window px with the
## other layers' by apply_scale (base values kept as meta). max_view_m and
## min_view_m are world metres, never rescaled. The keyline is a fixed data
## value (fix round 1: a pale ring was nearly invisible on bright grass at
## the old 0.55 default). min_view_m is 0 (never hidden) for the selection
## ring, which must keep showing at any zoom once something is clicked;
## `dynamic_min` (false for it) marks a tier ring's material so apply_scale
## knows which ones to keep re-pointed at the live threshold.
func _ring_material(colour: Color, ring_px: float, line_px: float, max_view_m: float,
		priority: int, dot_px := 0.0, look: ShaderMaterial = RING_MAT, inner_px := 0.0,
		min_view_m := 0.0, dynamic_min := false) -> ShaderMaterial:
	var mat := look.duplicate() as ShaderMaterial
	mat.render_priority = priority
	mat.set_shader_parameter("colour", colour)
	mat.set_shader_parameter("max_view_m", max_view_m)
	mat.set_shader_parameter("min_view_m", min_view_m)
	mat.set_shader_parameter("fade_start", ctx.repo.bal("map3d_ring_fade_start"))
	var keyline := Color(0.08, 0.08, 0.08, ctx.repo.bal("map3d_ring_keyline_alpha"))
	mat.set_shader_parameter("keyline", keyline)
	mat.set_meta("ring_px", ring_px)
	mat.set_meta("line_px", line_px)
	mat.set_meta("dot_px", dot_px)
	mat.set_meta("inner_px", inner_px)
	mat.set_meta("dynamic_min", dynamic_min)
	_ring_mats.append(mat)
	return mat


## The ring materials' screen-px values in WINDOW px, and the metres per px
## per metre of distance — on load, marker build, selection and resize.
## min_view_m is WORLD metres, never rescaled by `s`, but it is recomputed
## here too (not only in build()): it depends on ctx.view_size, which a
## resize changes (Map3DView._fit_viewport -> _update_line_scale ->
## apply_scale), so a shorter or taller panel keeps the same share of ITS
## OWN reachable range rather than a threshold sized for the view it loaded
## under. The selection ring (dynamic_min false) is left at its fixed 0.
func apply_scale() -> void:
	if ctx == null:
		return
	var s := ctx.viewport_px_scale()
	var per_dist := ctx.px_per_dist()
	var min_view_m := dot_min_view_m(ctx.repo, ctx.meta, ctx.view_size.y)
	for mat: ShaderMaterial in _ring_mats:
		mat.set_shader_parameter("px_per_dist", per_dist)
		mat.set_shader_parameter("lift_px", ctx.repo.bal("map3d_ring_lift_px") * s)
		mat.set_shader_parameter("ring_px", float(mat.get_meta("ring_px")) * s)
		mat.set_shader_parameter("line_px", float(mat.get_meta("line_px")) * s)
		mat.set_shader_parameter("dot_px", float(mat.get_meta("dot_px", 0.0)) * s)
		mat.set_shader_parameter("inner_px", float(mat.get_meta("inner_px", 0.0)) * s)
		if bool(mat.get_meta("dynamic_min", false)):
			mat.set_shader_parameter("min_view_m", min_view_m)


## The settlement's DRAWN marker's diameter, design px: max(ring_px, dot_px,
## inner_px). Fix round 1 (owner 2026-09-20): this is deliberately NOT the
## same thing as Map3DContext.pick_reach_px. The old `marker_px` this
## replaces fed BOTH the click reach and Map3DContext.settlement_rects' HUD
## keep-clear rect, and re-homing the click reach onto the settlement's
## ground footprint (pick_reach_px) while leaving settlement_rects calling
## the same function crowded landmark marks out of a huge area below
## map3d_dot_min_view_m — ground where the dot is hidden and nothing is
## drawn at all. drawn_px stays tied to what is actually ON SCREEN (the
## marker), so settlement_rects only reserves space around something a
## player can actually see; pick_reach_px alone reasons about the ground.
static func drawn_px(spec: Dictionary) -> float:
	return maxf(maxf(float(spec.get("ring_px", 0.0)), float(spec.get("dot_px", 0.0))),
		float(spec.get("inner_px", 0.0)))
