class_name WarSheetInk
extends RefCounted
## What is inked on a laid sheet (owner 2026-10-01, spec 2026-10-01-war-room-design
## §2), in TEXTURE px — tex_px across the sheet's width, its height at the same
## scale — so WarInkPainter only draws. Roads solid, trails dashed, rivers in
## blue ink, the coast, each kingdom's LIVE outline (MapOwnership), the province
## seams, towns by tier with names, peaks with heights; since v2 B (spec
## 2026-10-02-war-room-v2 §2.4) hollows, woods from the build's canopy
## (WarBake), the manors' own edges and names, walled towns and ports.
## Contours and the grid are the shader's, not here.

## A burg's `group` column to its tier (capital 3, city 2, town / fort 1, village 0).
const TOWN_TIERS := {"village": 0, "town": 1, "fort": 1, "city": 2, "capital": 3}


static func cache_key(state: GameState, sheet_index: int) -> int:
	return hash([sheet_index, state.province_owner.hash(), state.manor_province.hash()])


static func _to_tex(r: Rect2, k: float, poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = (poly[i] - r.position) * k
	return out


static func _touches(r: Rect2, poly: PackedVector2Array) -> bool:
	for p in poly:
		if r.has_point(p):
			return true
	return false


## `window` (pack px, empty for the whole sheet): only the strokes touching it,
## in ITS texture's px, every px size scaled with it so a near-zoom patch (spec
## 2026-10-07-war-room-scale-hover §2) keeps the sheet's sizes on the table.
static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int, bake: WarBake = null,
		window := Rect2()) -> Dictionary:
	var r: Rect2 = sheet["rect"] if window.size.x <= 0.0 else window
	var k := float(tex_px) / r.size.x
	# px sizes grow with the window's magnification over the whole sheet's ink
	var px_k := 1.0 if window.size.x <= 0.0 \
		else k / (repo.bal("war_sheet_texture_px") / (sheet["rect"] as Rect2).size.x)
	var out := {"roads": [], "trails": [], "rivers": [], "coasts": [], "borders": [], "seams": [],
		"towns": [], "peaks": [], "hollows": [], "woods": [], "manor_edges": [], "manors": []}
	var route_codes: Array = repo.routes.keys()
	route_codes.sort()
	for code: String in route_codes:
		var row: Dictionary = repo.routes[code]
		var group := String(row.get("group", ""))
		if group != "roads" and group != "trails":
			continue
		var poly: PackedVector2Array = row["polyline"]
		if _touches(r, poly):
			(out[group] as Array).append(_to_tex(r, k, poly))
	var river_codes: Array = repo.rivers.keys()
	river_codes.sort()
	# a river widens from its source to its mouth by its discharge, and is named;
	# its course is the 3D map's own (the build's rivers.json), else the pack's
	# polyline smoothed as the build smooths it (owner 2026-10-07: no stiff,
	# ruler-straight rivers)
	var base_w := repo.bal("war_ink_river_px") * px_k
	var courses: Dictionary = bake.river_courses() if bake != null else {}
	var steps := int(repo.bal("war_ink_river_smooth_steps"))
	var tex_area := Rect2(Vector2.ZERO, r.size * k)
	for code: String in river_codes:
		var row: Dictionary = repo.rivers[code]
		var poly: PackedVector2Array = courses[code] if courses.has(code) \
			else MapGeometry.smooth_open(row["polyline"] as PackedVector2Array, steps)
		if _touches(r, poly):
			var mouth := minf(base_w * (1.0 + repo.bal("war_ink_river_discharge_k") * sqrt(maxf(float(row.get("discharge", "0")), 0.0))),
				repo.bal("war_ink_river_max_px") * px_k)
			var c := river_line(_to_tex(r, k, poly), tex_area, repo.bal("war_ink_river_step_px"))
			if (c["poly"] as PackedVector2Array).size() < 2:
				continue
			(out["rivers"] as Array).append({"poly": c["poly"], "t0": c["t0"], "t1": c["t1"], "w0": base_w,
				"w1": maxf(mouth, base_w), "label": String(row.get("label", "")),
				"label_run": longest_run(c["poly"], tex_area)})
	var river_polys: Array = (out["rivers"] as Array).map(func(rv: Dictionary) -> PackedVector2Array: return rv["poly"])
	var tex_rect := Rect2(Vector2.ZERO, r.size * k).grow(r.size.x * k * 0.02)
	out["bridges"] = crossings(out["roads"], river_polys, tex_rect)
	out["fords"] = crossings(out["trails"], river_polys, tex_rect)
	# the pack's trade on the roads (spec 2026-10-07-war-room-p3 §1.3): a busy
	# road is drawn heavier, by tier
	out["trade"] = []
	for s: Dictionary in WarEconomy.trade_segments(repo, r.grow(r.size.x * 0.02)):
		(out["trade"] as Array).append({"poly": _to_tex(r, k, s["poly"]), "tier": int(s["tier"]), "kind": String(s["kind"])})
	for row: Dictionary in repo.coasts:
		var poly: PackedVector2Array = row["polyline"]
		if _touches(r, poly):
			(out["coasts"] as Array).append(_to_tex(r, k, poly))
	var kingdoms: Array = repo.kingdoms.keys()
	kingdoms.sort()
	for kd: String in kingdoms:
		var loops: Array = []
		for loop: PackedVector2Array in MapOwnership.outline_of(repo, state, kd):
			if _touches(r, loop):
				loops.append(_to_tex(r, k, loop))
		if not loops.is_empty():
			(out["borders"] as Array).append({"kingdom": kd, "color": MapPalette.color_of(repo, kd), "loops": loops})
		for seam: PackedVector2Array in MapOwnership.seams_of(repo, state, kd):
			if _touches(r, seam):
				(out["seams"] as Array).append(_to_tex(r, k, seam))
	# a window keeps what reaches into it: a town's name runs a dozen letters
	# past its ring, so a patch never cuts a name the sheet draws
	var keep := r
	if window.size.x > 0.0:
		var sheet_k := repo.bal("war_sheet_texture_px") / (sheet["rect"] as Rect2).size.x
		keep = r.grow(repo.bal("war_ink_label_px") * 16.0 * repo.bal("war_ink_char_w") / sheet_k)
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		if not keep.has_point(at):
			continue
		var tier := 3 if String(b.get("is_capital", "0")) == "1" else int(TOWN_TIERS.get(String(b.get("group", "")), 0))
		var t := {"code": code, "at": (at - r.position) * k, "tier": tier, "label": String(b["label"]),
			"walls": String(b.get("features", "")).split("|").has("walls"), "port": String(b.get("is_port", "0")) == "1"}
		t.merge(town_marks(repo, code))
		# a works glyph stands above the ring, a market's scales below it — clear
		# of a walled town's square and its corner towers
		var ring := repo.bal("war_ink_town_px") * px_k * (1.0 + repo.bal("war_ink_town_tier_growth") * float(tier))
		if bool(t["walls"]):
			ring *= repo.bal("war_ink_wall_ratio") * 1.22
		t["works_at"] = (t["at"] as Vector2) - Vector2(0.0, ring + repo.bal("war_ink_works_px") * px_k * 0.75)
		t["market_at"] = (t["at"] as Vector2) + Vector2(0.0, ring + repo.bal("war_ink_market_px") * px_k * 0.75)
		(out["towns"] as Array).append(t)
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) != "high":
			continue
		var at: Vector2 = m["pos"]
		if keep.has_point(at):
			(out["peaks"] as Array).append({"at": (at - r.position) * k, "metres": int(m["metres"]), "lod": int(m["lod"])})
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) == "low" and keep.has_point(m["pos"]):
			(out["hollows"] as Array).append({"at": ((m["pos"] as Vector2) - r.position) * k,
				"metres": int(m["metres"]), "lod": int(m["lod"])})
	# the map's marks (spec 2026-10-07-war-room-p2 §1.3): sheet-layer glyphs, a
	# brigand's or pirate's reach as a ring
	out["places"] = []
	var per_px := WarMarks.km_per_px(repo)
	# a mark whose reach runs into the sheet or window is drawn, ring and all
	var reach_px := 0.0
	for t: String in repo.war_mark_hazards:
		reach_px = maxf(reach_px, float(repo.war_mark_hazards[t]["reach_km"]) / per_px)
	var reach_keep := keep.grow(reach_px)
	for m: Dictionary in WarMarks.inked(repo, "sheet"):
		var at: Vector2 = m["at"]
		if not reach_keep.has_point(at):
			continue
		var hz: Dictionary = repo.war_mark_hazards.get(String(m["type"]), {})
		var spot := (at - r.position) * k
		# a mark on a town stands aside, left of its ring (the name runs right):
		# the reach ring keeps the true spot
		var glyph_at := spot
		var half := repo.bal("war_mark_px") * px_k * 0.5
		for t: Dictionary in out["towns"]:
			var ring := repo.bal("war_ink_town_px") * px_k * (1.0 + repo.bal("war_ink_town_tier_growth") * float(int(t["tier"])))
			if glyph_at.distance_to(t["at"]) < ring + half * 1.4:
				glyph_at = (t["at"] as Vector2) - Vector2(ring + half * 1.5, 0.0)   # a clear gap, never touching
		(out["places"] as Array).append({"at": glyph_at, "ring_at": spot, "glyph": String(m["glyph"]),
			"hazard_r": 0.0 if hz.is_empty() else float(hz["reach_km"]) / per_px * k})
	if bake != null:
		var step := repo.bal("war_ink_wood_step_km") * WarSheets.px_per_unit(repo)
		var min_cover := repo.bal("war_ink_wood_min_cover")
		# sampled on the SHEET's grid (a window starts on it), each point taken
		# back to its grid index, so a patch draws exactly the sheet's trees
		var r0: Vector2 = (sheet["rect"] as Rect2).position
		var start := r0 + ((keep.position - r0) / step).floor() * step
		for w: Dictionary in bake.woods(Rect2(start, keep.end - start), step):
			var at: Vector2 = r0 + (((w["at"] as Vector2) - r0) / step).round() * step
			# a glyph where the canopy is thick enough, chosen by a fixed hash so
			# a sheet always draws the same woods
			var roll := float(absi(hash(Vector2i(roundi(at.x * 100.0), roundi(at.y * 100.0)))) % 1000) / 1000.0
			if float(w["cover"]) >= min_cover and roll < float(w["cover"]):
				var jitter := Vector2(float(absi(hash([at.x, at.y, 1])) % 200) - 100.0,
					float(absi(hash([at.x, at.y, 2])) % 200) - 100.0) / 100.0 * step * repo.bal("war_ink_wood_jitter")
				(out["woods"] as Array).append({"at": (at + jitter - r.position) * k, "conifer": float(w["conifer"]) > 0.5})
	_manors(repo, state, r, k, out, px_k, keep)
	var framed := sheet
	if window.size.x > 0.0:
		framed = sheet.duplicate()
		framed["rect"] = r
	out["graticule"] = graticule(repo, framed, k, px_k)
	return out


