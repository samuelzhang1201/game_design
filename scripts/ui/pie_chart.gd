class_name PieChart
extends Control
## A small pie for a part-to-whole with a few slices: the disc on the left,
## a legend of swatch + label + value on the right so no reading depends on
## colour alone. slices = [{label, value, color}].

const HEIGHT := 60.0
const RADIUS := 26.0
const LEGEND_X := 64.0

var slices: Array = []

func set_slices(new_slices: Array) -> void:
	slices = new_slices
	custom_minimum_size = Vector2(0, maxf(HEIGHT, 18.0 * slices.size()))
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
		var y := 8.0 + 18.0 * i
		draw_rect(Rect2(LEGEND_X, y - 1.0, 10.0, 10.0), s.get("color", UiPalette.GOLD))
		var pct := 0.0 if t <= 0.0 else 100.0 * maxf(float(s.get("value", 0.0)), 0.0) / t
		draw_string(font, Vector2(LEGEND_X + 16.0, y + 9.0),
			"%s %d%%" % [String(s.get("label", "")), roundi(pct)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiPalette.TEXT_SOFT)
