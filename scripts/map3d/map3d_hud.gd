class_name Map3DHud
extends Control
## The 3D map's furniture (owner 2026-09-18): the scale bar bottom-right —
## ScaleBar, the 2D map's own drawing, stating the 3D WORLD's metres (50 m
## per pack px; map_info's distance_scale is the 2D sheet's and would lie by
## 20x) — and the compass top-left: CompassLayer's oak wheel turning while
## time runs, as on the 2D map, under a north needle that turns with the
## view. Mouse-transparent; Map3DView routes a click on compass_rect() to
## its turn-north. Redrawn by the view whenever the camera moves.

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


## {distance_m, text, width_px} for the largest 1-2-5 distance whose bar fits
## in `max_px` at `m_per_px`; {} when nothing sensible fits.
static func scale_bar_for(m_per_px: float, max_px: float) -> Dictionary:
	if m_per_px <= 0.0 or max_px <= 0.0:
		return {}
	var d := MapGeometry.nice_step(max_px * m_per_px)
	if d <= 0.0:
		return {}
	var text := ("%s km" % ScaleBar.trim_zeros(d / 1000.0)) if d >= 1000.0 \
		else ("%s m" % ScaleBar.trim_zeros(d))
	return {"distance_m": d, "text": text, "width_px": d / m_per_px}


## The needle's turn, clockwise from screen-up, at a view yaw (Map3DGeometry
## .pose: yaw +90 puts north on the right).
static func needle_angle(yaw_deg: float) -> float:
	return deg_to_rad(yaw_deg)


## Top-left, the 2D compass's size and margin (the 2D map's is top-right).
func compass_rect() -> Rect2:
	var d := Game.data.bal("map_compass_size_px")
	var m := Game.data.bal("map_compass_margin_px")
	return Rect2(Vector2(m, m), Vector2(d, d)) if d > 0.0 else Rect2()


func _draw() -> void:
	if view == null:
		return
	ScaleBar.draw(self, scale_bar_for(view.metres_per_pixel(),
		Game.data.bal("map_scale_bar_max_px")), size)


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
	if not _compass.has_art():
		ci.draw_arc(c, r.size.x * 0.5 - 2.0, 0.0, TAU, 48, ink, 2.0, true)
	ci.draw_set_transform(c, needle_angle(view.yaw()), Vector2.ONE)
	var north := PackedVector2Array([Vector2(0, -reach), Vector2(w, 0), Vector2(-w, 0)])
	var south := PackedVector2Array([Vector2(0, reach), Vector2(w, 0), Vector2(-w, 0)])
	ci.draw_colored_polygon(south, Color(ink, 0.85))
	ci.draw_colored_polygon(north, gold)
	ci.draw_polyline(PackedVector2Array([Vector2(0, -reach), Vector2(w, 0), Vector2(0, reach),
		Vector2(-w, 0), Vector2(0, -reach)]), ink, 1.5, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