## The graticule's figures (owner 2026-10-02: 战术地图加上经纬度的格子): each
## meridian's longitude along the top and bottom of the neat line, each
## parallel's latitude down both sides, every war_grid_deg, just inside the
## chequered degree band — `at` the line's foot on the band's inner edge in
## ink px, `side` which edge (n s w e), `text` the figure ("24°N", "51°E").
static func graticule(repo: DataRepository, sheet: Dictionary, k: float, px_k := 1.0) -> Array:
	var r: Rect2 = sheet["rect"]
	var cell: Rect2 = sheet.get("cell", r)
	var step := MapCoords.px_per_deg(repo) * repo.bal("war_grid_deg")
	var pad := repo.bal("war_grid_label_pad_px") * px_k
	var size := int(round(repo.bal("war_grid_label_px") * px_k))
	var out: Array = []
	var x0 := ceili(cell.position.x / step.x + 0.001)
	var x1 := floori(cell.end.x / step.x - 0.001)
	for i in range(x0, x1 + 1):
		var x := (float(i) * step.x - r.position.x) * k
		var lon := MapCoords.lon_lat(repo, Vector2(float(i) * step.x, 0.0)).x
		var text := "%d°%s" % [absi(roundi(lon)), "W" if roundi(lon) < 0 else "E"]
		out.append({"at": Vector2(x, (cell.position.y - r.position.y) * k + pad), "side": "n", "text": text, "size": size})
		out.append({"at": Vector2(x, (cell.end.y - r.position.y) * k - pad), "side": "s", "text": text, "size": size})
	var y0 := ceili(cell.position.y / step.y + 0.001)
	var y1 := floori(cell.end.y / step.y - 0.001)
	for j in range(y0, y1 + 1):
		var y := (float(j) * step.y - r.position.y) * k
		var lat := MapCoords.lon_lat(repo, Vector2(0.0, float(j) * step.y)).y
		var text := "%d°%s" % [absi(roundi(lat)), "S" if roundi(lat) < 0 else "N"]
		out.append({"at": Vector2((cell.position.x - r.position.x) * k + pad, y), "side": "w", "text": text, "size": size})
		out.append({"at": Vector2((cell.end.x - r.position.x) * k - pad, y), "side": "e", "text": text, "size": size})
	return out


