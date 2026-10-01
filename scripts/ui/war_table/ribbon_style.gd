class_name RibbonStyle
extends StyleBox
## THE WAR TABLE's bookmark (owner 2026-10-01, C1's silk bookmarks on B3): a
## silk ribbon hanging from under the map sheet's lower edge, its foot cut in
## a swallow-tail, a sheen across it, its shadow on the table. Its colour is
## the tab's group (data/ui_bookmarks.csv). The LIT ribbon — the lens or
## screen that is open — hangs a little longer and brighter; a hovered one
## warms.

var color := Color("35583e")
var lit := false
var hover := false
var tail := 8.0
var drop := 14.0
var shadow_offset := Vector2(4, 6)
var shadow_alpha := 0.34

static func make(p_color: Color, p_lit: bool, p_hover: bool) -> RibbonStyle:
	var s := RibbonStyle.new()
	s.color = p_color
	s.lit = p_lit
	s.hover = p_hover
	s.tail = WarTable._num("ui_bookmark_tail_px", 8.0)
	s.drop = WarTable._num("ui_bookmark_drop_px", 14.0)
	s.shadow_offset = Vector2(WarTable._num("ui_table_shadow_dx", 6.0), WarTable._num("ui_table_shadow_dy", 10.0)) * 0.55
	s.shadow_alpha = WarTable._num("ui_table_shadow_alpha", 0.34)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 9
	s.content_margin_bottom = s.drop
	return s

## The ribbon's outline in `rect`, the lit one reaching `extra` further down.
func outline(rect: Rect2, extra: float) -> PackedVector2Array:
	var b := rect.end.y + extra
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, b), Vector2(rect.get_center().x, b - tail), Vector2(rect.position.x, b)])

func _draw(ci: RID, rect: Rect2) -> void:
	var extra := drop * 0.45 if lit else 0.0
	var pts := outline(rect, extra)
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + shadow_offset)
	RenderingServer.canvas_item_add_polygon(ci, sh, PackedColorArray([Color(0, 0, 0, shadow_alpha * 0.7)]))
	var body := color
	if lit:
		body = color.lightened(0.14)
	elif hover:
		body = color.lightened(0.07)
	var edge := body.darkened(0.3)
	# the sheen: darker at both edges, lit down the middle
	var mid := rect.get_center().x
	var b := rect.end.y + extra
	var left := PackedVector2Array([rect.position, Vector2(mid, rect.position.y), Vector2(mid, b - tail), Vector2(rect.position.x, b)])
	var right := PackedVector2Array([Vector2(mid, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, b), Vector2(mid, b - tail)])
	RenderingServer.canvas_item_add_polygon(ci, left, PackedColorArray([edge, body, body, edge]))
	RenderingServer.canvas_item_add_polygon(ci, right, PackedColorArray([body, edge, edge, body]))
	# where it comes out from under the sheet: the sheet's shadow across it
	var fall := 5.0
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y + fall), Vector2(rect.position.x, rect.position.y + fall)]),
		PackedColorArray([Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	if lit:
		RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position + Vector2(3, 5), Vector2(rect.size.x - 6, 1.0)),
			Color(UiPalette.table_color("brass_light", Color.WHITE), 0.7))
