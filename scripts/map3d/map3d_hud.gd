class_name Map3DHud
extends Control
## The 3D map's furniture (owner 2026-09-18): the scale bar bottom-right —
## ScaleBar, the 2D map's own drawing, in the 2D map's own measure (owner
## 2026-09-18: the world is BUILT at 50 m per pack px, but it reads as the
## pack's distance_scale says, so both maps agree — Map3DView.
## map_units_per_metre) — and the compass top-left: CompassLayer's oak wheel turning while
## time runs, as on the 2D map, under a north needle that turns with the
## view. Mouse-transparent; Map3DView routes a click on compass_rect() to
## its turn-north. Redrawn by the view whenever the camera moves.
##
## Fix round 1 (owner 2026-09-18): a pale halo (terrain_palette
## map3d_hud_halo) under the scale bar's strokes/label and the needle's
## shadow/N, so both read over bright ground (snow, sea) that the 2D map
## never had to contend with; a soft dark vignette behind the wheel so map
## symbols at a busy zoom (24 km) don't tangle with its spokes; a drop
## shadow and a small rotating "N" so the needle reads as sitting over the
## wheel rather than pasted flat on it.

## A needle drawn as its own CanvasItem, added after CompassLayer so it
## paints on top of the wheel art: a CanvasItem child always draws over its
## earlier siblings at the same z_index, and a negative z_index on the
## wheel instead would sink it below the view's own TextureRect (a sibling
## of Hud, not a child of it) and hide it entirely.
class NeedleLayer:
	extends Node2D
	var hud: Map3DHud

	func _draw() -> void:
		if hud != null:
			hud._draw_needle(self)


var view: Map3DView
var _compass: CompassLayer
var _needle: NeedleLayer


func _ready() -> void:
	name = "Hud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compass = CompassLayer.new()
	_compass.name = "Compass"
	_compass.box = compass_rect
	add_child(_compass)
	_compass.setup()
	_needle = NeedleLayer.new()
	_needle.name = "Needle"
	_needle.hud = self
	add_child(_needle)


## Redraws the scale bar and, on top of the wheel, the needle (queue_redraw
## itself cannot be overridden — the engine refuses to call a script's
## override of a native CanvasItem method). Called by the view on every
## camera move.
func refresh() -> void:
	queue_redraw()
	if _needle != null:
		_needle.queue_redraw()


## {distance, text, width_px} for the largest 1-2-5 distance whose bar fits
## in `max_px` at `units_per_px` (the pack's distance_unit per screen px, so
## the bar reads what the 2D map's does — owner 2026-09-18); {} when nothing
## sensible fits.
static func scale_bar_for(units_per_px: float, max_px: float, unit: String) -> Dictionary:
	if units_per_px <= 0.0 or max_px <= 0.0:
		return {}
	var d := MapGeometry.nice_step(max_px * units_per_px)
	if d <= 0.0:
		return {}
	return {"distance": d, "text": ("%s %s" % [ScaleBar.trim_zeros(d), unit]).strip_edges(),
		"width_px": d / units_per_px}


## The needle's turn, clockwise from screen-up, at a view yaw (Map3DGeometry
## .pose: yaw +90 puts north on the right).
static func needle_angle(yaw_deg: float) -> float:
	return deg_to_rad(yaw_deg)


## Top-left, the 2D compass's size and margin (the 2D map's is top-right).
func compass_rect() -> Rect2:
	var d := Game.data.bal("map_compass_size_px")
	var m := Game.data.bal("map_compass_margin_px")
	return Rect2(Vector2(m, m), Vector2(d, d)) if d > 0.0 else Rect2()


## terrain_palette's pale halo, at map3d_hud_halo_alpha — {} (alpha 0) turns
## every halo off, including the 2D map's ScaleBar.draw call, which never
## passes one and so is untouched by this fix.
func _hud_halo() -> Color:
	var halo := MapTerrain.palette_color(Game.data, "map3d_hud_halo", MapTerrain.FALLBACK)
	halo.a = Game.data.bal("map3d_hud_halo_alpha")
	return halo


func _draw() -> void:
	if view == null:
		return
	# Own _draw() paints before every child (the wheel, the needle), so the
	# backdrop sits behind both with no z_index needed.
	_draw_compass_backdrop()
	ScaleBar.draw(self, scale_bar_for(view.metres_per_pixel() * view.map_units_per_metre(),
		Game.data.bal("map_scale_bar_max_px"), view.map_unit()), size, _hud_halo())
	# The MEASUREMENT ruler (owner 2026-09-18), over the scale bar.
	view.draw_ruler(self)


## A soft dark vignette behind the wheel (fix round 1: map symbols tangled
## with the spokes at 24 km), a few concentric filled circles layered from
## a pale wide one to a small one at map3d_compass_backdrop_alpha — normal
## alpha blending stacks them into a radial fade with no gradient texture.
func _draw_compass_backdrop() -> void:
	var r := compass_rect()
	if r.size.x <= 0.0:
		return
	var peak := Game.data.bal("map3d_compass_backdrop_alpha")
	if peak <= 0.0:
		return
	var c := r.get_center()
	var radius := r.size.x * 0.58
	var rings := 6
	for i in rings:
		var t := float(i + 1) / float(rings)
		draw_circle(c, radius * (1.0 - t), Color(0.0, 0.0, 0.0, peak * t))


func _draw_needle(ci: CanvasItem) -> void:
	if view == null:
		return
	var r := compass_rect()
	if r.size.x <= 0.0:
		return
	var c := r.get_center()
	var reach := r.size.x * 0.5 * Game.data.bal("map3d_compass_needle_reach")
	var w := r.size.x * 0.5 * Game.data.bal("map3d_compass_needle_width")
	var gold := MapPalette.named(Game.data, "map3d_selection")
	var ink := MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)
	var halo := _hud_halo()
	if not _compass.has_art():
		ci.draw_arc(c, r.size.x * 0.5 - 2.0, 0.0, TAU, 48, ink, 2.0, true)
	ci.draw_set_transform(c, needle_angle(view.yaw()), Vector2.ONE)
	var north := PackedVector2Array([Vector2(0, -reach), Vector2(w, 0), Vector2(-w, 0)])
	var south := PackedVector2Array([Vector2(0, reach), Vector2(w, 0), Vector2(-w, 0)])
	var shadow_alpha := Game.data.bal("map3d_compass_needle_shadow_alpha")
	if shadow_alpha > 0.0:
		var shadow := Color(0.0, 0.0, 0.0, shadow_alpha)
		var by := Vector2(1.5, 2.0)
		ci.draw_colored_polygon(_offset_poly(south, by), shadow)
		ci.draw_colored_polygon(_offset_poly(north, by), shadow)
	ci.draw_colored_polygon(south, Color(ink, 0.85))
	ci.draw_colored_polygon(north, gold)
	ci.draw_polyline(PackedVector2Array([Vector2(0, -reach), Vector2(w, 0), Vector2(0, reach),
		Vector2(-w, 0), Vector2(0, -reach)]), ink, 1.5, true)
	_draw_north_label(ci, gold, halo, reach)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small "N" just beyond the north tip, in the same rotated frame as the
## needle so it turns with it.
func _draw_north_label(ci: CanvasItem, gold: Color, halo: Color, reach: float) -> void:
	var font := UiPalette.display_font()
	if font == null:
		return
	var font_px := 10
	var text := "N"
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var pos := Vector2(-text_w * 0.5, -reach - 4.0)
	if halo.a > 0.0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 3, halo)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, gold)


static func _offset_poly(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(p + by)
	return out