## A town's economic marks (spec 2026-10-07-war-room-p3 §1.3): the glyph of
## its works family ("" for none) and whether a market is centred on it.
static func town_marks(repo: DataRepository, burg: String) -> Dictionary:
	return {"works": String((WarEconomy.works(repo).get(burg, {}) as Dictionary).get("glyph", "")),
		"market": WarEconomy.market_of_town(repo, burg) != ""}


## A town's ring and name as one box, ink px (the painter's own layout: the
## ring at `at`, the name to its right), for keeping other names off it.
static func town_label_box(repo: DataRepository, t: Dictionary, px_k := 1.0) -> Rect2:
	var town := repo.bal("war_ink_town_px") * px_k
	var r := town * (1.0 + repo.bal("war_ink_town_tier_growth") * float(int(t["tier"])))
	var label := repo.bal("war_ink_label_px") * px_k
	var w := r + town * repo.bal("war_ink_label_gap_ratio") + float(String(t["label"]).length()) * label * repo.bal("war_ink_char_w")
	var h := maxf(r, label * 0.6)
	var up := h
	var down := h
	var clear := r * (repo.bal("war_ink_wall_ratio") * 1.22 if bool(t.get("walls", false)) else 1.0)
	if String(t.get("works", "")) != "":
		up = maxf(up, clear + repo.bal("war_ink_works_px") * px_k * 1.25)
	if bool(t.get("market", false)):
		down = maxf(down, clear + repo.bal("war_ink_market_px") * px_k * 1.25)
	var at: Vector2 = t["at"]
	return Rect2(at.x - r, at.y - up, r + w, up + down)


