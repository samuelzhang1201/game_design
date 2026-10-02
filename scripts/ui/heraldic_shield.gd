@tool
class_name HeraldicShield
extends Control
## A house's or a kingdom's coat of arms (owner 2026-09-15): the generated
## arms (HouseArms) fitted into the rect when there is a texture, else a
## small heater shield in a kingdom's colour with an initial on it — what a
## family with no seat still shows (user request 2026-09-09, after Azgaar's
## burg editor).

## The fallback shield's colour and letter, and the arms when there are any
## (the running game sets all three from the crown's house).
@export var color: Color = UiPalette.GOLD:
	set(v):
		color = v
		queue_redraw()
@export var initial := "":
	set(v):
		initial = v
		queue_redraw()
@export var texture: Texture2D = null:
	set(v):
		texture = v
		queue_redraw()

## The defaults of a shield made in code. A scene's node keeps what the scene
## says: the scene's properties are set before its script, so _init runs
## after them and must not overwrite them.
func _init() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(44, 52)
	if mouse_filter == Control.MOUSE_FILTER_STOP:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_arms(kingdom_color: Color, letter: String) -> void:
	color = kingdom_color
	initial = letter
	queue_redraw()

## The arms to draw; null falls back to the coloured shield and its initial.
func set_texture(arms: Texture2D) -> void:
	texture = arms
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if texture != null:
		var ts := texture.get_size()
		var k := minf(w / ts.x, h / ts.y)
		var drawn := ts * k
		draw_texture_rect(texture, Rect2((size - drawn) / 2.0, drawn), false)
		return
	var shape := PackedVector2Array([Vector2(2, 2), Vector2(w - 2, 2), Vector2(w - 2, h * 0.55),
		Vector2(w / 2.0, h - 2), Vector2(2, h * 0.55)])
	draw_colored_polygon(shape, color)
	draw_polyline(shape + PackedVector2Array([shape[0]]), UiPalette.GOLD, 2.0, true)
	var font := UiPalette.display_font()
	if font == null or initial == "":
		return
	var px := int(h * 0.5)
	var tw := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	font.draw_string(get_canvas_item(), Vector2((w - tw) / 2.0, h * 0.62), initial,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, UiPalette.PANEL_BG)
