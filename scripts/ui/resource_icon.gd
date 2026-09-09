class_name ResourceIcon
extends Control
## A small drawn glyph for a resource or a unit type (user request
## 2026-09-09: icons instead of words, with a floating tooltip). The glyphs
## are simple strokes in the UI's gold so they match the chrome at any scale;
## which glyph and what the tooltip says come from data/resource_icons.csv.

const SIDE := 9.0

var key := ""
var color: Color = UiPalette.GOLD

static func create(resource_key: String, tint: Color = UiPalette.GOLD) -> ResourceIcon:
	var icon := ResourceIcon.new()
	icon.key = resource_key
	icon.color = tint
	return icon

func _init() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready() -> void:
	var row: Dictionary = Game.data.resource_icons.get(key, {})
	if not row.is_empty():
		tooltip_text = "%s — %s" % [String(row["label"]), String(row["tooltip"])]
	queue_redraw()

## The glyph name this key draws (data), or the key itself.
func glyph() -> String:
	return String((Game.data.resource_icons.get(key, {}) as Dictionary).get("icon", key))

func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		s = SIDE
	draw_glyph(self, glyph(), Vector2(size.x, size.y) / 2.0, s, color)

## Draw one glyph on any canvas item (bars draw them at row starts): centred
## on `c`, `s` px across, in `color`.
static func draw_glyph(ci: CanvasItem, name: String, c: Vector2, s: float, color: Color) -> void:
	var u := s / 9.0  # one design unit
	match name:
		"coin":
			ci.draw_circle(c, 3.6 * u, color)
			ci.draw_arc(c, 2.2 * u, 0.0, TAU, 16, UiPalette.PANEL_BG, 0.8 * u, true)
		"grain":
			for dx in [-2.2, 0.0, 2.2]:
				var top := c + Vector2(dx * u, -3.8 * u)
				ci.draw_line(c + Vector2(0, 4.0 * u), top, color, 0.9 * u, true)
				ci.draw_circle(top, 1.0 * u, color)
		"people":
			for dx in [-1.9, 1.9]:
				var head := c + Vector2(dx * u, -2.0 * u)
				ci.draw_circle(head, 1.4 * u, color)
				ci.draw_rect(Rect2(head + Vector2(-1.8 * u, 1.8 * u), Vector2(3.6 * u, 3.0 * u)), color)
		"swords":
			ci.draw_line(c + Vector2(-3.5, 3.5) * u, c + Vector2(3.5, -3.5) * u, color, 1.0 * u, true)
			ci.draw_line(c + Vector2(3.5, 3.5) * u, c + Vector2(-3.5, -3.5) * u, color, 1.0 * u, true)
			ci.draw_line(c + Vector2(-2.6, 1.0) * u, c + Vector2(-1.0, 2.6) * u, color, 1.0 * u, true)
			ci.draw_line(c + Vector2(2.6, 1.0) * u, c + Vector2(1.0, 2.6) * u, color, 1.0 * u, true)
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.2) * u,
				c + Vector2(2.4, -0.5) * u, c + Vector2(1.6, 4.0) * u, c + Vector2(-1.6, 4.0) * u,
				c + Vector2(-2.4, -0.5) * u]), color)
			ci.draw_circle(c + Vector2(0, 1.6 * u), 1.1 * u, UiPalette.PANEL_BG)
		"crown":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 3.5) * u, c + Vector2(4, 3.5) * u,
				c + Vector2(4, -1.5) * u, c + Vector2(2, 0.5) * u, c + Vector2(0, -3.8) * u,
				c + Vector2(-2, 0.5) * u, c + Vector2(-4, -1.5) * u]), color)
		"sun":
			ci.draw_circle(c, 2.0 * u, color)
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2.from_angle(a) * 2.8 * u, c + Vector2.from_angle(a) * 4.2 * u,
					color, 0.8 * u, true)
		"cross":
			ci.draw_line(c + Vector2(0, -4.2) * u, c + Vector2(0, 4.2) * u, color, 1.2 * u, true)
			ci.draw_line(c + Vector2(-2.6, -1.6) * u, c + Vector2(2.6, -1.6) * u, color, 1.2 * u, true)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3.5, -3.5) * u, c + Vector2(3.5, -3.5) * u,
				c + Vector2(3.5, 0.5) * u, c + Vector2(0, 4.2) * u, c + Vector2(-3.5, 0.5) * u]), color)
		"bow":
			ci.draw_arc(c + Vector2(-1.0 * u, 0), 3.8 * u, -PI / 2.2, PI / 2.2, 12, color, 1.0 * u, true)
			ci.draw_line(c + Vector2(-1.0, -3.4) * u, c + Vector2(-1.0, 3.4) * u, color, 0.7 * u, true)
			ci.draw_line(c + Vector2(-2.6, 0) * u, c + Vector2(4.0, 0) * u, color, 0.8 * u, true)
		"horseshoe":
			ci.draw_arc(c + Vector2(0, 0.6 * u), 3.3 * u, PI * 0.15, PI * 0.85 + PI, 16, color, 1.3 * u, true)
		"cannon":
			ci.draw_circle(c + Vector2(-1.2 * u, 1.6 * u), 2.0 * u, color)
			ci.draw_line(c + Vector2(-1.0, 0.4) * u, c + Vector2(4.0, -3.2) * u, color, 1.6 * u, true)
		"sail":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.4, -4.2) * u, c + Vector2(3.4, 1.4) * u,
				c + Vector2(-0.4, 1.4) * u]), color)
			ci.draw_line(c + Vector2(-3.8, 2.6) * u, c + Vector2(3.8, 2.6) * u, color, 1.2 * u, true)
		_:
			ci.draw_rect(Rect2(c - Vector2(3, 3) * u, Vector2(6, 6) * u), color, false, 1.0 * u)
