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
## TALLY rows (THE WAR TABLE, owner 2026-10-01): a named row writes its gauge
## as the steward's tally marks — one per balance ui_tally_per_mark points,
## gated in fives — between its name and its figure, in place of the bar.
var tally := false

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
	var track := UiPalette.ink("track")
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
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - lx, LABEL_PX, UiPalette.ink("muted"))
		var x1 := maxf(size.x - VALUE_W, x0 + 8.0)
		var yb := y + (ROW_H - BAR_H) / 2.0
		draw_rect(Rect2(x0, yb, x1 - x0, BAR_H), track)
		var frac := clampf(float(r.get("value", 0.0)) / max_value, 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(x0, yb, (x1 - x0) * frac, BAR_H), r.get("color", UiPalette.GOLD))
		var text := String(r.get("text", str(int(float(r.get("value", 0.0))))))
		draw_string(font, Vector2(x1 + 4.0, y + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			UiPalette.ink("soft"))


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
		if tally:
			_draw_tally_row(font, r, y, x0, x1)
			continue
		draw_string(font, Vector2(x0, y + 12.0), String(r.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT, x1 - x0, LABEL_PX, UiPalette.ink("muted"))
		var yb := y + NAMED_ROW_H - NAMED_BAR_H - 5.0
		draw_rect(Rect2(x0, yb, x1 - x0, NAMED_BAR_H), track)
		var frac := clampf(float(r.get("value", 0.0)) / max_value, 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(x0, yb, (x1 - x0) * frac, NAMED_BAR_H), r.get("color", UiPalette.GOLD))
		var text := String(r.get("text", str(int(float(r.get("value", 0.0))))))
		# On the bar's line, where the eye already is.
		draw_string(font, Vector2(x1, yb + NAMED_BAR_H + 1.0), text,
			HORIZONTAL_ALIGNMENT_RIGHT, VALUE_W, 14, UiPalette.ink("soft"))

## One tally row: the name in body ink at the row's middle, the marks right of
## it ending before the figure, the figure right-aligned. A value under one
## mark writes a dash.
func _draw_tally_row(font: Font, r: Dictionary, y: float, x0: float, x1: float) -> void:
	var mid := y + NAMED_ROW_H / 2.0
	draw_string(font, Vector2(x0, mid + 5.0), String(r.get("label", "")),
		HORIZONTAL_ALIGNMENT_LEFT, x1 - x0, 15, UiPalette.ink("soft"))
	var per := 10.0
	if Game != null and Game.data != null and Game.data.balance.has("ui_tally_per_mark"):
		per = maxf(Game.data.bal("ui_tally_per_mark"), 1.0)
	var marks := tally_marks(float(r.get("value", 0.0)), per)
	var ink := r.get("color", UiPalette.ink("soft")) as Color
	var step := 3.4
	var gate_gap := 5.0
	var h := 13.0
	var width := 0.0
	for k in marks:
		width += step if (k + 1) % 5 != 0 else 0.0
		if (k + 1) % 5 == 0 and k + 1 < marks:
			width += gate_gap
	var right := x1 - 6.0
	var x := right - maxf(width, 4.0)
	if marks <= 0:
		draw_line(Vector2(right - 12.0, mid), Vector2(right, mid), UiPalette.ink("muted"), 1.4, true)
	else:
		var in_gate := 0
		var gate_x := x
		for k in marks:
			if in_gate < 4:
				var tilt := 1.0 if k % 2 == 0 else 0.4
				draw_line(Vector2(x + tilt, mid - h / 2.0), Vector2(x, mid + h / 2.0), ink, 1.5, true)
				if in_gate == 0:
					gate_x = x
				x += step
				in_gate += 1
			else:
				# the fifth strikes the four
				draw_line(Vector2(gate_x - 2.0, mid + 3.5), Vector2(x + 0.5, mid - 3.5), ink, 1.5, true)
				x += gate_gap
				in_gate = 0
	var text := String(r.get("text", str(int(float(r.get("value", 0.0))))))
	draw_string(font, Vector2(x1, mid + 5.0), text, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_W, 15,
		UiPalette.ink("soft"))

## How many strokes a value writes: its WHOLE tens (49 is four strokes, 50 a
## gate of five) — the critic of 2026-10-01: rounded, 49 and 50 drew alike.
static func tally_marks(value: float, per: float) -> int:
	return maxi(floori(value / maxf(per, 1.0)), 0)
