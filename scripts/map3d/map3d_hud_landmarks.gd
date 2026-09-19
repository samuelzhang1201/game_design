class_name Map3DHudLandmarks
extends Map3DHudPiece
## HEIGHTS' high and low points on the 3D map's HUD (owner 2026-09-19, spec
## 2026-09-19-map3d-heights §4), over the kingdom names.

## marks()' cut and the pose it was cut for (see there).
var _cache: Array = []
var _key: Array = []


## The high and low points shown now, in design px, biggest first: those
## whose lod the camera's distance allows, before the camera and on screen,
## none overlapping a settlement dot, a regiment counter, the legend or a
## bigger mark.
## [] off HEIGHTS.
func marks() -> Array:
	if not bound() or not view.heat_on() or not view.is_loaded():
		return []
	# ~1.5 ms a call (the settlement dots dominate) and asked up to three
	# times a frame — HUD draw, hover, click — so it is cut once per camera
	# pose (Task 7 bench): the pose, the view's size, whether the counters
	# are shown and the date (regiments) key it.
	var st := ctx.state()
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(),
		view.military(), st.tick if st != null else 0, st.day if st != null else 0]
	if key == _key:
		return _cache
	_cache = _cut()
	_key = key
	return _cache


func _cut() -> Array:
	var repo := ctx.repo
	var camera := ctx.camera
	var max_lod := 2
	if ctx.distance >= repo.bal("map3d_landmark_lod_far_view_m"):
		max_lod = 0
	elif ctx.distance >= repo.bal("map3d_landmark_lod_mid_view_m"):
		max_lod = 1
	var s := ctx.viewport_px_scale()
	var px := repo.bal("map3d_landmark_px")
	var font := UiPalette.display_font()
	var font_px := int(repo.bal("map3d_landmark_font_px"))
	var frame := Rect2(Vector2.ZERO, ctx.view_size)
	var taken: Array = ctx.settlement_rects()
	var armies := sibling("Armies") as Map3DHudArmies
	if armies != null:
		for a: Dictionary in armies.markers():
			taken.append(a["rect"])
	var legend := sibling("HeatLegend") as Map3DHudHeatLegend
	if legend != null:
		taken.append(legend.rect())
	var out: Array = []
	for m: Dictionary in Elevation.landmarks(repo):
		if int(m["lod"]) > max_lod:
			continue
		var ground := ctx.pack_ground(m["pos"])
		if camera.is_position_behind(ground):
			continue
		var p := camera.unproject_position(ground) / s
		if not frame.has_point(p):
			continue
		var text := "%d m" % int(m["metres"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x \
			if font != null else 0.0
		var tall := maxf(px, float(font_px))
		var rect := Rect2(p - Vector2(px * 0.5, tall * 0.5), Vector2(px + 4.0 + tw, tall))
		# the whole mark and its height inside the view: a "15" cut by the edge
		# (or under the council tab) reads as a wrong number (Task 7 look pass)
		if not frame.encloses(rect):
			continue
		var clear := true
		for r: Rect2 in taken:
			if r.intersects(rect):
				clear = false
				break
		if not clear:
			continue
		taken.append(rect)
		out.append({"cell": int(m["cell"]), "kind": String(m["kind"]), "pos": p,
			"rect": rect, "text": text})
	return out


## A triangle up (high) or down (low) on a pale halo, the height beside it.
func _draw() -> void:
	if not bound():
		return
	var list := marks()
	if list.is_empty():
		return
	var repo := ctx.repo
	var px := repo.bal("map3d_landmark_px")
	var font := UiPalette.display_font()
	var font_px := int(repo.bal("map3d_landmark_font_px"))
	var halo := MapTerrain.palette_color(repo, "map3d_hud_halo", MapTerrain.FALLBACK)
	var text_ink := MapPalette.named(repo, "landmark_text")
	var high_ink := MapPalette.named(repo, "landmark_high")
	var low_ink := MapPalette.named(repo, "landmark_low")
	for mk: Dictionary in list:
		var p: Vector2 = mk["pos"]
		var h := px * 0.5
		var high := String(mk["kind"]) == "high"
		var tri := PackedVector2Array([p + Vector2(0, -h), p + Vector2(h, h), p + Vector2(-h, h)]) \
			if high else PackedVector2Array([p + Vector2(0, h), p + Vector2(-h, -h), p + Vector2(h, -h)])
		draw_colored_polygon(tri, high_ink if high else low_ink)
		draw_polyline(tri + PackedVector2Array([tri[0]]), halo, 1.5, true)
		if font != null:
			var at := p + Vector2(h + 3.0, font_px * 0.35)
			draw_string_outline(font, at, String(mk["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_px, 3, halo)
			draw_string(font, at, String(mk["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_px, text_ink)
