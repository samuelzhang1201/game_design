@tool
class_name BrassDial
extends Control
## THE WAR TABLE's date dial (owner 2026-10-01): a brass disc on the table
## with the day of the month engraved on it; the season and year are written
## beside it on the wood (the top bar's date label). Its tooltip is the full
## date. Its look is edited on the node (scenes/hud/top_bar.tscn).

@export var day := 1:
	set(v):
		day = v
		queue_redraw()
## Brass: the lit side, the body, the shadowed rim.
@export var brass: Array[Color] = [Color("f4db9a"), Color("b08a3e"), Color("6b4e1c")]:
	set(v):
		brass = v
		queue_redraw()
@export var ink := Color("2b1f15"):
	set(v):
		ink = v
		queue_redraw()
@export var shadow_alpha := 0.34:
	set(v):
		shadow_alpha = v
		queue_redraw()
## The engraved figure's face (the body's bold role).
@export var font: Font = null:
	set(v):
		font = v
		queue_redraw()

## The defaults of a dial made in code; a scene's node keeps what the scene
## says (its properties are set before its script, so _init runs after them).
func _init() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(52, 52)
	if size_flags_vertical == Control.SIZE_FILL:
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if mouse_filter == Control.MOUSE_FILTER_STOP:
		mouse_filter = Control.MOUSE_FILTER_PASS

func set_day(d: int, full_date: String) -> void:
	day = d
	tooltip_text = full_date

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	BrassStyle.draw_brass(get_canvas_item(), c, r, brass, shadow_alpha, false)
	draw_arc(c, r * 0.8, 0.0, TAU, 48, Color(brass[2], 0.55), 1.2, true)
	var face := font if font != null else get_theme_default_font()
	var fs := int(r * 0.95)
	var text := str(day)
	var w := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := face.get_ascent(fs)
	draw_string(face, Vector2(c.x - w * 0.5, c.y + asc * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
