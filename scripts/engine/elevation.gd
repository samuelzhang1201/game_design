class_name Elevation
extends RefCounted
## Height as numbers (owner 2026-09-19, spec
## docs/superpowers/specs/2026-09-19-map3d-heights-design.md): the pack's
## CELL height in metres, the supply tier it falls in, and (§3) the named
## high and low points. Pure and deterministic; the 3D mesh's synthesized
## ridges are look only and never enter here. Caches are per pack, forgotten
## by DataRepository.load_map.

static var _landmarks: Array = []
static var _landmarks_map := ""


static func forget() -> void:
	_landmarks = []
	_landmarks_map = ""


## Whole metres above the waterline of an Azgaar height (negative under it).
static func metres_of_height(repo: DataRepository, height: float) -> int:
	return int(round((height - repo.bal("elevation_sea_level")) * repo.bal("elevation_m_per_unit")))


## A cell's metres; 0 for no cell.
static func metres_of_cell(repo: DataRepository, id: int) -> int:
	if not repo.cells.has(id):
		return 0
	return metres_of_height(repo, float(repo.cells[id]["height"]))


## {tier, supply_permille}: the first row of army_height_supply.csv, highest
## first, whose min_height the height reaches.
static func tier_of(repo: DataRepository, height: float) -> Dictionary:
	for r: Dictionary in repo.army_height_supply:
		if height >= float(r["min_height"]):
			return {"tier": String(r["tier"]), "supply_permille": int(r["supply_permille"])}
	return {"tier": "plains", "supply_permille": 1000}


## A land cell the landmarks count: not water, a real polygon.
static func _is_land(cell: Dictionary) -> bool:
	return String(cell.get("water", "")) == "" \
		and (cell["vertex_ids"] as PackedInt32Array).size() >= 3


## Whether a outranks b as a high point: higher, or level with a lower id.
static func _above(ha: float, a: int, hb: float, b: int) -> bool:
	return ha > hb or (ha == hb and a < b)


## The high points (land cells above every land neighbour; a tie goes to the
## lower id, so a plateau keeps one) and the low points (land cells below
## every neighbour and touching no water — a basin, not a shore), each in id
## order. Pure on a cells dict so a test can hand-build one.
static func extremes(cells: Dictionary) -> Dictionary:
	var high := PackedInt32Array()
	var low := PackedInt32Array()
	var ids := cells.keys()
	ids.sort()
	for id: int in ids:
		var c: Dictionary = cells[id]
		if not _is_land(c):
			continue
		var h := float(c["height"])
		var is_high := true
		var is_low := true
		var land_nb := 0
		for n: int in c["neighbor_ids"]:
			if not cells.has(n):
				continue
			var nc: Dictionary = cells[n]
			if not _is_land(nc):
				is_low = false
				continue
			land_nb += 1
			var hn := float(nc["height"])
			if not _above(h, id, hn, n):
				is_high = false
			if not _above(hn, n, h, id):
				is_low = false
		if land_nb == 0:
			continue
		if is_high:
			high.append(id)
		elif is_low:
			low.append(id)
	return {"high": high, "low": low}


## The land cells out to `rings` rings round `id` (not `id` itself), in
## breadth-first order.
static func _ring_cells(repo: DataRepository, id: int, rings: int) -> Array:
	var seen := {id: true}
	var frontier := [id]
	var out: Array = []
	for _r in rings:
		var next: Array = []
		for c: int in frontier:
			for n: int in repo.cells[c]["neighbor_ids"]:
				if seen.has(n) or not repo.cells.has(n) or not _is_land(repo.cells[n]):
					continue
				seen[n] = true
				next.append(n)
				out.append(n)
		frontier = next
	return out


## Metres the cell stands above the mean of its landmark_ring rings (negative
## below it); 0 with no land round it.
static func local_edge_m(repo: DataRepository, id: int) -> int:
	var ring := _ring_cells(repo, id, int(repo.bal("landmark_ring")))
	if ring.is_empty():
		return 0
	var sum := 0
	for n: int in ring:
		sum += metres_of_cell(repo, n)
	return metres_of_cell(repo, id) - int(round(float(sum) / ring.size()))


## Every landmark of the pack, biggest prominence first (ties by cell id),
## named; cached per pack.
static func landmarks(repo: DataRepository) -> Array:
	if _landmarks_map == repo.map_id and not _landmarks.is_empty():
		return _landmarks
	var e := extremes(repo.cells)
	var out: Array = []
	var floor_m := int(repo.bal("landmark_min_prominence_m"))
	for kind: String in ["high", "low"]:
		for id: int in e[kind]:
			var edge := local_edge_m(repo, id)
			var prom := absi(edge)
			if prom < floor_m:
				continue
			out.append({"cell": id, "kind": kind, "metres": metres_of_cell(repo, id),
				"prominence": prom, "lod": _lod(repo, prom), "name": "",
				"pos": MapTerrain.cell_center(repo, repo.cells[id])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["prominence"] == b["prominence"]:
			return int(a["cell"]) < int(b["cell"])
		return a["prominence"] > b["prominence"])
	_name_all(repo, out)
	_landmarks = out
	_landmarks_map = repo.map_id
	return out


static func landmark_at(repo: DataRepository, cell: int) -> Dictionary:
	for m: Dictionary in landmarks(repo):
		if int(m["cell"]) == cell:
			return m
	return {}


static func _lod(repo: DataRepository, prominence: int) -> int:
	if prominence >= int(repo.bal("landmark_lod_far_m")):
		return 0
	if prominence >= int(repo.bal("landmark_lod_mid_m")):
		return 1
	return 2


## Names in prominence order, so the biggest gets its first choice: every
## override is reserved FIRST, in its own pass, so a hand-authored name
## always wins its cell and can never be handed to a more prominent
## landmark that is only generated afterward; the rest are then named from
## the patterns, by a hash of the cell over the nearest town, then the
## next-nearest, never a name already taken (by an override or a generated
## name).
static func _name_all(repo: DataRepository, marks: Array) -> void:
	var taken := {}
	for m: Dictionary in marks:
		var id := int(m["cell"])
		if repo.landmark_name_overrides.has(id):
			m["name"] = String(repo.landmark_name_overrides[id])
			taken[m["name"]] = true
	var towns := repo.burgs.keys()
	towns.sort()
	for m: Dictionary in marks:
		if String(m["name"]) != "":
			continue
		var id := int(m["cell"])
		var patterns: Array = repo.landmark_names.get(String(m["kind"]), [])
		if patterns.is_empty():
			continue
		var at: Vector2 = m["pos"]
		var by_dist := towns.duplicate()
		by_dist.sort_custom(func(a: String, b: String) -> bool:
			var da := at.distance_squared_to(Vector2(float(repo.burgs[a]["x"]), float(repo.burgs[a]["y"])))
			var db := at.distance_squared_to(Vector2(float(repo.burgs[b]["x"]), float(repo.burgs[b]["y"])))
			return da < db if da != db else a < b)
		var start := posmod(str(id).hash(), patterns.size())
		for town: String in by_dist:
			var label := String(repo.burgs[town].get("label", town))
			for k in patterns.size():
				var name := String(patterns[(start + k) % patterns.size()]).replace("{town}", label)
				if not taken.has(name):
					m["name"] = name
					break
			if String(m["name"]) != "":
				break
		taken[m["name"]] = true
