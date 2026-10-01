class_name WarSheets
extends RefCounted
## The WAR ROOM's numbered map series (owner 2026-10-01, spec
## 2026-10-01-war-room-design §2): the pack cut into equal sheets at ONE
## scale, neighbours overlapping, numbered in Roman numerals row by row from
## the north-west, each named after the kingdom with the most land on it by
## the STARTING border, and a place written "III · C7". Generated from the
## pack alone; no pack is named. Pure and cached per repository.

static var _cache: Dictionary = {}


static func forget() -> void:
	_cache.clear()


## Pack px per unit of the pack's own measure (map_info distance_scale is
## units per px), so the war_* sizes are in the measure the scale bar reads.
static func px_per_unit(repo: DataRepository) -> float:
	return 1.0 / maxf(float(repo.map_info.get("distance_scale", "1")), 0.0001)


## Every sheet rect of the full grid, row-major: a stride of the size less the
## overlap, as many as cover the map, the last of each run held to the edge so
## no sheet runs off it. A map smaller than a sheet is one sheet at the origin.
static func layout(width: float, height: float, w: float, h: float, overlap: float) -> Array[Rect2]:
	var xs := _starts(width, w, overlap)
	var ys := _starts(height, h, overlap)
	var out: Array[Rect2] = []
	for y in ys:
		for x in xs:
			out.append(Rect2(x, y, w, h))
	return out


static func _starts(span: float, size: float, overlap: float) -> Array[float]:
	if span <= size:
		return [0.0]
	var stride := maxf(size - overlap, 1.0)
	var n := int(ceil((span - overlap) / stride))
	var out: Array[float] = []
	for i in n:
		out.append(minf(float(i) * stride, span - size))
	return out


## The series: sheets with land, in order, numbered and named.
static func series(repo: DataRepository) -> Array:
	var key := repo.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var k := px_per_unit(repo)
	var rects := layout(float(repo.map_info.get("width", "0")), float(repo.map_info.get("height", "0")),
		repo.bal("war_sheet_w_km") * k, repo.bal("war_sheet_h_km") * k, repo.bal("war_sheet_overlap_km") * k)
	var centres := _land_centres(repo)
	var out: Array = []
	for r: Rect2 in rects:
		var tally: Dictionary = {}
		for c: Dictionary in centres:
			if r.has_point(c["at"]):
				tally[c["kingdom"]] = int(tally.get(c["kingdom"], 0)) + 1
		if tally.is_empty():
			continue
		var best := ""
		for kd: String in tally:
			if best == "" or int(tally[kd]) > int(tally[best]) or (int(tally[kd]) == int(tally[best]) and kd < best):
				best = kd
		var i := out.size()
		out.append({"index": i, "numeral": roman(i + 1), "kingdom": best,
			"name": String((repo.kingdoms.get(best, {}) as Dictionary).get("label", best)), "rect": r})
	_cache[key] = out
	return out


## Each land cell's centre and its province's starting kingdom.
static func _land_centres(repo: DataRepository) -> Array:
	var out: Array = []
	var ids: Array = repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var prov := String((repo.manors.get(id, {}) as Dictionary).get("province_code", ""))
		var kd := String((repo.provinces.get(prov, {}) as Dictionary).get("kingdom_code", ""))
		if kd == "":
			continue
		out.append({"at": MapTerrain.cell_center(repo, cell), "kingdom": kd})
	return out


static func roman(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	var left := n
	for i in vals.size():
		while left >= int(vals[i]):
			out += String(syms[i])
			left -= int(vals[i])
	return out


## The sheet holding `px` whose centre is nearest (in the overlap both hold
## it); a point on no sheet goes to the sheet whose rect is nearest.
static func sheet_of(repo: DataRepository, px: Vector2) -> int:
	var best := -1
	var best_d := INF
	var holding := false
	for s: Dictionary in series(repo):
		var r: Rect2 = s["rect"]
		var inside := r.has_point(px)
		var d := px.distance_squared_to(r.get_center()) if inside else _rect_gap(r, px)
		if (inside and not holding) or ((inside == holding) and d < best_d):
			best = int(s["index"])
			best_d = d
			holding = holding or inside
	return best


static func _rect_gap(r: Rect2, p: Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return 1.0e12 + p.distance_squared_to(q)  # always behind any sheet that holds it


## "III · C7": the sheet's numeral, the column letter (A from the west edge)
## and row number (1 from the north edge) of war_grid_km squares.
static func grid_ref(repo: DataRepository, sheet: Dictionary, px: Vector2) -> String:
	var r: Rect2 = sheet["rect"]
	var g := repo.bal("war_grid_km") * px_per_unit(repo)
	var col := clampi(int(floor((px.x - r.position.x) / g)), 0, 25)
	var row := maxi(int(floor((px.y - r.position.y) / g)), 0) + 1
	return "%s · %s%d" % [sheet["numeral"], char(65 + col), row]


## The sheets beside `index`: the nearest one each way whose rect overlaps
## this one's edge band.
static func neighbours(repo: DataRepository, index: int) -> Dictionary:
	var all := series(repo)
	if index < 0 or index >= all.size():
		return {}
	var me: Rect2 = all[index]["rect"]
	var out: Dictionary = {}
	var dists: Dictionary = {}
	for s: Dictionary in all:
		var r: Rect2 = s["rect"]
		if int(s["index"]) == index:
			continue
		var dc := r.get_center() - me.get_center()
		var dir := ""
		if absf(dc.x) > absf(dc.y):
			dir = "e" if dc.x > 0.0 else "w"
			if r.position.y >= me.end.y or r.end.y <= me.position.y:
				continue
		else:
			dir = "s" if dc.y > 0.0 else "n"
			if r.position.x >= me.end.x or r.end.x <= me.position.x:
				continue
		var d := dc.length()
		if not dists.has(dir) or d < float(dists[dir]):
			dists[dir] = d
			out[dir] = int(s["index"])
	return out