## A manor's name as a box, ink px, centred where the painter sets it.
static func manor_label_box(repo: DataRepository, m: Dictionary, px_k := 1.0) -> Rect2:
	var px := repo.bal("war_ink_manor_label_px") * px_k
	var w := float(String(m["label"]).length()) * px * repo.bal("war_ink_char_w")
	var at: Vector2 = m["at"]
	return Rect2(at.x - w * 0.5, at.y - px * 0.5, w, px)


## The manors' own edges — a cell edge between two land cells of ONE province
## (a province seam or the coast is drawn already) — and each manor's name at
## its centre unless its box would touch a town's ring or name (a town's name
## wins; war_ink_manor_clear_px of air kept round it).
static func _manors(repo: DataRepository, state: GameState, r: Rect2, k: float, out: Dictionary, px_k := 1.0,
		keep := Rect2()) -> void:
	var first: Dictionary = {}   # edge key -> the cell that met it first
	var ids: Array = repo.cells.keys()
	ids.sort()
	var clear := repo.bal("war_ink_manor_clear_px") * px_k
	var reach := (keep if keep.size.x > 0.0 else r).grow(r.size.x * 0.05)
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		var vids: PackedInt32Array = cell["vertex_ids"]
		if vids.size() < 3:
			continue
		var centre := MapTerrain.cell_center(repo, cell)
		if not reach.has_point(centre):
			continue
		var prov := MapManors.province_of(repo, id, state)
		for i in vids.size():
			var a := vids[i]
			var b := vids[(i + 1) % vids.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if first.has(key):
				if MapManors.province_of(repo, int(first[key]), state) == prov:
					(out["manor_edges"] as Array).append(PackedVector2Array([
						((repo.vertices[a] as Vector2) - r.position) * k, ((repo.vertices[b] as Vector2) - r.position) * k]))
			else:
				first[key] = id
		if r.has_point(centre):
			var m := {"at": (centre - r.position) * k, "label": MapManors.label_of(repo, id)}
			var box := manor_label_box(repo, m, px_k).grow(clear)
			var clash := false
			for t: Dictionary in out["towns"]:
				if box.intersects(town_label_box(repo, t, px_k)):
					clash = true
					break
			if not clash:
				(out["manors"] as Array).append(m)


## A river's course in ink px made ready to draw: the part reaching `area`
## (one point beyond it either side, so the curve inside is the whole
## course's), with a point every `step` px along a curve through its samples
## (MapGeometry.densify_open), and `t0` / `t1` — how far along the WHOLE
## course (by length) the part starts and ends, for its taper.
## {poly, t0, t1}; poly empty when no span reaches the area.
static func river_line(poly: PackedVector2Array, area: Rect2, step: float) -> Dictionary:
	var lo := -1
	var hi := -1
	for i in poly.size() - 1:
		if Rect2(poly[i], Vector2.ZERO).expand(poly[i + 1]).intersects(area, true):
			if lo < 0:
				lo = i
			hi = i + 1
	if lo < 0:
		return {"poly": PackedVector2Array(), "t0": 0.0, "t1": 1.0}
	lo = maxi(lo - 1, 0)
	hi = mini(hi + 1, poly.size() - 1)
	var total := 0.0
	var at_lo := 0.0
	var at_hi := 0.0
	for i in range(1, poly.size()):
		total += poly[i].distance_to(poly[i - 1])
		if i == lo:
			at_lo = total
		if i == hi:
			at_hi = total
	total = maxf(total, 0.0001)
	return {"poly": MapGeometry.densify_open(poly.slice(lo, hi + 1), step), "t0": at_lo / total, "t1": at_hi / total}


## The longest stretch of `poly` (by its length) whose points all lie in
## `area`: Vector2i(first, last) point index; (0, -1) when no two do. A
## river's name is written along it, so it never runs off the sheet.
static func longest_run(poly: PackedVector2Array, area: Rect2) -> Vector2i:
	var best := Vector2i(0, -1)
	var best_len := 0.0
	var start := -1
	var run_len := 0.0
	for i in poly.size() + 1:
		if i < poly.size() and area.has_point(poly[i]):
			if start < 0:
				start = i
				run_len = 0.0
			else:
				run_len += poly[i].distance_to(poly[i - 1])
			continue
		if start >= 0 and i - 1 > start and run_len > best_len:
			best = Vector2i(start, i - 1)
			best_len = run_len
		start = -1
	return best


## Where any of `lines` crosses any of `rivers` (both lists of polylines in one
## space): the point and the LINE's direction there. The rivers' segments are
## put in a grid of CROSS_CELL_PX buckets once (a river drawn on its smooth
## course runs to thousands of segments), so each line segment meets only the
## few river segments near it.
const CROSS_CELL_PX := 64.0


static func crossings(lines: Array, rivers: Array, clip := Rect2()) -> Array:
	var out: Array = []
	var clipped := clip.size != Vector2.ZERO
	var grid: Dictionary = {}   # Vector2i cell -> [[a, b, box, id], ...]
	var n_segs := 0
	for rv: PackedVector2Array in rivers:
		for j in rv.size() - 1:
			var box := Rect2(rv[j], Vector2.ZERO).expand(rv[j + 1])
			if clipped and not box.intersects(clip, true):
				continue
			var seg := [rv[j], rv[j + 1], box, n_segs]
			n_segs += 1
			for cell: Vector2i in _cells(box):
				if not grid.has(cell):
					grid[cell] = []
				(grid[cell] as Array).append(seg)
	for line: PackedVector2Array in lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var lbox := Rect2(a, Vector2.ZERO).expand(b)
			if clipped and not lbox.intersects(clip, true):
				continue
			var seen: Dictionary = {}   # a river segment in two of this segment's cells is met once
			for cell: Vector2i in _cells(lbox):
				for sg: Array in grid.get(cell, []):
					if seen.has(sg[3]) or not lbox.intersects(sg[2] as Rect2, true):
						continue
					seen[sg[3]] = true
					var hit: Variant = Geometry2D.segment_intersects_segment(a, b, sg[0], sg[1])
					if hit != null:
						out.append({"at": hit as Vector2, "dir": (b - a).normalized()})
	return out


static func _cells(box: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := Vector2i((box.position / CROSS_CELL_PX).floor())
	var hi := Vector2i((box.end / CROSS_CELL_PX).floor())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out


## The line cut into dashes: `on` px drawn, `off` px left, along its whole
## length. A dash or gap of no length cannot cut it: the whole line is one dash.
static func dashed(poly: PackedVector2Array, on: float, off: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if poly.size() < 2:
		return out
	if on <= 0.0 or off <= 0.0:
		out.append(poly.duplicate())
		return out
	var drawing := true
	var left := on
	var cur := PackedVector2Array([poly[0]])
	for i in range(1, poly.size()):
		var a := poly[i - 1]
		var b := poly[i]
		var seg := a.distance_to(b)
		var pos := 0.0
		while seg - pos > left:
			pos += left
			var p := a.lerp(b, pos / seg)
			if drawing:
				cur.append(p)
				out.append(cur)
				cur = PackedVector2Array()
			else:
				cur = PackedVector2Array([p])
			drawing = not drawing
			left = on if drawing else off
		left -= seg - pos
		if drawing:
			cur.append(b)
	if drawing and cur.size() >= 2:
		out.append(cur)
	return out
