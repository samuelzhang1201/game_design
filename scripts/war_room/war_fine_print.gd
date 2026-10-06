class_name WarFinePrint
extends RefCounted
## What a leaning officer reads that the overview never shows (spec
## 2026-10-07-war-room-scale-hover §3), in the sheet's ink texture px: each
## town's second line, the routes' names, the minor peaks and hollows, and the
## heights written on the contours. Only public, static facts of the map. A
## box that would touch a town's or a manor's name is left out. Pure.


## "city · citadel · 14,061 souls · 961 m".
static func town_note(b: Dictionary) -> String:
	var feats := String(b.get("features", "")).split("|")
	var works := "citadel" if "citadel" in feats else ("walls" if "walls" in feats else "open")
	return "%s · %s · %s souls · %s m" % [String(b.get("group", "")), works,
		Intel.num(int(float(b.get("population", "0")))), String(b.get("elevation_m", "0"))]


static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int, bake: WarBake) -> Dictionary:
	var r: Rect2 = sheet["rect"]
	var k := float(tex_px) / r.size.x
	var ink := WarSheetInk.strokes(repo, state, sheet, tex_px)
	var taken: Array = []   # Rect2 boxes, ink px: the names already on the sheet
	for t: Dictionary in ink["towns"]:
		taken.append(WarSheetInk.town_label_box(repo, t))
	for m: Dictionary in ink.get("manors", []):
		taken.append(WarSheetInk.manor_label_box(repo, m))
	var out := {"notes": [], "routes": [], "marks": [], "figures": []}
	var note_px := repo.bal("war_fine_note_px")
	var char_w := repo.bal("war_ink_char_w")
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		if not r.has_point(at):
			continue
		var tier := 3 if String(b.get("is_capital", "0")) == "1" else int(WarSheetInk.TOWN_TIERS.get(String(b.get("group", "")), 0))
		var box := WarSheetInk.town_label_box(repo, {"at": (at - r.position) * k, "tier": tier, "label": String(b["label"])})
		var text := town_note(b)
		# under the name, left-aligned with it
		var pos := Vector2(box.position.x + box.size.y, box.end.y + note_px * 0.9)
		var nb := Rect2(pos - Vector2(0, note_px), Vector2(float(text.length()) * note_px * char_w, note_px * 1.2))
		if _clear(nb, taken):
			taken.append(nb)
			(out["notes"] as Array).append({"at": pos, "text": text})
	var route_px := repo.bal("war_fine_route_px")
	var tex_rect := Rect2(Vector2.ZERO, r.size * k)
	var rcodes: Array = repo.routes.keys()
	rcodes.sort()
	for code: String in rcodes:
		var row: Dictionary = repo.routes[code]
		var label := String(row.get("label", ""))
		if label == "" or not ["roads", "trails"].has(String(row.get("group", ""))):
			continue
		var poly: PackedVector2Array = row["polyline"]
		var best := -1
		var best_len := 0.0
		for i in poly.size() - 1:
			var a := (poly[i] - r.position) * k
			var b2 := (poly[i + 1] - r.position) * k
			if tex_rect.has_point(a) and tex_rect.has_point(b2) and a.distance_to(b2) > best_len:
				best_len = a.distance_to(b2)
				best = i
		if best < 0 or best_len < float(label.length()) * route_px * char_w:
			continue
		var p0 := (poly[best] - r.position) * k
		var p1 := (poly[best + 1] - r.position) * k
		var ang := (p1 - p0).angle()
		if ang > PI * 0.5:
			ang -= PI
		elif ang < -PI * 0.5:
			ang += PI
		var mid := (p0 + p1) * 0.5
		var w := float(label.length()) * route_px * char_w
		var rb := Rect2(mid - Vector2(w * 0.5, route_px), Vector2(w, route_px * 1.2))
		if _clear(rb, taken):
			taken.append(rb)
			(out["routes"] as Array).append({"at": mid, "angle": ang, "text": label})
	var mark_px := repo.bal("war_fine_mark_px")
	for m: Dictionary in Elevation.landmarks(repo):
		if int(m["lod"]) == 0 or not r.has_point(m["pos"]):
			continue
		var at := ((m["pos"] as Vector2) - r.position) * k
		var mb := Rect2(at - Vector2(mark_px, mark_px), Vector2(mark_px * 2.0 + note_px * 4.0, mark_px * 2.0))
		if _clear(mb, taken):
			taken.append(mb)
			(out["marks"] as Array).append({"at": at, "kind": String(m["kind"]), "metres": int(m["metres"])})
	if bake != null:
		var nx := int(repo.bal("war_fine_contour_grid"))
		var nz := WarRoomTable.rows_for(r, nx)
		var heights := bake.heights(r, nx, nz)
		var spacing := repo.bal("war_fine_contour_label_km") * WarSheets.px_per_unit(repo) * k
		# a figure keeps off the roads, trails and rivers it would sit on (the
		# critic of 2026-10-07: a trail's dashes ran through a "1000"): half a
		# four-figure height's length along its contour, and a little air
		var fig_px := repo.bal("war_fine_figure_px")
		var keep_off := fig_px * char_w * 2.0 + fig_px * 0.5
		var lines: Array = (ink["roads"] as Array) + (ink["trails"] as Array)
		for rv: Dictionary in ink["rivers"]:
			lines.append(rv["poly"])
		var off_lines := func(at: Vector2) -> bool: return not _near_line(at, lines, keep_off)
		for f: Dictionary in contour_figures(heights, nx, nz, r.size * k, repo.bal("war_fine_contour_level_m"), spacing, off_lines):
			var fb := Rect2((f["at"] as Vector2) - Vector2(note_px, note_px * 0.6), Vector2(note_px * 2.0, note_px * 1.2))
			if _clear(fb, taken):
				taken.append(fb)
				(out["figures"] as Array).append({"at": f["at"], "angle": f["angle"], "text": str(int(f["metres"]))})
	return out


