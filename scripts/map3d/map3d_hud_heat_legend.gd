class_name Map3DHudHeatLegend
extends Map3DHudPiece
## The HEIGHTS legend, bottom-left of the 3D map's HUD (owner 2026-09-19):
## the heat ramp (the ground look's heat_ramp) bottom to top, the tier lines
## ticked and named with their metres; faint (`yield_alpha`) while a
## MEASUREMENT ruler crosses it. Its look is edited on the node (owner
## 2026-10-02).

## The ramp's width and height, design px (bottom-left).
@export var ramp_w_px := 14.0
@export var ramp_h_px := 160.0
## The tier names' size, design px (the landmarks' own).
@export var font_px := 14
## Its opacity while a ruler runs through it, so the ruler's reading is never
## printed over a tier's name (Task 7 look pass, 2026-09-20).
@export var yield_alpha := 0.25


## The legend's box, bottom-left, in design px (Rect2() off HEIGHTS).
func rect() -> Rect2:
	if ctx == null or view == null or not view.heat_on():
		return Rect2()
	var w := ramp_w_px
	var h := ramp_h_px
	var margin := ctx.repo.bal("map_compass_margin_px")
	return Rect2(Vector2(margin, ctx.view_size.y - margin - h), Vector2(w, h))


## The legend's tier lines, bottom up: {label "Hills 750 m", y} in design px,
## each at its metres' share of the ramp's height. [] off HEIGHTS.
func ticks() -> Array:
	var box := rect()
	if box.size.y <= 0.0:
		return []
	var repo := ctx.repo
	var top_m := repo.bal("elevation_m_per_unit") * (100.0 - repo.bal("elevation_sea_level"))
	var out: Array = []
	for i in range(repo.army_height_supply.size() - 1, -1, -1):
		var r: Dictionary = repo.army_height_supply[i]
		var metres := Elevation.metres_of_height(repo, float(r["min_height"]))
		if metres <= 0 or top_m <= 0.0:
			continue
		out.append({"label": "%s %d m" % [String(r["tier"]).capitalize(), metres],
			"y": box.end.y - box.size.y * clampf(float(metres) / top_m, 0.0, 1.0)})
	return out


## The legend's whole footprint, design px: the ramp and its tier names
## (Rect2() off HEIGHTS).
func _area() -> Rect2:
	var box := rect()
	if box.size.y <= 0.0:
		return Rect2()
	var font := UiPalette.display_font()
	var w := 0.0
	for t: Dictionary in ticks():
		w = maxf(w, font.get_string_size(String(t["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_px).x if font != null else float(font_px) * String(t["label"]).length())
	return Rect2(box.position, Vector2(box.size.x + 7.0 + w, box.size.y))


## Whether the legend steps back for a MEASUREMENT ruler (Task 7 look pass):
## true while a ruler runs through the legend's footprint grown by the
## reading's size, so the reading is never printed over a tier's name.
func yields() -> bool:
	if not bound():
		return false
	var ruler := view.ruler()
	if not view.ruler_on or not ruler.active():
		return false
	var area := _area()
	if area.size.y <= 0.0:
		return false
	area = area.grow(ctx.repo.bal("map_ruler_font_px") + ctx.repo.bal("map_ruler_label_offset_px"))
	var camera := ctx.camera
	var a3 := Vector3(ruler.start.x, ctx.height_at(ruler.start), ruler.start.y)
	var b3 := Vector3(ruler.end.x, ctx.height_at(ruler.end), ruler.end.y)
	if camera.is_position_behind(a3) or camera.is_position_behind(b3):
		return false
	var s := ctx.viewport_px_scale()
	var a := camera.unproject_position(a3) / s
	var b := camera.unproject_position(b3) / s
	if area.has_point(a) or area.has_point(b):
		return true
	var c := [area.position, Vector2(area.end.x, area.position.y), area.end,
		Vector2(area.position.x, area.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false


func _draw() -> void:
	if not bound():
		return
	var box := rect()
	if box.size.y <= 0.0:
		return
	var repo := ctx.repo
	var fade := Color(1, 1, 1, yield_alpha) \
		if yields() else Color.WHITE
	var x0 := box.position.x
	var x1 := box.end.x
	var ramp := Map3DGroundLook.shared().heat_ramp
	for i in mini(5, ramp.size() - 1):
		var y0 := box.end.y - box.size.y * float(i) / 5.0
		var y1 := box.end.y - box.size.y * float(i + 1) / 5.0
		var c0 := ramp[i] * fade
		var c1 := ramp[i + 1] * fade
		draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0),
			Vector2(x1, y1), Vector2(x0, y1)]), PackedColorArray([c0, c0, c1, c1]))
	var font := UiPalette.display_font()
	var ink := MapPalette.named(repo, "landmark_text") * fade
	var halo := Color((get_parent() as Map3DHud).halo_color, 1.0) * fade
	for t: Dictionary in ticks():
		var y := float(t["y"])
		draw_line(Vector2(x0, y), Vector2(x1 + 4.0, y), ink, 1.5)
		if font != null:
			var at := Vector2(x1 + 7.0, y + font_px * 0.35)
			draw_string_outline(font, at, String(t["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_px, 3, halo)
			draw_string(font, at, String(t["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, ink)
