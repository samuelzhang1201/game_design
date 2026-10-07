@tool
class_name WarToolSlot
extends Control
## One slot of the WAR ROOM's tool roll (spec 2026-10-07-war-room-annotations-
## and-planning-pieces ruling 15, 2026-10-08-war-room-draw-orders ruling 1):
## an inked glyph of a side's crayon, a mark or an action, ringed in brass
## while chosen, faint while it cannot be used (`why`, its tooltip then). Its
## look is its exported fields, set in the scene; a click says `pressed(key)`.

signal pressed(key: String)

## hand, blue, red (sticks: the hand and each row's crayon); arrow, front, objective, phase (kinds);
## piece, scrape (actions).
@export var key := "hand":
	set(v):
		key = v
		queue_redraw()
## stick, kind or action.
@export var group := "stick"
## The glyph's pale ink on the leather.
@export var glyph_ink := Color(0.886, 0.808, 0.627):
	set(v):
		glyph_ink = v
		queue_redraw()
## A stick's own colour (its crayon or pen).
@export var stick_color := Color(0.18, 0.3, 0.53):
	set(v):
		stick_color = v
		queue_redraw()
## The brass ring round a chosen slot.
@export var ring := Color(0.839, 0.698, 0.376):
	set(v):
		ring = v
		queue_redraw()
@export var chosen := false:
	set(v):
		chosen = v
		queue_redraw()
## How faint a slot that cannot be used is drawn.
@export var faint := 0.3:
	set(v):
		faint = v
		queue_redraw()
## Why it cannot be used now ("" it can): drawn faint, said by its tooltip,
## and a click does nothing.
var why := "":
	set(v):
		if why == v:
			return
		if why == "":
			_hint = tooltip_text
		why = v
		tooltip_text = _hint if v == "" else v
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v == "" else Control.CURSOR_FORBIDDEN
		queue_redraw()
var _hint := ""


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if why == "":
			pressed.emit(key)
		accept_event()


func _draw() -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y) / 44.0   # the glyphs are drawn on a 44 px slot
	if chosen:
		draw_arc(c, 20.0 * s, 0.0, TAU, 32, ring, 2.5 * s, true)
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * s
	var ink := glyph_ink
	if why != "":
		ink.a *= faint
	var w := 2.0 * s
	match key:
		"hand":
			draw_polyline(PackedVector2Array([p.call(-6, 14), p.call(-10, -4), p.call(-4, -2), p.call(-4, -16),
				p.call(2, -16), p.call(2, -4), p.call(8, -4), p.call(10, 14)]), ink, w, true)
		"blue", "red", "ink":
			var body := PackedVector2Array([p.call(-14, 12), p.call(8, -12), p.call(14, -6), p.call(-8, 18)])
			draw_colored_polygon(body, stick_color)
			draw_polyline(body + PackedVector2Array([body[0]]), ink, 1.0 * s, true)
			draw_colored_polygon(PackedVector2Array([p.call(8, -12), p.call(14, -18), p.call(14, -6)]), stick_color)
		"arrow":
			draw_line(p.call(-14, 10), p.call(6, -6), ink, 6.0 * s, true)
			draw_colored_polygon(PackedVector2Array([p.call(2, -14), p.call(16, -14), p.call(14, 0)]), ink)
		"front":
			draw_line(p.call(-16, 4), p.call(16, 4), ink, 3.0 * s, true)
			for k: float in [-12.0, -2.0, 8.0]:
				draw_colored_polygon(PackedVector2Array([p.call(k - 4, 4), p.call(k, -6), p.call(k + 4, 4)]), ink)
		"objective":
			draw_arc(c, 13.0 * s, 0.0, TAU, 32, ink, w * 1.3, true)
			draw_arc(c, 9.0 * s, 0.0, TAU, 32, ink, w * 0.6, true)
		"phase":
			var k := -16.0
			while k < 14.0:
				draw_line(p.call(k, 8 - k * 0.5), p.call(k + 5, 8 - (k + 5) * 0.5), ink, w, true)
				k += 9.0
		"piece":
			draw_colored_polygon(PackedVector2Array([p.call(-12, 10), p.call(12, 10), p.call(9, 4), p.call(-9, 4)]), stick_color)
			draw_colored_polygon(PackedVector2Array([p.call(-6, 5), p.call(-4, -12), p.call(4, -12), p.call(6, 5)]), ink)
			draw_circle(p.call(0, -15), 4.0 * s, ink)
		"scrape":
			draw_polyline(PackedVector2Array([p.call(-14, 12), p.call(4, -10), p.call(12, -4), p.call(-6, 16), p.call(-14, 12)]), ink, w, true)
			draw_line(p.call(8, -7), p.call(16, -16), ink, 3.0 * s, true)
