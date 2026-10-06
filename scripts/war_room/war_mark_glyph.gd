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
		"sabre_wave":
			ci.draw_arc(at + Vector2(s * 0.6, -s * 0.1), s * 0.9, PI * 0.95, PI * 1.6, 10, color, w, true)
			var wave := PackedVector2Array()
			for i in 9:
				var x := -s + float(i) * s * 0.25
				wave.append(at + Vector2(x, s * 0.75 + sin(float(i) * PI * 0.5) * s * 0.15))
			ci.draw_polyline(wave, color, w, true)
		"pick":
			ci.draw_arc(at + Vector2(0, s * 0.2), s * 0.9, PI * 1.15, PI * 1.85, 10, color, w * 1.2, true)
			ci.draw_line(at + Vector2(0, -s * 0.7), at + Vector2(0, s), color, w, true)
		"tankard":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.55, -s * 0.6), Vector2(s * 0.9, s * 1.5)), color, false, w, true)
			ci.draw_arc(at + Vector2(s * 0.35, s * 0.1), s * 0.35, -PI * 0.5, PI * 0.5, 8, color, w, true)
		"crossed_flags":
			ci.draw_line(at + Vector2(-s * 0.7, s), at + Vector2(s * 0.5, -s), color, w, true)
			ci.draw_line(at + Vector2(s * 0.7, s), at + Vector2(-s * 0.5, -s), color, w, true)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(s * 0.5, -s), at + Vector2(s, -s * 0.75),
				at + Vector2(s * 0.35, -s * 0.5)]), color)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.5, -s), at + Vector2(-s, -s * 0.75),
				at + Vector2(-s * 0.35, -s * 0.5)]), color)
		"broken_column":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.3, -s * 0.4), Vector2(s * 0.6, s * 1.4)), color, false, w, true)
			ci.draw_polyline(PackedVector2Array([at + Vector2(-s * 0.3, -s * 0.4), at + Vector2(-s * 0.05, -s * 0.8),
				at + Vector2(s * 0.1, -s * 0.5), at + Vector2(s * 0.3, -s * 0.7)]), color, w, true)
			ci.draw_line(at + Vector2(-s * 0.6, s), at + Vector2(s * 0.6, s), color, w, true)
		"tower_light":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.35, s), at + Vector2(s * 0.35, s),
				at + Vector2(s * 0.2, -s * 0.4), at + Vector2(-s * 0.2, -s * 0.4)]), color)
			for a in [-0.35, 0.0, 0.35]:
				var d := Vector2.from_angle(-PI * 0.5 + a)
				ci.draw_line(at + Vector2(0, -s * 0.6) + d * s * 0.2, at + Vector2(0, -s * 0.6) + d * s * 0.55, color, w * 0.8, true)
		_:
			ci.draw_circle(at, s * 0.3, color)
