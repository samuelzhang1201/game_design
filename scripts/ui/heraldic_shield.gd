class_name HeraldicShield
extends Control
## A small heater shield in a kingdom's colour with an initial on it — the
## card's heraldry until real coats of arms exist (user request 2026-09-09,
## after Azgaar's burg editor).

var color: Color = UiPalette.GOLD
var initial := ""

func _init() -> void:
	custom_minimum_size = Vector2(22, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_arms(kingdom_color: Color, letter: String) -> void:
	color = kingdom_color
	initial = letter
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var shape := PackedVector2Array([Vector2(1, 1), Vector2(w - 1, 1), Vector2(w - 1, h * 0.55),
		Vector2(w / 2.0, h - 1), Vector2(1, h * 0.55)])
	draw_colored_polygon(shape, color)
	draw_polyline(shape + PackedVector2Array([shape[0]]), UiPalette.GOLD, 1.0, true)
	var font := UiPalette.display_font()
	if font == null or initial == "":
		return
	var px := int(h * 0.5)
	var tw := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	font.draw_string(get_canvas_item(), Vector2((w - tw) / 2.0, h * 0.62), initial,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, UiPalette.PANEL_BG)
