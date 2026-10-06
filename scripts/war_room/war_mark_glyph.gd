class_name WarMarkGlyph
extends RefCounted
## One map mark's glyph, drawn in ink on any CanvasItem (the sheet's painter,
## the key slip) — spec 2026-10-07-war-room-p2-tactical-layer §1.3. `size` is
## the glyph's height; every stroke scales with it. WarMarks.GLYPHS lists the
## names the data may use.


static func knows(glyph: String) -> bool:
	return WarMarks.GLYPHS.has(glyph)


static func draw(ci: CanvasItem, glyph: String, at: Vector2, size: float, color: Color) -> void:
	var s := size * 0.5
	var w := maxf(size * 0.09, 1.0)
	match glyph:
		"crossed_swords":
			ci.draw_line(at + Vector2(-s, s), at + Vector2(s, -s), color, w, true)
			ci.draw_line(at + Vector2(s, s), at + Vector2(-s, -s), color, w, true)
			ci.draw_line(at + Vector2(-s * 0.75, s * 0.35), at + Vector2(-s * 0.35, s * 0.75), color, w, true)
			ci.draw_line(at + Vector2(s * 0.75, s * 0.35), at + Vector2(s * 0.35, s * 0.75), color, w, true)
		"galley":   # a raider's ship on the water: hull, mast and a lateen sail
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s, s * 0.2), at + Vector2(s, s * 0.2),
				at + Vector2(s * 0.65, s * 0.55), at + Vector2(-s * 0.7, s * 0.55)]), color)
			ci.draw_line(at + Vector2(-s * 0.1, s * 0.2), at + Vector2(-s * 0.1, -s * 0.8), color, w, true)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.85, s * 0.05), at + Vector2(s * 0.5, -s),
				at + Vector2(s * 0.45, s * 0.05)]), color)
			var wave := PackedVector2Array()
			for i in 9:
				wave.append(at + Vector2(-s + float(i) * s * 0.25, s * 0.85 + sin(float(i) * PI * 0.5) * s * 0.1))
			ci.draw_polyline(wave, color, w, true)
		"pick":   # a mine: pick and hammer crossed
			ci.draw_line(at + Vector2(-s * 0.8, s * 0.9), at + Vector2(s * 0.6, -s * 0.6), color, w, true)
			ci.draw_arc(at + Vector2(s * 0.75, -s * 0.75) + Vector2(-s * 0.5, s * 0.5), s * 0.75, -PI * 0.95, -PI * 0.05, 10, color, w * 1.3, true)
			ci.draw_line(at + Vector2(s * 0.8, s * 0.9), at + Vector2(-s * 0.55, -s * 0.55), color, w, true)
			ci.draw_rect(Rect2(at + Vector2(-s * 0.95, -s * 0.95), Vector2(s * 0.7, s * 0.45)), color, true)
		"tankard":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.55, -s * 0.6), Vector2(s * 0.9, s * 1.5)), color, false, w, true)
			ci.draw_arc(at + Vector2(s * 0.35, s * 0.1), s * 0.35, -PI * 0.5, PI * 0.5, 8, color, w, true)
		"pennon":   # an old battlefield: a pennon on its staff over a mound
			ci.draw_line(at + Vector2(-s * 0.3, s * 0.8), at + Vector2(-s * 0.3, -s), color, w, true)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.3, -s), at + Vector2(s * 0.9, -s * 0.65),
				at + Vector2(-s * 0.3, -s * 0.3)]), color)
			ci.draw_arc(at + Vector2(0, s * 1.4), s * 0.9, PI * 1.2, PI * 1.8, 10, color, w, true)
		"broken_column":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.3, -s * 0.4), Vector2(s * 0.6, s * 1.4)), color, false, w, true)
			ci.draw_polyline(PackedVector2Array([at + Vector2(-s * 0.3, -s * 0.4), at + Vector2(-s * 0.05, -s * 0.8),
				at + Vector2(s * 0.1, -s * 0.5), at + Vector2(s * 0.3, -s * 0.7)]), color, w, true)
			ci.draw_line(at + Vector2(-s * 0.6, s), at + Vector2(s * 0.6, s), color, w, true)
		"tower_light":   # a lighthouse: a tapering tower, its lantern and the beams
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.4, s), at + Vector2(s * 0.4, s),
				at + Vector2(s * 0.22, -s * 0.25), at + Vector2(-s * 0.22, -s * 0.25)]), color)
			ci.draw_rect(Rect2(at + Vector2(-s * 0.28, -s * 0.6), Vector2(s * 0.56, s * 0.3)), color, false, w, true)
			ci.draw_line(at + Vector2(-s * 0.35, -s * 0.62), at + Vector2(s * 0.35, -s * 0.62), color, w, true)
			for a in [-1.0, 1.0]:
				ci.draw_line(at + Vector2(s * 0.35 * a, -s * 0.45), at + Vector2(s * 1.0 * a, -s * 0.7), color, w * 0.8, true)
				ci.draw_line(at + Vector2(s * 0.35 * a, -s * 0.45), at + Vector2(s * 1.0 * a, -s * 0.25), color, w * 0.8, true)
		_:
			ci.draw_circle(at, s * 0.3, color)
