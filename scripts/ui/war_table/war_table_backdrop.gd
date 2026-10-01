class_name WarTableBackdrop
extends Control
## THE WAR TABLE's table (owner 2026-10-01, B3 + C1's bookmarks): pale oak
## planks by daylight behind every panel of a main screen — the planks tiled at
## balance ui_table_tile_px, a warm tone laid over them, one broad soft shaft
## of window light falling from the upper left (ui_table_light_*), and the far
## corners darkened. Every colour is data/ui_table_palette.csv. It takes no
## input and draws only when resized.

const ART_PATH := "res://assets/2D/ui/war_table/table_oak.jpg"

var _tex: Texture2D = null

## Put a table under `screen`'s panels in place of its flat background colour
## (`bg`, the screen's full-rect ColorRect), or leave the screen as it is when
## the war table is off. Returns the table, or null.
static func install(screen: Control, bg: ColorRect) -> WarTableBackdrop:
	if not UiPalette.war_table():
		return null
	var t := WarTableBackdrop.new()
	t.name = "WarTable"
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(t)
	screen.move_child(t, bg.get_index() + 1)
	bg.color = UiPalette.table_color("board", bg.color)
	return t

func _ready() -> void:
	if ResourceLoader.exists(ART_PATH):
		_tex = load(ART_PATH)
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var tile := _num("ui_table_tile_px", 560.0)
	if _tex != null and tile > 1.0:
		var y := 0.0
		while y < r.size.y:
			var x := 0.0
			while x < r.size.x:
				draw_texture_rect(_tex, Rect2(x, y, tile, tile), false)
				x += tile
			y += tile
	draw_rect(r, UiPalette.table_color("table_tone", Color(0, 0, 0, 0.2)))
	_draw_light(r)
	_draw_vignette(r)

## One soft shaft: a band slanted from vertical, full in its middle and gone at
## its sides (a quad strip whose outer vertices carry no alpha).
func _draw_light(r: Rect2) -> void:
	var c := UiPalette.table_color("light", Color(1, 1, 1, 0.1))
	var slant := tan(deg_to_rad(_num("ui_table_light_angle_deg", 28.0))) * r.size.y
	var half := _num("ui_table_light_width", 0.3) * r.size.x * 0.5
	var mid := _num("ui_table_light_center", 0.5) * r.size.x
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
	var c := UiPalette.table_color("vignette", Color(0, 0, 0, 0.3))
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

static func _num(key: String, fallback: float) -> float:
	if Game != null and Game.data != null and Game.data.balance.has(key):
		return Game.data.bal(key)
	return fallback
