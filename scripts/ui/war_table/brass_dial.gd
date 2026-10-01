class_name BrassDial
extends Control
## THE WAR TABLE's date dial (owner 2026-10-01): a brass disc on the table
## with the day of the month engraved on it; the season and year are written
## beside it on the wood (the top bar's date label). Its tooltip is the full
## date.

var day := 1

func _init() -> void:
	name = "DateDial"
	var px := WarTable._num("ui_dial_px", 52.0)
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_day(d: int, full_date: String) -> void:
	day = d
	tooltip_text = full_date
	queue_redraw()

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var cols := [UiPalette.table_color("brass_light", Color("f4db9a")),
		UiPalette.table_color("brass_mid", Color("b08a3e")),
		UiPalette.table_color("brass_dark", Color("6b4e1c"))]
	BrassStyle.draw_brass(get_canvas_item(), c, r, cols, WarTable._num("ui_table_shadow_alpha", 0.34), false)
	draw_arc(c, r * 0.8, 0.0, TAU, 48, Color(cols[2], 0.55), 1.2, true)
	var font := UiPalette.role_font("body_bold")
	if font == null:
		font = get_theme_default_font()
	var fs := int(r * 0.95)
	var text := str(day)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := font.get_ascent(fs)
	draw_string(font, Vector2(c.x - w * 0.5, c.y + asc * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiPalette.table_color("ink", Color("2b1f15")))
