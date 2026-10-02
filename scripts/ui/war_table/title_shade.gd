@tool
class_name TitleShade
extends Control
## THE LIVING REALM's reading side (owner 2026-10-01, title plan A): the left
## of the title darkened over the live map so its words read, fading out
## `reach` across the screen, and the top and foot a touch darker. Its look is
## edited on the node (scenes/main_menu.tscn's Shade; owner 2026-10-02).

## The darkness at the left edge, 0..1.
@export_range(0.0, 1.0, 0.01) var shade := 0.92:
	set(v):
		shade = v
		queue_redraw()
## How far across the screen it reaches, a share of the width.
@export_range(0.0, 1.0, 0.01) var reach := 0.62:
	set(v):
		reach = v
		queue_redraw()
## The shade's colour (warm umber, near black).
@export var tint := Color(0.055, 0.04, 0.03):
	set(v):
		tint = v
		queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var dark := Color(tint, shade)
	var clear := Color(dark, 0.0)
	var x := w * reach
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(x, 0), Vector2(x, h), Vector2(0, h)]),
		PackedColorArray([dark, clear, clear, dark]))
	var band := h * 0.22
	var edge := Color(dark, dark.a * 0.55)
	var edge0 := Color(dark, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, h - band), Vector2(w, h - band), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([edge0, edge0, edge, edge]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, band * 0.6), Vector2(0, band * 0.6)]),
		PackedColorArray([edge, edge, edge0, edge0]))
