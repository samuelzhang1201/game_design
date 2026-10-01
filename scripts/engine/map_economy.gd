class_name MapEconomy
extends RefCounted
## What each province makes, and what a realm makes in total.
##
## The pack records production per BURG (economy/production.csv, keyed
## burg:good); a province's output is the sum over the burgs inside it, and a
## realm's is the sum over the provinces it holds NOW — so a conquest moves
## the output with the land, the same way the map's colours move. Pure
## functions over the repository and the live state; cached where the answer
## cannot change (the pack's burgs never move between provinces) and computed
## fresh where it can (who holds what).

## {province_code: {good_code: units}}. Cached: burgs do not change province.
static var _output_cache: Dictionary = {}
## {burg_code: cell_id} and {cell_id: manor}, per repository. Cached: a burg
## never moves out of its cell.
static var _burg_cell_cache: Dictionary = {}
static var _manor_cache: Dictionary = {}
## {repo instance id: {"bucket": float, "grid": Dictionary}}. Cached: the
## pack's land cells never move.
static var _land_grid_cache: Dictionary = {}

static func forget() -> void:
	_output_cache.clear()
	_burg_cell_cache.clear()
	_manor_cache.clear()
	_land_grid_cache.clear()

## --- Manors (owner request 2026-09-13) ----------------------------------
## The ECONOMY view draws the land as its MANORS: the pack's Voronoi cells,
## each one an estate. A manor with a settlement in it is a working manor —
## it carries that settlement's production. The pack records production per
## burg and gives no burg a cell, so the cell is found here: the land cell
## whose polygon holds the burg's point.

