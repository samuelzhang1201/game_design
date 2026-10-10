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
var fine := false    # the fine print (WarFinePrint), not the sheet's ink
var plan := false    # the staff's plan layer (WarPlanInk), drawn by WarPlanDraw with `look`
var look: Dictionary = {}


func paint(p_ink: Dictionary, p_pal: Dictionary, p_px: Dictionary, p_font: Font, as_intel := false, as_fine := false) -> void:
	intel = as_intel
	fine = as_fine
	plan = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_PARENT_NODE
	ink = p_ink
	pal = p_pal
	px = p_px
	font = p_font
	queue_redraw()


## The plan layer: WarPlanInk's parts drawn with `p_look` (WarPlanDraw.paint).
func paint_plan(p_ink: Dictionary, p_look: Dictionary) -> void:
	intel = false
	fine = false
	plan = true
	ink = p_ink
	look = p_look
	# the tooth's UVs run past 1 across a stroke: it tiles (a sampling rule, not a look)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()


func _draw() -> void:
	if plan:
		WarPlanDraw.paint(self, ink, look)
		return
	if ink.is_empty():
		return
	if intel:
		_draw_intel()
		return
	if fine:
		_draw_fine()
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
	for rv: Dictionary in ink["rivers"]:   # one tapered stroke from source to mouth, named along its course
		_draw_river(rv, pal["river_ink"])
		_name_river(rv, pal["river_ink"])
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
	for tr: Dictionary in ink.get("trade", []):   # a trade road weighs more, by tier (spec P3 §1.3); a trail stays dashed
		if String(tr.get("kind", "road")) == "trail":   # a pale band under the trail's own dashes
			var band := c_ink
			band.a *= 0.35
			draw_polyline(tr["poly"], band, float(px["trail"]) + float(px.get("trade", 0.0)) * float(int(tr["tier"])) * 1.5, true)
		else:
			draw_polyline(tr["poly"], c_ink, float(px["road"]) + float(px.get("trade", 0.0)) * float(int(tr["tier"])), true)
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
		# a works' glyph above, a market's scales below, each on a parchment
		# knock-out so a road leaving the town does not run through it
		var ground: Color = pal.get("parchment", pal.get("paper", Color.WHITE))
		if String(t.get("works", "")) != "":
			draw_circle(t["works_at"], float(px.get("works", px["town"])) * 0.6, ground)
			WarMarkGlyph.draw(self, String(t["works"]), t["works_at"], float(px.get("works", px["town"])), c_ink)
		if bool(t.get("market", false)):
			draw_circle(t["market_at"], float(px.get("market", px["town"])) * 0.6, ground)
			WarMarkGlyph.draw(self, "scales", t["market_at"], float(px.get("market", px["town"])), c_ink)
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
	for p: Dictionary in ink.get("places", []):   # the map's marks; a brigand's reach a dotted rubric ring
		var hr := float(p["hazard_r"])
		var hazard_c: Color = pal.get("hazard_ink", pal["rubric"])
		var glyph_c: Color = hazard_c if hr > 0.0 else c_ink
		if hr > 0.0:
			var ring_c: Color = hazard_c
			ring_c.a = float(px["mark_reach_alpha"])
			var ring := PackedVector2Array()
			for i in 65:
				ring.append((p.get("ring_at", p["at"]) as Vector2) + Vector2.from_angle(TAU * float(i) / 64.0) * hr)
			for d: PackedVector2Array in WarSheetInk.dashed(ring, float(px["dash"]) * 0.3, float(px["gap"])):
				draw_polyline(d, ring_c, float(px.get("mark_reach", px["seam"])), true)
		WarMarkGlyph.draw(self, String(p["glyph"]), p["at"], float(px["mark"]), glyph_c)
	_draw_hollows(c_ink)
	_draw_graticule(c_ink)


