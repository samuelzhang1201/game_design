class_name WarInkPainter
extends Node2D
## Draws a sheet's WarSheetInk strokes ONCE into its SubViewport (spec
## 2026-10-01-war-room-design §2): the view reads the texture back and caches
## it by WarSheetInk.cache_key. Clear background: the vellum is the shader's.

var ink: Dictionary = {}
var pal: Dictionary = {}
var px: Dictionary = {}   # the war_ink_* widths and ratios, by short key
var font: Font
var intel := false   # the intelligence layer (WarIntelInk), not the sheet's ink


func paint(p_ink: Dictionary, p_pal: Dictionary, p_px: Dictionary, p_font: Font, as_intel := false) -> void:
	intel = as_intel
	ink = p_ink
	pal = p_pal
	px = p_px
	font = p_font
	queue_redraw()


func _draw() -> void:
	if ink.is_empty():
		return
	if intel:
		_draw_intel()
		return
	var c_ink: Color = pal["ink"]
	var c_faint: Color = pal["ink_faint"]
	for b: Dictionary in ink["borders"]:
		var band: Color = (b["color"] as Color)
		band.a = float(px["band_alpha"])
		for loop: PackedVector2Array in b["loops"]:
			draw_polyline(_closed(loop), band, float(px["band"]), true)
	for poly: PackedVector2Array in ink["coasts"]:
		draw_polyline(poly, pal["sea_ink"], float(px["coast"]), true)
	for rv: Dictionary in ink["rivers"]:   # widening from source to mouth, and named
		var poly: PackedVector2Array = rv["poly"]
		var n := poly.size()
		for i in n - 1:
			var w := lerpf(float(rv["w0"]), float(rv["w1"]), float(i) / float(maxi(n - 2, 1)))
			draw_line(poly[i], poly[i + 1], pal["river_ink"], w, true)
		if String(rv["label"]) != "" and n >= 2:
			@warning_ignore("integer_division")
			var mid := poly[n / 2]
			draw_string(font, mid + Vector2(float(px["river_label"]) * 0.4, -float(px["river_label"]) * 0.3), String(rv["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["river_label"]), pal["river_ink"])
	for poly: PackedVector2Array in ink["seams"]:  # fine work: a hairline (the segments arrive two points apiece)
		draw_polyline(poly, c_faint, float(px["seam"]), true)
	for b: Dictionary in ink["borders"]:
		for loop: PackedVector2Array in b["loops"]:
			var parts := WarSheetInk.dashed(_closed(loop), float(px["dash"]), float(px["gap"]))
			for i in parts.size():
				draw_polyline(parts[i], c_ink, float(px["border"]), true)
				if i + 1 < parts.size():  # the dot between dashes
					draw_circle(parts[i][parts[i].size() - 1].lerp(parts[i + 1][0], 0.5), float(px["border"]) * float(px["border_dot_ratio"]), c_ink)
	var c_wood: Color = pal.get("wood_ink", c_faint)
	for wd: Dictionary in ink.get("woods", []):
		var wat: Vector2 = wd["at"]
		var ws := float(px["wood"])
		if bool(wd["conifer"]):
			draw_colored_polygon(PackedVector2Array([wat + Vector2(0, -ws), wat + Vector2(ws * 0.55, ws * 0.35), wat + Vector2(-ws * 0.55, ws * 0.35)]), c_wood)
		else:
			draw_circle(wat + Vector2(0, -ws * 0.25), ws * 0.5, c_wood)
		draw_line(wat + Vector2(0, ws * 0.2), wat + Vector2(0, ws * 0.6), c_wood, maxf(ws * 0.15, 1.0), true)
	for e: PackedVector2Array in ink.get("manor_edges", []):
		for d: PackedVector2Array in WarSheetInk.dashed(e, float(px["manor_dash"]), float(px["manor_gap"])):
			draw_polyline(d, c_faint, float(px["manor"]), true)
	for mn: Dictionary in ink.get("manors", []):
		var mw := float(String(mn["label"]).length()) * float(px["manor_label"]) * float(px["char_w"])
		draw_string(font, (mn["at"] as Vector2) + Vector2(-mw * 0.5, float(px["manor_label"]) * 0.35), String(mn["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["manor_label"]), c_faint)
	for poly: PackedVector2Array in ink["trails"]:
		for d: PackedVector2Array in WarSheetInk.dashed(poly, float(px["dash"]), float(px["gap"])):
			draw_polyline(d, c_ink, float(px["trail"]), true)
	for poly: PackedVector2Array in ink["roads"]:
		draw_polyline(poly, c_ink, float(px["road"]), true)
	for br: Dictionary in ink.get("bridges", []):   # two parapets across the river
		var at: Vector2 = br["at"]
		var along: Vector2 = br["dir"]
		var across := along.orthogonal()
		var bs := float(px["bridge"])
		for side in [-1.0, 1.0]:
			draw_line(at + across * bs * 0.5 * side - along * bs, at + across * bs * 0.5 * side + along * bs, c_ink, maxf(bs * 0.25, 1.0), true)
	for fd: Dictionary in ink.get("fords", []):   # a dashed bar across the water
		var at: Vector2 = fd["at"]
		var across := (fd["dir"] as Vector2).orthogonal()
		var bs := float(px["bridge"])
		for d: PackedVector2Array in WarSheetInk.dashed(PackedVector2Array([at - across * bs, at + across * bs]), bs * 0.35, bs * 0.3):
			draw_polyline(d, c_ink, maxf(bs * 0.2, 1.0), true)
	for t: Dictionary in ink["towns"]:
		var r := float(px["town"]) * (1.0 + float(px["town_tier_growth"]) * float(int(t["tier"])))
		draw_arc(t["at"], r, 0.0, TAU, 32, c_ink, float(px["town"]) * float(px["town_ring_ratio"]), true)
		if int(t["tier"]) >= 2:
			draw_circle(t["at"], r * float(px["town_dot_ratio"]), c_ink)
		var ring_w := float(px["town"]) * float(px["town_ring_ratio"])
		if bool(t.get("walls", false)):
			var wr := r * float(px["wall_ratio"])
			var tc: Vector2 = t["at"]
			draw_rect(Rect2(tc - Vector2(wr, wr), Vector2(wr, wr) * 2.0), c_ink, false, ring_w, true)
			for q in 4:   # a tower at each corner
				var corner := tc + Vector2(wr if q % 2 == 0 else -wr, wr if q < 2 else -wr)
				draw_rect(Rect2(corner - Vector2.ONE * wr * 0.22, Vector2.ONE * wr * 0.44), c_ink)
		if bool(t.get("port", false)):
			var an := (t["at"] as Vector2) + Vector2(-r * 2.2, 0.0)
			var aa := r * float(px["anchor_ratio"])
			var aw := maxf(aa * 0.16, 1.0)
			draw_line(an + Vector2(0, -aa), an + Vector2(0, aa), c_ink, aw, true)
			draw_line(an + Vector2(-aa * 0.45, -aa * 0.55), an + Vector2(aa * 0.45, -aa * 0.55), c_ink, aw, true)
			draw_arc(an + Vector2(0, aa * 0.2), aa * 0.75, 0.15 * PI, 0.85 * PI, 10, c_ink, aw, true)
		draw_string(font, (t["at"] as Vector2) + Vector2(r + float(px["town"]) * float(px["label_gap_ratio"]),
			float(px["label"]) * float(px["label_drop_ratio"])), String(t["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["label"]), c_ink)
	for p: Dictionary in ink["peaks"]:
		if int(p.get("lod", 0)) != 0:  # thinned to the most prominent; the strokes list stays whole
			continue
		var at: Vector2 = p["at"]
		var s := float(px["town"])
		var hw := s * float(px["peak_half_w"])
		var drop := s * float(px["peak_drop"])
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(hw, drop), at + Vector2(-hw, drop)]), c_ink)
		draw_string(font, at + Vector2(hw + s * float(px["label_gap_ratio"]), drop), "%d m" % int(p["metres"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(float(px["label"]) * float(px["peak_label_ratio"])), c_ink)
	_draw_hollows(c_ink)
	_draw_graticule(c_ink)


## The meridians' and parallels' figures inside the neat line: a meridian's
## beside its line (the line never runs through the figure), a parallel's
## just above its line, each set in from its own edge.
func _draw_graticule(_c_ink: Color) -> void:
	var c_fig: Color = pal.get("rubric", _c_ink)
	var ground: Color = pal.get("parchment", pal.get("paper", Color.WHITE))
	ground.a = 0.6
	for g: Dictionary in ink.get("graticule", []):
		var fs := int(g["size"])
		var text := String(g["text"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at: Vector2 = g["at"]
		var gap := float(fs) * 0.25
		var pos := at
		match String(g["side"]):
			"n":
				pos = at + Vector2(gap, float(fs) * 0.85)
			"s":
				pos = at + Vector2(gap, -float(fs) * 0.2)
			"w":
				pos = at + Vector2(0.0, -gap)
			"e":
				pos = at + Vector2(-tw, -gap)
		# a parchment knock-out, so no line runs through the figure
		draw_rect(Rect2(pos + Vector2(-gap * 0.4, -float(fs) * 0.78), Vector2(tw + gap * 0.8, float(fs) * 0.98)), ground)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c_fig)


## What we know (WarIntelInk), in the intel ink: supply roads dashed and
## fading with their loss, couriers with their road ahead and a pennon (a spy's
## in rubric), weather marks, spy reports as dashed rings with their words.
func _draw_intel() -> void:
	var c: Color = pal["intel_ink"]
	for s: Dictionary in ink["supply"]:
		var col := c
		col.a *= clampf(1.0 - float(s["loss_permille"]) / 1000.0 * float(px["supply_loss_fade"]), 0.25, 1.0)
		for d: PackedVector2Array in WarSheetInk.dashed(s["poly"], float(px["supply_dash"]), float(px["supply_gap"])):
			draw_polyline(d, col, float(px["supply"]), true)
	for cr: Dictionary in ink["couriers"]:
		for d: PackedVector2Array in WarSheetInk.dashed(cr["poly"], 2.0, float(px["supply_gap"])):
			draw_polyline(d, c, float(px["supply"]) * 0.7, true)
		var at: Vector2 = cr["at"]
		var s := float(px["courier"])
		draw_circle(at, s * 0.5, c)
		draw_line(at, at + Vector2(0, -s * 1.3), c, maxf(s * 0.15, 1.0), true)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.3), at + Vector2(s * 0.8, -s * 1.1), at + Vector2(0, -s * 0.9)]),
			pal["rubric"] if bool(cr["spy"]) else c)
	for w: Dictionary in ink["weather"]:
		var at: Vector2 = w["at"]
		var s := float(px["weather"])
		var lw := maxf(s * 0.1, 1.0)
		if float(w["overcast"]) >= 0.5:
			draw_arc(at + Vector2(-s * 0.3, 0), s * 0.45, PI, TAU, 10, c, lw, true)
			draw_arc(at + Vector2(s * 0.3, -s * 0.1), s * 0.55, PI, TAU, 10, c, lw, true)
		for i in int(round(float(w["rain"]) * 3.0)):
			var x := -s * 0.4 + float(i) * s * 0.4
			draw_line(at + Vector2(x, s * 0.2), at + Vector2(x - s * 0.15, s * 0.7), c, lw, true)
		if float(w["snow"]) > 0.0:
			for a in 3:
				var dir := Vector2.from_angle(float(a) * PI / 3.0) * s * 0.35
				draw_line(at + Vector2(0, s * 0.45) - dir, at + Vector2(0, s * 0.45) + dir, c, lw, true)
	for sp: Dictionary in ink["spies"]:
		var at: Vector2 = sp["at"]
		var ring := PackedVector2Array()
		for i in 49:
			ring.append(at + Vector2.from_angle(TAU * float(i) / 48.0) * float(sp["radius"]))
		for d: PackedVector2Array in WarSheetInk.dashed(ring, float(px["supply_dash"]), float(px["supply_gap"])):
			draw_polyline(d, pal["rubric"], float(px["supply"]), true)
		draw_string(font, at + Vector2(float(sp["radius"]) + 4.0, 0), String(sp["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["intel_label"]), pal["rubric"])


## The hollows: a ▽ outlined, with its depth.
func _draw_hollows(c_ink: Color) -> void:
	for p: Dictionary in ink.get("hollows", []):
		if int(p.get("lod", 0)) != 0:
			continue
		var at: Vector2 = p["at"]
		var s := float(px["town"])
		var hw := s * float(px["peak_half_w"])
		var drop := s * float(px["peak_drop"])
		draw_polyline(PackedVector2Array([at + Vector2(-hw, -drop), at + Vector2(hw, -drop), at + Vector2(0, s), at + Vector2(-hw, -drop)]),
			c_ink, maxf(s * 0.12, 1.0), true)
		draw_string(font, at + Vector2(hw + s * float(px["label_gap_ratio"]), drop), "%d m" % int(p["metres"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(float(px["label"]) * float(px["peak_label_ratio"])), c_ink)


static func _closed(loop: PackedVector2Array) -> PackedVector2Array:
	var out := loop.duplicate()
	if out.size() > 1 and out[0] != out[out.size() - 1]:
		out.append(out[0])
	return out