## {burg_code: cell_id} for every burg that stands inside a land cell.
static func burg_cells(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _burg_cell_cache.has(key):
		return _burg_cell_cache[key]
	var out: Dictionary = {}
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		var p := Vector2(float(b.get("x", 0)), float(b.get("y", 0)))
		var id := cell_at(repo, p)
		# A burg on the shoreline can sit a hair outside every land polygon;
		# it belongs to the nearest land cell around it.
		if id >= 0:
			out[code] = id
	_burg_cell_cache[key] = out
	return out

## The land cells bucketed by centre, so a point only tests a handful of
## polygons, not all of them. Cached: the pack's land cells never move.
static func _land_grid(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _land_grid_cache.has(key):
		return _land_grid_cache[key]
	var reach := 0.0
	var land: Array = []
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		land.append(id)
		reach = maxf(reach, MapTerrain.cell_radius(repo, cell))
	var bucket := maxf(reach * 2.0, 1.0)
	var grid: Dictionary = {}
	# Each land cell's polygon, its bounding box (grown a hair, so a point it
	# leaves out is surely outside the polygon) and its centre, built ONCE:
	# cell_at is asked every frame by the map's counters (ArmySystem.bars_of →
	# supply_use), and building them per ask cost ~0.15 ms a regiment (perf
	# 2026-10-02). Same polygons, same centres, so the same answers.
	var polys: Dictionary = {}
	var boxes: Dictionary = {}
	var centres: Dictionary = {}
	for id: int in land:
		var poly := cell_polygon(repo, repo.cells[id])
		var box := Rect2(poly[0], Vector2.ZERO)
		for q: Vector2 in poly:
			box = box.expand(q)
		polys[id] = poly
		boxes[id] = box.grow(0.001)
		centres[id] = MapTerrain.cell_center(repo, repo.cells[id])
		var g := Vector2i(((centres[id] as Vector2) / bucket).floor())
		if not grid.has(g):
			grid[g] = []
		(grid[g] as Array).append(id)
	var out := {"bucket": bucket, "grid": grid, "polys": polys, "boxes": boxes, "centres": centres}
	_land_grid_cache[key] = out
	return out

## The land cell holding a map point: the cell whose polygon contains it, else
## the land cell with the nearest centre in the neighbouring buckets (a point
## on the shoreline can sit a hair outside every land polygon). -1 when no
## land cell is near.
static func cell_at(repo: DataRepository, p: Vector2) -> int:
	var lg := _land_grid(repo)
	var bucket: float = lg["bucket"]
	var grid: Dictionary = lg["grid"]
	var polys: Dictionary = lg["polys"]
	var boxes: Dictionary = lg["boxes"]
	var centres: Dictionary = lg["centres"]
	var home := Vector2i((p / bucket).floor())
	var nearest := -1
	var nearest_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for id: int in grid.get(home + Vector2i(dx, dy), []):
				if (boxes[id] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, polys[id]):
					return id
				var d := p.distance_squared_to(centres[id])
				if d < nearest_d:
					nearest_d = d
					nearest = id
	return nearest

static func cell_polygon(repo: DataRepository, cell: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in (cell["vertex_ids"] as PackedInt32Array):
		pts.append(repo.vertices[v] as Vector2)
	return pts

## Every working manor: {cell_id: {cell, burgs, goods, good, units, total}} —
## `goods` everything its settlements make, `good` / `units` the one it makes
## most of (ties break on the good code, as in dominant), `total` the lot.
static func manors(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _manor_cache.has(key):
		return _manor_cache[key]
	var cells := burg_cells(repo)
	var out: Dictionary = {}
	for row: Dictionary in repo.world_table("economy", "production").values():
		var burg := String(row.get("burg_code", ""))
		if not cells.has(burg):
			continue
		var id: int = cells[burg]
		if not out.has(id):
			out[id] = {"cell": id, "burgs": [], "goods": {}}
		var m: Dictionary = out[id]
		if not (m["burgs"] as Array).has(burg):
			(m["burgs"] as Array).append(burg)
		var good := String(row.get("good_code", ""))
		m["goods"][good] = float(m["goods"].get(good, 0.0)) + float(row.get("units", 0))
	for id: int in out:
		var m: Dictionary = out[id]
		(m["burgs"] as Array).sort()
		var best := ""
		var best_units := -1.0
		var total := 0.0
		for good: String in m["goods"]:
			var units := float(m["goods"][good])
			total += units
			if units > best_units or (units == best_units and good < best):
				best_units = units
				best = good
		m["good"] = best
		m["units"] = best_units
		m["total"] = total
	_manor_cache[key] = out
	return out

## How good a manor's land is, 0..1: its biome's habitability from the pack
## (geography/biomes.csv, 0-100). The ECONOMY view deepens a manor's colour
## with it, so rich farmland reads darker than moor and tundra.
static func land_value(repo: DataRepository, cell: Dictionary) -> float:
	var row: Dictionary = repo.biomes.get(int(cell.get("biome_id", -1)), {})
	return clampf(float(row.get("habitability", 0)) / 100.0, 0.0, 1.0)

static func province_output(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _output_cache.has(key):
		return _output_cache[key]
	var out: Dictionary = {}
	for row: Dictionary in repo.world_table("economy", "production").values():
		var burg: Dictionary = repo.burgs.get(String(row.get("burg_code", "")), {})
		if burg.is_empty():
			continue
		var province := String(burg.get("province_code", ""))
		if province == "":
			continue
		if not out.has(province):
			out[province] = {}
		var good := String(row.get("good_code", ""))
		var by: Dictionary = out[province]
		by[good] = float(by.get(good, 0.0)) + float(row.get("units", 0))
	_output_cache[key] = out
	return out

## The one good a province makes most of: {good, units, share} — share being
## its part of everything that province makes, so a one-crop province reads
## differently from a mixed one. {} when the province makes nothing.
static func dominant(repo: DataRepository, province_code: String) -> Dictionary:
	var by: Dictionary = province_output(repo).get(province_code, {})
	if by.is_empty():
		return {}
	var best := ""
	var best_units := -1.0
	var total := 0.0
	for good: String in by:
		var units := float(by[good])
		total += units
		# Ties break on the good code so the map never flickers between two.
		if units > best_units or (units == best_units and good < best):
			best_units = units
			best = good
	return {"good": best, "units": best_units,
		"share": 0.0 if total <= 0.0 else best_units / total}

## Everything a realm makes, biggest first: [{good, label, units}]. Reads
## ownership live, so a province changing hands moves its output with it.
static func realm_output(repo: DataRepository, state: GameState, kingdom_code: String) -> Array:
	return output_of_provinces(repo, MapOwnership.provinces_of(repo, state, kingdom_code))

## The same over any provinces — the crown's controlled ones for its own
## column (MapManors.controlled_provinces). WITHOUT a state it is the pack's
## town production alone; WITH one, every manor's month as ManorEconomy
## figures it (2026-09-14) — the chief good, the buildings' produce and the
## town's, in whole units, so the column and the manor card say one thing.
static func output_of_provinces(repo: DataRepository, provinces: Array, state: GameState = null) -> Array:
	var totals: Dictionary = {}
	var per_province := province_output(repo)
	for province: String in provinces:
		if state == null:
			for good: String in per_province.get(province, {}):
				totals[good] = float(totals.get(good, 0.0)) + float(per_province[province][good])
			continue
		for cell: int in MapManors.manors_of_province(repo, province, state):
			var units: Dictionary = ManorEconomy.line_of(repo, state, cell, state.tick)["units"]
			for good: String in units:
				totals[good] = float(totals.get(good, 0.0)) + float(units[good])
	var out: Array = []
	for good: String in totals:
		out.append({"good": good, "units": float(totals[good]),
			"label": String(repo.world_row("economy", "goods", good).get("label", good))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["units"] == b["units"]:
			return String(a["good"]) < String(b["good"])
		return a["units"] > b["units"])
	return out

## The tag a good is filed under — its first, which is the one the palette
## and the economy map colour by. "" when the good is unknown.
static func good_tag(repo: DataRepository, good_code: String) -> String:
	var tags := String(repo.world_row("economy", "goods", good_code).get("tags", ""))
	var parts := tags.split("|", false)
	return "" if parts.is_empty() else String(parts[0])