static func _near_line(at: Vector2, lines: Array, reach: float) -> bool:
	for poly: PackedVector2Array in lines:
		for i in poly.size() - 1:
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, poly[i], poly[i + 1])) <= reach:
				return true
	return false


static func _clear(box: Rect2, taken: Array) -> bool:
	for t: Rect2 in taken:
		if t.intersects(box):
			return false
	return true


## Where the `level_m` multiples cross the grid's edges, each with its
## contour's direction (normalised so the figure is never upside down), no
## two of one height nearer than `spacing_px`, none where `allowed` (a point) says no. `heights` is nx x nz, row-major
## z outer, spanning `size_px`. Pure.
static func contour_figures(heights: PackedFloat32Array, nx: int, nz: int, size_px: Vector2,
		level_m: float, spacing_px: float, allowed := Callable()) -> Array:
	var out: Array = []
	if nx < 2 or nz < 2 or level_m <= 0.0 or heights.size() < nx * nz:
		return out
	var cell := Vector2(size_px.x / float(nx - 1), size_px.y / float(nz - 1))
	for z in nz:
		for x in nx - 1:
			var h0 := heights[z * nx + x]
			var h1 := heights[z * nx + x + 1]
			var lo := minf(h0, h1)
			var hi := maxf(h0, h1)
			var level := ceilf(lo / level_m) * level_m
			if level <= 0.0 or level > hi or hi == lo:
				continue
			var t := (level - h0) / (h1 - h0)
			var at := Vector2((float(x) + t) * cell.x, float(z) * cell.y)
			# the gradient from the neighbouring rows; the contour runs across it
			var zu := maxi(z - 1, 0)
			var zd := mini(z + 1, nz - 1)
			var gy := (heights[zd * nx + x] - heights[zu * nx + x]) / maxf(float(zd - zu) * cell.y, 1e-3)
			var gx := (h1 - h0) / cell.x
			var ang := Vector2(gx, gy).orthogonal().angle()
			if ang > PI * 0.5:
				ang -= PI
			elif ang < -PI * 0.5:
				ang += PI
			var ok := not allowed.is_valid() or bool(allowed.call(at))
			for f: Dictionary in out:
				if int(f["metres"]) == int(level) and (f["at"] as Vector2).distance_to(at) < spacing_px:
					ok = false
					break
			if ok:
				out.append({"at": at, "angle": ang, "metres": int(level)})
	return out
