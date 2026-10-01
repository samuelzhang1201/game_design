class_name Map3DLayerTrails
extends Node3D
## MARCH TRAILS (owner 2026-10-01: 当军事单位路过的时候，希望可以和地形互动，比如
## 留下一段行走印记，后逐步消失; node Viewport/Trails): the ground a marching
## column trod, laid on the relief behind each piece and fading out over
## `map3d_trail_days` of GAME time — so a paused clock holds it, and a 4x
## clock wears it away four times as fast. Presentation only: nothing here is
## saved or read by the engine (a loaded game starts with clean ground). It
## follows the pieces where Map3DLayerUnits draws them (shown_positions): a
## piece that moved this frame is walking; a point every `map3d_trail_step_m`
## of its walk, a new stretch each time a column sets off again. A piece is a
## miniature of ONE world size at every zoom, so the trail's width is a number
## of world metres (`map3d_trail_half_width_m`), not read off the model. Takes everything from Map3DContext — never the Game autoload.

const MATERIAL := preload("res://scenes/map3d/materials/march_trail.tres")

var ctx: Map3DContext
var _units: Map3DLayerUnits
var _mat: ShaderMaterial
var _mesh: MeshInstance3D
## code -> Array of stretches, each {pts: PackedVector2Array, t: PackedFloat32Array, half_w: float}
var _trails: Dictionary = {}
var _last_xz: Dictionary = {}
var _last_moved: Dictionary = {}
var _last_now := -1.0
var _dirty := false


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	_units = get_node_or_null("../Units") as Map3DLayerUnits
	_mat = MATERIAL.duplicate() as ShaderMaterial
	_mat.render_priority = Map3DPriority.MARCH_TRAILS
	var repo := ctx.repo
	var c := MapTerrain.palette_color(repo, "map3d_march_trail", Color("#A89468"))
	c.a = repo.bal("map3d_trail_alpha")
	_mat.set_shader_parameter("colour", c)
	_mat.set_shader_parameter("life_days", repo.bal("map3d_trail_days"))
	_mat.set_shader_parameter("edge_soft", repo.bal("map3d_trail_edge_soft"))
	_mat.set_shader_parameter("print_m", repo.bal("map3d_trail_print_m"))
	_mat.set_shader_parameter("print_mix", repo.bal("map3d_trail_print_mix"))
	for key in ["lanes", "lane_fill", "lane_wander", "rag"]:
		_mat.set_shader_parameter(key, repo.bal("map3d_trail_" + key))
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.extra_cull_margin = 16384.0
		add_child(_mesh)  # no owner: never saved into the authored scene
	_mesh.material_override = _mat
	clear()


## Clean ground (a new game, a load).
func clear() -> void:
	_trails.clear()
	_last_xz.clear()
	_last_moved.clear()
	_dirty = true


## The stretches' points, {code: [PackedVector2Array, ...]} — a test seam.
func stretches() -> Dictionary:
	var out := {}
	for code: String in _trails:
		var lines: Array = []
		for s: Dictionary in _trails[code]:
			lines.append(s["pts"])
		out[code] = lines
	return out


## Per FRAME, after the pieces have stepped.
func step() -> void:
	if ctx == null or _units == null or _mat == null:
		return
	var repo := ctx.repo
	var on := repo.bal("map3d_trail_on") > 0.0
	visible = on
	var st := ctx.state()
	if not on or st == null:
		return
	var now := float(st.absolute_day()) + ctx.day_share()
	# time running back more than a day is a load; the day's turn itself can
	# read a frame early (the share resets before the day moves on)
	if now < _last_now - 1.0:
		clear()
	now = maxf(now, _last_now)
	_last_now = now
	var step_m := repo.bal("map3d_trail_step_m")
	var half_w := repo.bal("map3d_trail_half_width_m")
	var shown := _units.shown_positions()
	for code: String in shown:
		var xz: Vector2 = shown[code]
		var prev: Variant = _last_xz.get(code)
		_last_xz[code] = xz
		if prev == null or (prev as Vector2).distance_to(xz) < 0.01 or ctx.clock_speed() <= 0:
			continue
		if not _trails.has(code):
			_trails[code] = []
		var list: Array = _trails[code]
		# a column that stood still a while, or jumped (snapped to the
		# engine's spot), sets off on a new stretch
		var fresh := list.is_empty() or now - float(_last_moved.get(code, -1.0e9)) > 0.25
		if not fresh:
			var last: PackedVector2Array = (list.back() as Dictionary)["pts"]
			fresh = last[last.size() - 1].distance_to(xz) > step_m * 8.0
		_last_moved[code] = now
		if fresh:
			list.append({"pts": PackedVector2Array([xz]), "t": PackedFloat32Array([now]), "half_w": half_w})
			_dirty = true
			continue
		var s: Dictionary = list.back()
		var pts: PackedVector2Array = s["pts"]
		if pts[pts.size() - 1].distance_to(xz) >= step_m:
			pts.append(xz)
			var ts: PackedFloat32Array = s["t"]
			ts.append(now)  # packed arrays are values: write the copy back
			s["t"] = ts
			s["pts"] = pts
			_dirty = true
	_forget_older_than(now - repo.bal("map3d_trail_days"))
	if _dirty:
		_rebuild()
		_dirty = false
	_mat.set_shader_parameter("now_days", now)
	_mat.set_shader_parameter("px_per_dist", ctx.px_per_dist())
	_mat.set_shader_parameter("lift_px", repo.bal("map3d_line_lift_px") * ctx.viewport_px_scale())


## Drops the points worn away before `cut`, keeping the last worn one of a
## stretch that still has fresher ground so its tail fades rather than cuts.
func _forget_older_than(cut: float) -> void:
	for code: String in _trails.keys():
		var keep: Array = []
		for s: Dictionary in _trails[code]:
			var t: PackedFloat32Array = s["t"]
			var first := 0
			while first + 1 < t.size() and t[first + 1] < cut:
				first += 1
			if t[t.size() - 1] < cut:
				_dirty = true
				continue
			if first > 0:
				s["pts"] = (s["pts"] as PackedVector2Array).slice(first)
				s["t"] = t.slice(first)
				_dirty = true
			keep.append(s)
		if keep.is_empty():
			_trails.erase(code)
		else:
			_trails[code] = keep


func _rebuild() -> void:
	var lines: Array = []
	var stamps: Array = []
	for code: String in _trails:
		for s: Dictionary in _trails[code]:
			if (s["pts"] as PackedVector2Array).size() >= 2:
				lines.append(s["pts"])
				stamps.append(s)
	if lines.is_empty():
		_mesh.mesh = null
		return
	var arrays := Map3DBorders.ribbon_arrays(lines, ctx.height_at)
	# UV2: (the day each point was trodden, the formation's half width), two
	# vertices a point in ribbon_arrays' own order
	var uv2 := PackedVector2Array()
	for s: Dictionary in stamps:
		var t: PackedFloat32Array = s["t"]
		for i in t.size():
			uv2.append(Vector2(t[i], float(s["half_w"])))
			uv2.append(Vector2(t[i], float(s["half_w"])))
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.mesh = mesh