## A river as ONE continuous ribbon (owner 2026-10-07: no stiff segments, no
## visible joints): its half-width swells with the length run from the source
## (w0) to the mouth (w1), each point offset along the bisector of its two
## legs, the edges feathered to clear over war_ink_river_feather_px so the
## triangles are as smooth as an antialiased line.
func _draw_river(rv: Dictionary, color: Color) -> void:
	var poly: PackedVector2Array = rv["poly"]
	var n := poly.size()
	if n < 2:
		return
	var arc := _arc(poly)
	var total := maxf(arc[n - 1], 0.001)
	var feather := float(px.get("river_feather", 1.0))
	var clear := color
	clear.a = 0.0
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var dir := Vector2.ZERO
		if i > 0:
			dir += (poly[i] - poly[i - 1]).normalized()
		if i < n - 1:
			dir += (poly[i + 1] - poly[i]).normalized()
		var nrm := (dir.normalized() if dir.length_squared() > 0.0 else Vector2.RIGHT).orthogonal()
		var t := lerpf(float(rv.get("t0", 0.0)), float(rv.get("t1", 1.0)), arc[i] / total)   # along the whole course
		var h := lerpf(float(rv["w0"]), float(rv["w1"]), t) * 0.5
		for off: float in [h + feather, h, -h, -h - feather]:
			pts.append(poly[i] + nrm * off)
		cols.append_array([clear, color, color, clear])
	for i in n - 1:
		var a := i * 4
		for band in 3:   # feather, core, feather
			idx.append_array([a + band, a + band + 1, a + 4 + band, a + band + 1, a + 5 + band, a + 4 + band])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)


## A river's name written ALONG its course, letter by letter, on its upper side
## and reading left to right, over the middle of its longest stretch on the
## sheet (WarSheetInk.longest_run); the baseline follows the course averaged
## over a few letters, so it bends with the river but not with every meander.
func _name_river(rv: Dictionary, color: Color) -> void:
	var text := String(rv["label"])
	var run: Vector2i = rv.get("label_run", Vector2i(0, -1))
	if text == "" or run.y <= run.x:
		return
	var size := int(px["river_label"])
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var line := (rv["poly"] as PackedVector2Array).slice(run.x, run.y + 1)
	var arc := _arc(line)
	var total := arc[arc.size() - 1]
	if total < width * 1.3:
		return   # too little of it on the sheet to carry its name
	# the baseline: points every half letter over the name's span, averaged
	var step := float(size) * 0.5
	var s0 := total * 0.5 - width * 0.5 - float(size)
	var raw := PackedVector2Array()
	var at := s0
	while at <= total * 0.5 + width * 0.5 + float(size):
		raw.append(_point_at(line, arc, at))
		at += step
	var base := PackedVector2Array()
	for i in raw.size():
		var sum := Vector2.ZERO
		var c := 0
		for j in range(maxi(0, i - 3), mini(raw.size(), i + 4)):
			sum += raw[j]
			c += 1
		base.append(sum / float(c))
	if base[base.size() - 1].x < base[0].x:
		base.reverse()   # never upside down
	var barc := _arc(base)
	var lift := float(rv["w1"]) * 0.5 + float(size) * float(px.get("river_label_lift", 0.35))
	var halo: Color = pal.get("parchment", pal.get("paper", Color.WHITE))
	halo.a = 0.6
	var pos := (barc[barc.size() - 1] - width) * 0.5
	for i in text.length():
		var ch := text.substr(i, 1)
		var adv := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var mid := pos + adv * 0.5
		var tangent := (_point_at(base, barc, mid + step) - _point_at(base, barc, mid - step)).normalized()
		draw_set_transform(_point_at(base, barc, mid) + tangent.orthogonal() * lift, tangent.angle(), Vector2.ONE)
		draw_char_outline(font, Vector2(-adv * 0.5, 0.0), ch, size, maxi(int(float(size) * 0.15), 1), halo)
		draw_char(font, Vector2(-adv * 0.5, 0.0), ch, size, color)
		pos += adv
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The length run along `poly` to each of its points.
static func _arc(poly: PackedVector2Array) -> PackedFloat32Array:
	var arc := PackedFloat32Array()
	arc.resize(poly.size())
	for i in range(1, poly.size()):
		arc[i] = arc[i - 1] + poly[i].distance_to(poly[i - 1])
	return arc


## The point `s` along `poly` (held to its ends).
static func _point_at(poly: PackedVector2Array, arc: PackedFloat32Array, s: float) -> Vector2:
	if s <= 0.0:
		return poly[0]
	var i := arc.bsearch(s)
	if i >= poly.size():
		return poly[poly.size() - 1]
	var span := arc[i] - arc[i - 1]
	return poly[i - 1].lerp(poly[i], (s - arc[i - 1]) / span if span > 0.0 else 0.0)


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


