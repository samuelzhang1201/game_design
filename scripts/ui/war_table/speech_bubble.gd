@tool
class_name SpeechBubble
extends Control
## A minister's word on the war table (owner 2026-10-02: UI上的头像下方缓缓弹出
## 一个奶白色的对话框说有事禀报): a cream bubble with a tail pointing up at the
## miniature it speaks for, its words in the paper's ink, a soft shadow down
## and right like every piece on the table. It sizes itself to its words; the
## seal places it and makes it rise (WaxSeal). A click on it is `pressed`.
## Its look is edited on the node in scenes/war_table/council_seal.tscn.

signal pressed

@export var text := "A matter to report, Majesty.":
	set(v):
		text = v
		_fit()
@export var font: Font:
	set(v):
		font = v
		_fit()
@export var font_px := 13:
	set(v):
		font_px = v
		_fit()
@export var paper := Color("f3ead6")
@export var ink := Color("3a2a1c")
@export var edge := Color("b9a47a")
@export var edge_px := 1.0
@export var radius_px := 7.0
@export var pad := Vector2(10, 6)
## The tail: its height above the bubble and its width at the base.
@export var tail_px := 7.0
@export var tail_w_px := 11.0
@export var shadow_alpha := 0.28
@export var shadow_offset := Vector2(2, 3.5)

## Where the tail's tip points, in the bubble's own x (its middle by default).
var tail_x := -1.0:
	set(v):
		tail_x = v
		queue_redraw()

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fit()

func _fit() -> void:
	if not is_inside_tree():
		return
	var f := font if font != null else get_theme_default_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var h := f.get_height(font_px)
	size = Vector2(ceilf(w + pad.x * 2.0), ceilf(h + pad.y * 2.0 + tail_px))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		pressed.emit()
		accept_event()

func _draw() -> void:
	var box := Rect2(Vector2(0, tail_px), Vector2(size.x, size.y - tail_px))
	var tx := clampf(tail_x if tail_x >= 0.0 else size.x * 0.5, radius_px + tail_w_px * 0.5,
		size.x - radius_px - tail_w_px * 0.5)
	var shape := _outline(box, tx)
	var shadow := PackedVector2Array()
	for p in shape:
		shadow.append(p + shadow_offset)
	draw_colored_polygon(shadow, Color(0, 0, 0, shadow_alpha))
	draw_colored_polygon(shape, paper)
	var closed := shape.duplicate()
	closed.append(shape[0])
	draw_polyline(closed, edge, edge_px, true)
	var f := font if font != null else get_theme_default_font()
	draw_string(f, Vector2(pad.x, box.position.y + pad.y + f.get_ascent(font_px)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, ink)

## The bubble's outline: a rounded box with the tail rising from its top edge
## at `tx`, clockwise from the tail's tip.
func _outline(box: Rect2, tx: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := minf(radius_px, minf(box.size.x, box.size.y) * 0.5)
	pts.append(Vector2(tx, 0.0))
	pts.append(Vector2(tx + tail_w_px * 0.5, box.position.y))
	var corners := [
		[Vector2(box.end.x - r, box.position.y + r), -PI * 0.5],
		[Vector2(box.end.x - r, box.end.y - r), 0.0],
		[Vector2(box.position.x + r, box.end.y - r), PI * 0.5],
		[Vector2(box.position.x + r, box.position.y + r), PI],
	]
	for c in corners:
		for k in 7:
			var a: float = float(c[1]) + PI * 0.5 * float(k) / 6.0
			pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2(tx - tail_w_px * 0.5, box.position.y))
	return pts
