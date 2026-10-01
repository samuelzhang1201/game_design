class_name PieChart
extends Control
## A small pie for a part-to-whole with a few slices: the disc on the left,
## a legend of swatch + label + value on the right so no reading depends on
## colour alone. slices = [{label, value, color, dimension?}]. A slice with a
## `dimension` (a data/resource_icons.csv key) shows that key's art in the
## legend instead of its label, which becomes the floating tooltip (owner
## 2026-09-13).

const HEIGHT := 60.0
const RADIUS := 26.0
const LEGEND_X := 64.0
const LEGEND_ROW := 22.0
const ICON_PX := 22.0

var slices: Array = []
## Whether a slice with art writes its name beside it too (balance
## ui_dimension_labels, owner 2026-09-28).
var named := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

## The legend row under a point, or -1.
func legend_row_at(at_position: Vector2) -> int:
	if at_position.x < LEGEND_X:
		return -1
	var i := int(floor((at_position.y - 2.0) / LEGEND_ROW))
	return i if i >= 0 and i < slices.size() else -1

func _get_tooltip(at_position: Vector2) -> String:
	var i := legend_row_at(at_position)
	if i < 0:
		return ""
	var key := String((slices[i] as Dictionary).get("dimension", ""))
	return ResourceIcon.tooltip_of(key) if key != "" else ""

func set_slices(new_slices: Array) -> void:
	slices = new_slices
	custom_minimum_size = Vector2(0, maxf(HEIGHT, LEGEND_ROW * slices.size()))
	queue_redraw()

func total() -> float:
	var t := 0.0
	for s in slices:
		t += maxf(float(s.get("value", 0.0)), 0.0)
	return t

func _draw() -> void:
	var font := get_theme_default_font()
	var t := total()
	var c := Vector2(RADIUS + 2.0, size.y / 2.0)
	if t > 0.0:
		var start := -PI / 2.0
		for s in slices:
			var frac := maxf(float(s.get("value", 0.0)), 0.0) / t
			if frac <= 0.0:
				continue
			var sweep := TAU * frac
			var pts := PackedVector2Array([c])
			var steps := maxi(3, int(ceil(sweep / (TAU / 48.0))))
			for i in steps + 1:
				pts.append(c + Vector2.from_angle(start + sweep * i / steps) * RADIUS)
			draw_colored_polygon(pts, s.get("color", UiPalette.GOLD))
			start += sweep
		# A hairline ring in the panel colour separates the slices (the 2px
		# surface gap of the mark rules, at this size).
		draw_arc(c, RADIUS, 0.0, TAU, 48, UiPalette.PANEL_BG, 1.6, true)
	if font == null:
		return
	for i in slices.size():
		var s: Dictionary = slices[i]
		var y := 8.0 + LEGEND_ROW * i
		draw_rect(Rect2(LEGEND_X, y - 1.0, 10.0, 10.0), s.get("color", UiPalette.GOLD))
		var pct := 0.0 if t <= 0.0 else 100.0 * maxf(float(s.get("value", 0.0)), 0.0) / t
		var dimension := String(s.get("dimension", ""))
		if dimension != "":
			# The swatch keeps colour and slice together; the art says which.
			ResourceIcon.draw_icon(self, dimension, Vector2(LEGEND_X + 16.0 + ICON_PX / 2.0, y + 4.0),
				ICON_PX, UiPalette.GOLD)
			var x := LEGEND_X + 20.0 + ICON_PX
			if named:
				var word := String(s.get("label", ""))
				draw_string(font, Vector2(x, y + 9.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.ink("muted"))
				x += font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 6.0
			draw_string(font, Vector2(x, y + 9.0), "%d%%" % roundi(pct),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.ink("soft"))
		else:
			draw_string(font, Vector2(LEGEND_X + 16.0, y + 9.0),
				"%s %d%%" % [String(s.get("label", "")), roundi(pct)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.ink("soft"))
