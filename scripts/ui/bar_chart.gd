class_name BarChart
extends Control
## A small horizontal bar chart drawn in the panel: a muted label, a thin bar
## on a dark track, the value in text ink (dataviz rules: thin marks, text
## never wears the series colour, a legend is the labels themselves).
## rows = [{label, value, color, text}]; the bar runs to max_value.

const ROW_H := 9.0
const LABEL_W := 34.0
const VALUE_W := 22.0
const BAR_H := 4.0

var rows: Array = []
var max_value := 1.0

func set_rows(new_rows: Array, top: float) -> void:
	rows = new_rows
	max_value = maxf(top, 0.000001)
	custom_minimum_size = Vector2(0, ROW_H * rows.size())
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var track := UiPalette.chart_color("track")
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := ROW_H * i
		draw_string(font, Vector2(0, y + 7.0), String(r.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 7, UiPalette.TEXT_MUTED)
		var x0 := LABEL_W + 2.0
		var x1 := maxf(size.x - VALUE_W, x0 + 4.0)
		var yb := y + (ROW_H - BAR_H) / 2.0
		draw_rect(Rect2(x0, yb, x1 - x0, BAR_H), track)
		var frac := clampf(float(r.get("value", 0.0)) / max_value, 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(x0, yb, (x1 - x0) * frac, BAR_H), r.get("color", UiPalette.GOLD))
		var text := String(r.get("text", str(int(float(r.get("value", 0.0))))))
		draw_string(font, Vector2(x1 + 2.0, y + 7.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
			UiPalette.TEXT_SOFT)
