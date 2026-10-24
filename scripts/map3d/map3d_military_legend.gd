@tool
class_name Map3DMilitaryLegend
extends Control
## The authored scroll viewport owns placement; shared symbol data owns every key.
@export var symbols: Map3DUnitSymbols
@export var row_size := Vector2.ZERO
@export var icon_size := Vector2.ZERO
@export var text_offset := Vector2.ZERO
@export var panel: StyleBox
@export var text_ink := Color()


func apply_mode(on: bool, military: bool) -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll != null: scroll.visible = on and military and symbols != null
	visible = on and military and symbols != null
	queue_redraw()


func _draw() -> void:
	if symbols == null: return
	custom_minimum_size = Vector2(row_size.x, row_size.y * symbols.legend_keys.size())
	if panel != null: draw_style_box(panel, Rect2(Vector2.ZERO, size))
	for i: int in symbols.legend_keys.size():
		var key := symbols.legend_keys[i]
		var top := Vector2(0.0, row_size.y * i)
		var rect := Rect2(top + Vector2((text_offset.x - icon_size.x) * 0.5, (row_size.y - icon_size.y) * 0.5), icon_size)
		symbols.draw_symbol(self, rect, "infantry" if key == "royal" else (key if symbols.glyphs.has(key) else ""), key if symbols.frames.has(key) else "own", key == "royal")
		if symbols.font != null:
			draw_string(symbols.font, top + text_offset, String(symbols.labels.get(key, key)), HORIZONTAL_ALIGNMENT_LEFT, -1, symbols.font_px, text_ink)
