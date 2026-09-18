class_name ScaleBar
extends RefCounted
## The scale bar both maps draw in their bottom-right corner (library M-14):
## alternating filled and open segments under a bracketing line, the
## distance right-aligned above it, in terrain_palette scale_bar ink.
## `bar` is {width_px, text}; `area` the drawing's size in its own px.
##
## `halo` (fix round 1, owner 2026-09-18): with alpha > 0, every stroke is
## laid first 2 px wider in this colour and the label gets a matching
## draw_string_outline, so the bar reads over bright ground (snow, sea) the
## way the 2D map never needed to. The 2D map passes nothing, so it stays
## pixel-identical to before this fix.
static func draw(ci: CanvasItem, bar: Dictionary, area: Vector2,
		halo: Color = Color(0, 0, 0, 0)) -> void:
	if bar.is_empty():
		return
	var color := MapTerrain.palette_color(Game.data, "scale_bar", MapTerrain.FALLBACK)
	color.a = Game.data.bal("map_scale_bar_alpha")
	if color.a <= 0.0:
		return
	var glow := halo if halo.a > 0.0 else Color(0, 0, 0, 0)
	var w: float = bar["width_px"]
	var h := Game.data.bal("map_scale_bar_height_px")
	var margin := Game.data.bal("map_scale_bar_margin_px")
	var right := area.x - margin
	var bottom := area.y - margin
	var left := right - w
	var top := bottom - h
	var divisions := maxi(int(Game.data.bal("map_scale_bar_divisions")), 1)
	var step := w / float(divisions)
	for i in divisions:
		if i % 2 == 0:
			var seg := Rect2(Vector2(left + step * i, top), Vector2(step, h))
			if glow.a > 0.0:
				ci.draw_rect(seg.grow(1.0), glow, true)
			ci.draw_rect(seg, color, true)
	if glow.a > 0.0:
		ci.draw_rect(Rect2(Vector2(left, top), Vector2(w, h)), glow, false, 4.0)
	ci.draw_rect(Rect2(Vector2(left, top), Vector2(w, h)), color, false, 2.0)
	var brow := top - 6.0
	_stroke(ci, Vector2(left, brow), Vector2(right, brow), color, glow)
	_stroke(ci, Vector2(left, brow), Vector2(left, top), color, glow)
	_stroke(ci, Vector2(right, brow), Vector2(right, top), color, glow)
	var font := UiPalette.display_font()
	if font == null:
		return
	var font_px := int(Game.data.bal("map_scale_bar_font_px"))
	var text := String(bar["text"])
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var pos := Vector2(right - text_w, brow - 6.0)
	if glow.a > 0.0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 4, glow)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)


## A bracket stroke, haloed 2 px wider first when `glow` has alpha.
static func _stroke(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, glow: Color) -> void:
	if glow.a > 0.0:
		ci.draw_line(a, b, glow, 4.0, true)
	ci.draw_line(a, b, color, 2.0, true)


## 500.0 -> "500", 2.5 -> "2.5": a scale bar reads as a number, not a float.
static func trim_zeros(v: float) -> String:
	var s := String.num(v, 2)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s
