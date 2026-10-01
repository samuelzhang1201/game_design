class_name WarInkPainter
extends Node2D
## Draws a sheet's WarSheetInk strokes ONCE into its SubViewport (spec
## 2026-10-01-war-room-design §2): the view reads the texture back and caches
## it by WarSheetInk.cache_key. Clear background: the vellum is the shader's.

var ink: Dictionary = {}
var pal: Dictionary = {}
var px: Dictionary = {}   # the war_ink_* widths, by short key
var font: Font


func paint(p_ink: Dictionary, p_pal: Dictionary, p_px: Dictionary, p_font: Font) -> void:
	ink = p_ink
	pal = p_pal
	px = p_px
	font = p_font
	queue_redraw()


func _draw() -> void:
	if ink.is_empty():
		return
	var c_ink: Color = pal["ink"]
	var c_faint: Color = pal["ink_faint"]
	for b: Dictionary in ink["borders"]:
		var band: Color = (b["color"] as Color)
		band.a = 0.28
		for loop: PackedVector2Array in b["loops"]:
			draw_polyline(_closed(loop), band, float(px["band"]), true)
	for poly: PackedVector2Array in ink["coasts"]:
		draw_polyline(poly, pal["sea_ink"], float(px["coast"]), true)
	for poly: PackedVector2Array in ink["rivers"]:
		draw_polyline(poly, pal["river_ink"], float(px["river"]), true)
	for poly: PackedVector2Array in ink["seams"]:  # fine work: a hairline (the segments arrive two points apiece)
		draw_polyline(poly, c_faint, float(px["seam"]), true)
	for b: Dictionary in ink["borders"]:
		for loop: PackedVector2Array in b["loops"]:
			var parts := WarSheetInk.dashed(_closed(loop), float(px["dash"]), float(px["gap"]))
			for i in parts.size():
				draw_polyline(parts[i], c_ink, float(px["border"]), true)
				if i + 1 < parts.size():  # the dot between dashes
					draw_circle(parts[i][parts[i].size() - 1].lerp(parts[i + 1][0], 0.5), float(px["border"]) * 0.6, c_ink)
	for poly: PackedVector2Array in ink["trails"]:
		for d: PackedVector2Array in WarSheetInk.dashed(poly, float(px["dash"]), float(px["gap"])):
			draw_polyline(d, c_ink, float(px["trail"]), true)
	for poly: PackedVector2Array in ink["roads"]:
		draw_polyline(poly, c_ink, float(px["road"]), true)
	for t: Dictionary in ink["towns"]:
		var r := float(px["town"]) * (1.0 + 0.5 * float(int(t["tier"])))
		draw_arc(t["at"], r, 0.0, TAU, 32, c_ink, float(px["town"]) * 0.33, true)
		if int(t["tier"]) >= 2:
			draw_circle(t["at"], r * 0.35, c_ink)
		draw_string(font, (t["at"] as Vector2) + Vector2(r + float(px["town"]) * 0.66, float(px["label"]) * 0.35), String(t["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["label"]), c_ink)
	for p: Dictionary in ink["peaks"]:
		if int(p.get("lod", 0)) != 0:  # thinned to the most prominent; the strokes list stays whole
			continue
		var at: Vector2 = p["at"]
		var s := float(px["town"])
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(s * 0.9, s * 0.6),
			at + Vector2(-s * 0.9, s * 0.6)]), c_ink)
		draw_string(font, at + Vector2(s + s * 0.44, s * 0.6), "%d m" % int(p["metres"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(float(px["label"]) * 0.7), c_ink)


static func _closed(loop: PackedVector2Array) -> PackedVector2Array:
	var out := loop.duplicate()
	if out.size() > 1 and out[0] != out[out.size() - 1]:
		out.append(out[0])
	return out
