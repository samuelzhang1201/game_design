@tool
class_name WarTableBackdrop
extends Control
## THE WAR TABLE's table (owner 2026-10-01, B3 + C1's bookmarks): pale oak
## planks by daylight behind every panel of a main screen — the planks tiled at
## balance ui_table_tile_px, a warm tone laid over them, one broad soft shaft
## of window light falling from the upper left (ui_table_light_*), and the far
## corners darkened. Every colour is data/screens/ui/ui_table_palette.csv. It takes no
## input and draws only when resized.

const ART_PATH := "res://assets/2D/ui/war_table/table_oak.jpg"

## The look, edited on the node (scenes/screens/court.tscn, conversation.tscn).
@export var texture: Texture2D = null:
	set(v):
		texture = v
		queue_redraw()
@export var tile_px := 560.0:
	set(v):
		tile_px = v
		queue_redraw()
@export var tone := Color(0, 0, 0, 0.2):
	set(v):
		tone = v
		queue_redraw()
@export var light := Color(1, 1, 1, 0.1):
	set(v):
		light = v
		queue_redraw()
@export var light_angle_deg := 28.0:
	set(v):
		light_angle_deg = v
		queue_redraw()
@export var light_width := 0.3:
	set(v):
		light_width = v
		queue_redraw()
@export var light_center := 0.5:
	set(v):
		light_center = v
		queue_redraw()
@export var vignette := Color(0, 0, 0, 0.3):
	set(v):
		vignette = v
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var tile := tile_px
	if texture != null and tile > 1.0:
		var y := 0.0
		while y < r.size.y:
			var x := 0.0
			while x < r.size.x:
				# the last row and column cut to the rect (the editor shows the
				# node's own bounds; the game's spans the screen)
				var w := minf(tile, r.size.x - x)
				var h := minf(tile, r.size.y - y)
				var px := Vector2(texture.get_size()) / tile
				draw_texture_rect_region(texture, Rect2(x, y, w, h), Rect2(Vector2.ZERO, Vector2(w, h) * px))
				x += tile
			y += tile
	draw_rect(r, tone)
	_draw_light(r)
	_draw_vignette(r)

## One soft shaft: a band slanted from vertical, full in its middle and gone at
## its sides (a quad strip whose outer vertices carry no alpha).
func _draw_light(r: Rect2) -> void:
	var c := light
	var slant := tan(deg_to_rad(light_angle_deg)) * r.size.y
	var half := light_width * r.size.x * 0.5
	var mid := light_center * r.size.x
	var clear := Color(c.r, c.g, c.b, 0.0)
	# top edge shifted left by half the slant, bottom edge right: light from the upper left
	var top := mid - slant * 0.5
	var bot := mid + slant * 0.5
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array([
			Vector2(top, 0), Vector2(top + side * half, 0),
			Vector2(bot + side * half, r.size.y), Vector2(bot, r.size.y)])
		draw_polygon(pts, PackedColorArray([c, clear, clear, c]))

## The corners darken toward the edge in four gradient bands.
func _draw_vignette(r: Rect2) -> void:
	var c := vignette
	var clear := Color(c.r, c.g, c.b, 0.0)
	var band := minf(r.size.x, r.size.y) * 0.28
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(r.size.x, 0), Vector2(r.size.x, band), Vector2(0, band)]),
		PackedColorArray([c, c, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, r.size.y - band), Vector2(r.size.x, r.size.y - band), Vector2(r.size.x, r.size.y), Vector2(0, r.size.y)]),
		PackedColorArray([clear, clear, c, c]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(band, 0), Vector2(band, r.size.y), Vector2(0, r.size.y)]),
		PackedColorArray([c, clear, clear, c]))
	draw_polygon(PackedVector2Array([Vector2(r.size.x - band, 0), Vector2(r.size.x, 0), Vector2(r.size.x, r.size.y), Vector2(r.size.x - band, r.size.y)]),
		PackedColorArray([clear, c, c, clear]))
