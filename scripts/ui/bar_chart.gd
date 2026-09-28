class_name BarChart
extends Control
## A small horizontal bar chart drawn in the panel: a muted label, a thin bar
## on a dark track, the value in text ink (dataviz rules: thin marks, text
## never wears the series colour, a legend is the labels themselves).
## rows = [{label, value, color, text, icon?, dimension?}]; the bar runs to
## max_value. A row with an `icon` glyph name draws that glyph before its
## label. A row with a `dimension` (a data/resource_icons.csv key) draws
## that key's art IN PLACE of the label, which becomes the row's floating
## tooltip (owner 2026-09-13: icons, not words, on the realm card), and the
## bar starts right after the art.

const ROW_H := 22.0
## Widened 68 -> 92 with the label 14 -> 13 px for Cinzel Decorative
## (2026-09-13), which runs far wider than EB Garamond did and cut
## "Legitimacy" to "Legitima".
const LABEL_W := 92.0
const LABEL_PX := 13
const VALUE_W := 44.0
## The column a dimension's art takes at the row's start.
const ICON_W := 30.0
const ICON_PX := 22.0
const BAR_H := 8.0
## NAMED rows (owner 2026-09-28, after the UI critique: five gauges told apart
## only by their art had to be hovered to be read): the art, then the name
## over a thin bar, the value at the end. Taller, so the bar can sit under
## the name instead of beside it in a 240 px column.
const NAMED_ROW_H := 26.0
const NAMED_BAR_H := 5.0

var rows: Array = []
## Whether a dimension row writes its name beside its art (balance
## ui_dimension_labels picks it for the realm card).
var named := false
var max_value := 1.0

func _init() -> void:
	# Hover must reach the chart for the row tooltips, and pass on to the
	# column's scrolling.
	mouse_filter = Control.MOUSE_FILTER_PASS

## The row under a point, or -1.
func row_at(at_position: Vector2) -> int:
	var i := int(floor(at_position.y / row_h()))
	return i if i >= 0 and i < rows.size() and at_position.x >= 0.0 else -1

## The dimension row under the pointer names itself in the tooltip.
func _get_tooltip(at_position: Vector2) -> String:
	var i := row_at(at_position)
	if i < 0:
		return ""
	var key := String((rows[i] as Dictionary).get("dimension", ""))
	return ResourceIcon.tooltip_of(key) if key != "" else ""

func row_h() -> float:
	return NAMED_ROW_H if named else ROW_H

func set_rows(new_rows: Array, top: float) -> void:
	rows = new_rows
	max_value = maxf(top, 0.000001)
	custom_minimum_size = Vector2(0, row_h() * rows.size())
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var track := UiPalette.chart_color("track")
	if named:
		_draw_named(font, track)
		return
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := ROW_H * i
		var lx := 0.0
		var x0 := LABEL_W + 4.0
		var dimension := String(r.get("dimension", ""))
		if dimension != "":
			ResourceIcon.draw_icon(self, dimension, Vector2(ICON_W / 2.0, y + ROW_H / 2.0), ICON_PX,
				UiPalette.GOLD)
			x0 = ICON_W + 4.0
		else:
			var glyph := String(r.get("icon", ""))
			if glyph != "":
				ResourceIcon.draw_glyph(self, glyph, Vector2(8.0, y + ROW_H / 2.0), 14.0,
					r.get("color", UiPalette.GOLD))
				lx = 18.0
			draw_string(font, Vector2(lx, y + 14.0), String(r.get("label", "")),
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - lx, LABEL_PX, UiPalette.TEXT_MUTED)
		var x1 := maxf(size.x - VALUE_W, x0 + 8.0)
		var yb := y + (ROW_H - BAR_H) / 2.0
		draw_rect(Rect2(x0, yb, x1 - x0, BAR_H), track)
		var frac := clampf(float(r.get("value", 0.0)) / max_value, 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(x0, yb, (x1 - x0) * frac, BAR_H), r.get("color", UiPalette.GOLD))
		var text := String(r.get("text", str(int(float(r.get("value", 0.0))))))
		draw_string(font, Vector2(x1 + 4.0, y + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			UiPalette.TEXT_SOFT)


func _draw_named(font: Font, track: Color) -> void:
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := NAMED_ROW_H * i
		var x0 := 0.0
		var dimension := String(r.get("dimension", ""))
		if dimension != "":
			ResourceIcon.draw_icon(self, dimension, Vector2(ICON_W / 2.0, y + NAMED_ROW_H / 2.0),
				ICON_PX, UiPalette.GOLD)
			x0 = ICON_W + 4.0
		var x1 := maxf(size.x - VALUE_W, x0 + 8.0)
		draw_string(font, Vector2(x0, y + 12.0), String(r.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT, x1 - x0, LABEL_PX, UiPalette.TEXT_MUTED)
		var yb := y + NAMED_ROW_H - NAMED_BAR_H - 5.0
		draw_rect(Rect2(x0, yb, x1 - x0, NAMED_BAR_H), track)
		var frac := clampf(float(r.get("value", 0.0)) / max_value, 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(x0, yb, (x1 - x0) * frac, NAMED_BAR_H), r.get("color", UiPalette.GOLD))
		var text := String(r.get("text", str(int(float(r.get("value", 0.0))))))
		# On the bar's line, where the eye already is.
		draw_string(font, Vector2(x1, yb + NAMED_BAR_H + 1.0), text,
			HORIZONTAL_ALIGNMENT_RIGHT, VALUE_W, 14, UiPalette.TEXT_SOFT)
