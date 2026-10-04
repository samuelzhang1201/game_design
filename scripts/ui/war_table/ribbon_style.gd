@tool
class_name RibbonStyle
extends StyleBox
## THE WAR TABLE's bookmark (owner 2026-10-01, C1's silk bookmarks on B3): a
## silk ribbon hanging from under the map sheet's lower edge, its foot cut in
## a swallow-tail, a sheen across it, its shadow on the table. Its colour is
## the tab's group. The LIT ribbon — the lens or
## screen that is open — hangs a little longer and brighter; a hovered one
## warms. Each colour and state is a .tres in
## assets/2D/ui/war_table/styles/ribbons/, edited in the inspector (owner
## 2026-10-02), worn by scenes/hud/bottom_bar.tscn's tabs.

## The silk's colour (the tab's group: vert the lenses, gules realm and war,
## azure people and law, purpure the church, or the books and letters).
@export var color := Color("35583e"):
	set(v):
		color = v
		emit_changed()
## Lit: the open lens or screen — longer and brighter.
@export var lit := false:
	set(v):
		lit = v
		emit_changed()
## Under the pointer: a touch warmer.
@export var hover := false:
	set(v):
		hover = v
		emit_changed()
## The swallow-tail notch, and how far the silk hangs below its label, px.
@export var tail := 8.0:
	set(v):
		tail = v
		emit_changed()
@export var drop := 14.0:
	set(v):
		drop = v
		emit_changed()
## Its shadow on the table (the light is upper left).
@export var shadow_offset := Vector2(3.3, 5.5):
	set(v):
		shadow_offset = v
		emit_changed()
@export var shadow_alpha := 0.34:
	set(v):
		shadow_alpha = v
		emit_changed()

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
