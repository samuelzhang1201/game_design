class_name BoardStyle
extends StyleBox
## THE WAR TABLE's tally board (owner 2026-10-01): a plank of darkened oak
## lying on the table under the two purses — the table's own planks drawn
## darker (ui_table_palette.csv `board`), a lit top edge, a brass nail at each
## end, and the table's one shadow thrown down-right.

var texture: Texture2D = null
var tile := 360.0
var tint := Color("2a1c12")
var shadow_offset := Vector2(6, 10)
var shadow_alpha := 0.34
var nail_px := 7.0
var brass := [Color("f4db9a"), Color("b08a3e"), Color("6b4e1c")]

static func make(margin_h: float, margin_v: float) -> BoardStyle:
	var s := BoardStyle.new()
	if ResourceLoader.exists(WarTableBackdrop.ART_PATH):
		s.texture = load(WarTableBackdrop.ART_PATH)
	s.tint = UiPalette.table_color("board", s.tint)
	s.shadow_offset = Vector2(WarTable._num("ui_table_shadow_dx", 6.0), WarTable._num("ui_table_shadow_dy", 10.0)) * 0.6
	s.shadow_alpha = WarTable._num("ui_table_shadow_alpha", 0.34)
	s.nail_px = WarTable._num("ui_board_nail_px", 7.0)
	s.brass = [UiPalette.table_color("brass_light", s.brass[0]),
		UiPalette.table_color("brass_mid", s.brass[1]),
		UiPalette.table_color("brass_dark", s.brass[2])]
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s

func _draw(ci: RID, rect: Rect2) -> void:
	for i in 3:
		var g := 3.0 * float(i)
		RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position + shadow_offset - Vector2(g, g), rect.size + Vector2(2 * g, 2 * g)),
			Color(0, 0, 0, shadow_alpha * [0.5, 0.3, 0.2][i]))
	if texture != null:
		# the plank: the table's grain, darkened to the board's colour
		RenderingServer.canvas_item_add_texture_rect_region(ci, rect, texture.get_rid(),
			Rect2(Vector2.ZERO, Vector2(rect.size.x, rect.size.y) * (float(texture.get_width()) / tile)),
			Color(tint.r * 4.4, tint.g * 4.4, tint.b * 4.4, 1.0))
	else:
		RenderingServer.canvas_item_add_rect(ci, rect, tint)
	RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position, Vector2(rect.size.x, 2.0)), Color(1, 0.9, 0.7, 0.28))
	RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position, Vector2(2.0, rect.size.y)), Color(1, 0.9, 0.7, 0.16))
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(rect.end.x - 2.0, rect.position.y), Vector2(2.0, rect.size.y)), Color(0, 0, 0, 0.35))
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(rect.position.x, rect.end.y - 2.0), Vector2(rect.size.x, 2.0)), Color(0, 0, 0, 0.45))
	var y := rect.get_center().y
	for x in [rect.position.x + nail_px * 1.4, rect.end.x - nail_px * 1.4]:
		BrassStyle.draw_brass(ci, Vector2(x, y), nail_px * 0.5, brass, shadow_alpha)
