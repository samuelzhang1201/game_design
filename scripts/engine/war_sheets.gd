class_name WarSheets
extends RefCounted
## The WAR ROOM's map series (owner 2026-10-01; v2 2026-10-02, spec
## 2026-10-02-war-room-v2 §2.2): the pack cut by its own graticule
## (MapCoords) into war_sheet_deg cells, a sheet for every cell with land,
## named "D4" — the column letter and row number from the north-west — and
## after the kingdom with the most land on it by the STARTING border. A
## sheet's `cell` is its neat line; its `rect`, what the table shows, is the
## cell grown by a war_sheet_collar_km collar of the neighbouring ground. A
## place is written "D4 · c7 · 24°N 51°E". Generated from the pack alone; no
## pack is named. Pure and cached per repository.

static var _cache: Dictionary = {}


static func forget() -> void:
	_cache.clear()


## Pack px per unit of the pack's own measure (map_info distance_scale is
## units per px), so the war_* sizes are in the measure the scale bar reads.
static func px_per_unit(repo: DataRepository) -> float:
	return 1.0 / maxf(float(repo.map_info.get("distance_scale", "1")), 0.0001)


static func id_of(col: int, row: int) -> String:
	return "%s%d" % [char(65 + col), row + 1]


static func series(repo: DataRepository) -> Array:
	var key := repo.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var deg := repo.bal("war_sheet_deg")
	var collar := repo.bal("war_sheet_collar_km") * px_per_unit(repo)
	var tallies: Dictionary = {}   # Vector2i cell -> {kingdom: count}
	for c: Dictionary in _land_centres(repo):
		var at := MapCoords.cell_of(repo, c["at"], deg)
		if not tallies.has(at):
			tallies[at] = {}
		var t: Dictionary = tallies[at]
		if String(c["kingdom"]) != "":
			t[c["kingdom"]] = int(t.get(c["kingdom"], 0)) + 1
	var keys: Array = tallies.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array = []
	for at: Vector2i in keys:
		var tally: Dictionary = tallies[at]
		var best := ""
		for kd: String in tally:
			if best == "" or int(tally[kd]) > int(tally[best]) or (int(tally[kd]) == int(tally[best]) and kd < best):
				best = kd
		var cell := MapCoords.cell_rect(repo, at, deg)
		out.append({"index": out.size(), "id": id_of(at.x, at.y), "kingdom": best,
			"name": String((repo.kingdoms.get(best, {}) as Dictionary).get("label", best)),
			"cell": cell, "rect": cell.grow(collar), "col": at.x, "row": at.y})
	_cache[key] = out
	return out


## Each land cell's centre and its province's starting kingdom ("" unclaimed).
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
		# unclaimed land is land too (v2: a sheet for every cell with land); it
		# names no kingdom, so it only counts toward having a sheet
		out.append({"at": MapTerrain.cell_center(repo, cell), "kingdom": kd})
	return out


## The sheet holding `px` whose centre is nearest (in a collar two sheets'
## rects hold it, and the cell it lies in is the nearer); a point on no sheet
## goes to the sheet whose rect is nearest.
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


## "D4 · c7 · 24°N 51°E": the sheet's id, the war_grid_deg square inside its
## neat line (a lower-case column letter from the west, a row number from the
## north) and the place's own whole degrees.
static func grid_ref(repo: DataRepository, sheet: Dictionary, px: Vector2) -> String:
	var c: Rect2 = sheet.get("cell", sheet["rect"])
	var g := MapCoords.px_per_deg(repo) * repo.bal("war_grid_deg")
	var col := clampi(floori((px.x - c.position.x) / g.x), 0, 25)
	var row := maxi(floori((px.y - c.position.y) / g.y), 0) + 1
	return "%s · %s%d · %s" % [sheet["id"], char(97 + col), row, MapCoords.format(MapCoords.lon_lat(repo, px))]


## The sheets beside `index` by GRID position only: the kept sheet at
## (col +- 1, row) or (col, row +- 1), nothing where the grid holds none (a
## skipped sea sheet, the map's edge). Never a diagonal.
static func neighbours(repo: DataRepository, index: int) -> Dictionary:
	var all := series(repo)
	if index < 0 or index >= all.size():
		return {}
	var cells: Dictionary = {}
	for s: Dictionary in all:
		cells[Vector2i(int(s["col"]), int(s["row"]))] = int(s["index"])
	var me: Dictionary = all[index]
	return grid_neighbours(cells, Vector2i(int(me["col"]), int(me["row"])))


## Pure: `cells` maps Vector2i(col, row) to a sheet index; the four that stand
## beside `at`, as {"n"|"s"|"e"|"w": index}, only those that exist.
static func grid_neighbours(cells: Dictionary, at: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for d: Array in [["n", Vector2i(0, -1)], ["s", Vector2i(0, 1)], ["e", Vector2i(1, 0)], ["w", Vector2i(-1, 0)]]:
		var key: Vector2i = at + (d[1] as Vector2i)
		if cells.has(key):
			out[d[0]] = int(cells[key])
	return out