## What we know (WarIntelInk), in the intel ink: couriers with their road ahead and a pennon (a spy's
## in rubric), weather marks, spy reports as dashed rings with their words.
func _draw_intel() -> void:
	var c: Color = pal["intel_ink"]
	var hz_c: Color = pal["intel_ink"]
	hz_c.a *= float(px.get("hazard_alpha", 0.5))
	for h: Dictionary in ink.get("hazards", []):
		var w := float(px.get("hazard", 3.0))
		for l: PackedVector2Array in h["lines"]:
			if String(h["ink"]) == "rock":
				for d: PackedVector2Array in WarSheetInk.dashed(l, w * 4.0, w * 3.0):
					draw_polyline(d, hz_c, w, true)
			else:
				draw_polyline(l, hz_c, w, true)
		for p: Vector2 in h["dots"]:
			draw_circle(p, w * 1.6, hz_c)
		for e: PackedVector2Array in h["edges"]:
			for d: PackedVector2Array in WarSheetInk.dashed(e, float(px["supply_dash"]), float(px["supply_gap"])):
				draw_polyline(d, pal["intel_ink"], w, true)
		var size := int(px.get("hazard_label", px["intel_label"]))
		var at := (h["at"] as Vector2) - Vector2(font.get_string_size(String(h["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5, 0)
		draw_string_outline(font, at, String(h["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(int(w * 3.0), 1),
			pal.get("parchment", pal.get("paper", Color.WHITE)))
		draw_string(font, at, String(h["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, pal["intel_ink"])
	for st: Dictionary in ink.get("stripped", []):
		var size := int(px["intel_label"])
		var at := (st["at"] as Vector2) - Vector2(font.get_string_size(String(st["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5, 0)
		draw_string_outline(font, at, String(st["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(int(float(px.get("hazard", 3.0)) * 3.0), 1),
			pal.get("parchment", pal.get("paper", Color.WHITE)))
		draw_string(font, at, String(st["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
	for cr: Dictionary in ink["couriers"]:
		for d: PackedVector2Array in WarSheetInk.dashed(cr["poly"], float(px["supply_dash"]) / 1.5, float(px["supply_gap"])):
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


## The fine print (WarFinePrint): notes and route names in faint ink, minor
## heights as small marks, contour figures in rubric, each turned to its angle.
func _draw_fine() -> void:
	var c_ink: Color = pal["ink"]
	var c_faint: Color = pal["ink_faint"]
	var c_fig: Color = pal.get("contour_figure", pal["rubric"])
	for n: Dictionary in ink["notes"]:
		draw_string(font, n["at"], String(n["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["note"]), c_ink)
	for r: Dictionary in ink["routes"]:
		_turned_text(r["at"], float(r["angle"]), String(r["text"]), int(px["route"]), c_ink)
	for m: Dictionary in ink["marks"]:
		var at: Vector2 = m["at"]
		var s := float(px["mark"])
		var pts := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s * 0.9, s * 0.6), at + Vector2(-s * 0.9, s * 0.6)])
		if String(m["kind"]) == "high":
			draw_colored_polygon(pts, c_faint)
		else:
			pts = PackedVector2Array([at + Vector2(-s * 0.9, -s * 0.6), at + Vector2(s * 0.9, -s * 0.6), at + Vector2(0, s), at + Vector2(-s * 0.9, -s * 0.6)])
			draw_polyline(pts, c_faint, maxf(s * 0.2, 1.0), true)
		draw_string(font, at + Vector2(s * 1.4, s * 0.5), "%d m" % int(m["metres"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["note"]), c_faint)
	for f: Dictionary in ink["figures"]:
		_turned_text(f["at"], float(f["angle"]), String(f["text"]), int(px["figure"]), c_fig)
	for p: Dictionary in ink.get("places", []):
		if String(p["glyph"]) != "":
			WarMarkGlyph.draw(self, String(p["glyph"]), p["at"], float(px["mark"]), c_faint)
		draw_string(font, p["label_at"], String(p["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["note"]), c_faint)


## Text centred on `at`, turned by `angle`, on a parchment knock-out so the
## line under it does not run through the figure.
func _turned_text(at: Vector2, angle: float, text: String, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_set_transform(at, angle, Vector2.ONE)
	var ground: Color = pal.get("parchment", pal.get("paper", Color.WHITE))
	ground.a = 0.6
	draw_rect(Rect2(Vector2(-w * 0.5 - 2.0, -float(size) * 0.8), Vector2(w + 4.0, float(size))), ground)
	draw_string(font, Vector2(-w * 0.5, float(size) * 0.1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
