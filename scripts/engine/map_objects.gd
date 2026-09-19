class_name MapObjects
extends RefCounted
## The world map's interactive objects (spec 2026-09-08): what lies under a
## point, which town pins show at a given zoom, and the text on each info
## card. Pure functions over a DataRepository and the pack's index bitmaps —
## no Nodes, no RNG, no game state — so GUT can pin every rule headless.
## Coordinates are native map px; the view converts screen radii by its scale.

## min_burg_pop sentinel: only capitals get pins.
const CAPITALS_ONLY := -1

const GROUP_WORDS := {"roads": "Road", "trails": "Trail", "searoutes": "Sea route"}
const FEATURE_WORDS := {"walls": "Walled", "citadel": "Citadel", "temple": "Temple",
	"plaza": "Plaza", "shanty": "Shanty town"}
## Tie-break among lines at the same distance: the more significant one wins.
const LINE_RANK := {"roads": 0, "trails": 1, "searoutes": 2}
const RIVER_RANK := 3
## Distances closer than this are "the same" for the tie-break (native px).
const LINE_TIE_EPS := 0.001

## LOD rule from balance.csv. view_scale = screen px per native map px.
static func min_burg_pop_for_scale(repo: DataRepository, view_scale: float) -> int:
	if view_scale >= repo.bal("map_lod_village_scale"):
		return 0
	if view_scale >= repo.bal("map_lod_town_scale"):
		return int(repo.bal("map_lod_town_pop"))
	return CAPITALS_ONLY

static func burg_visible(b: Dictionary, min_pop: int) -> bool:
	if String(b.get("is_capital", "0")) == "1":
		return true
	if min_pop < 0:
		return false
	return int(float(b.get("population", "0"))) >= min_pop

## Priority: nearest pin (markers, then LOD-visible burgs) within pick_radius,
## else nearest line (routes, then rivers) within line_radius, else the land
## under the point (ids from the three bitmaps), else water.
## `cell_img` (world_cell_index.png) makes a land pixel answer as its MANOR
## (MANOR_SYSTEM.md §6): the view passes it while a layer that shows
## manors is up, and null on the political map, where land means province.
static func object_at(repo: DataRepository, state_img: Image, province_img: Image,
		biome_img: Image, native: Vector2, pick_radius: float, line_radius: float,
		min_burg_pop: int, state: GameState = null, cell_img: Image = null) -> Dictionary:
	var pin := nearest_pin(repo, native, pick_radius, min_burg_pop)
	if not pin.is_empty():
		return pin
	var line := nearest_line(repo, native, line_radius)
	if not line.is_empty():
		return line
	var px := Vector2i(native.floor())
	# The bitmaps are geometry and never go stale — provinces do not move.
	# Ownership does, so the kingdom here is the province's CURRENT holder
	# rather than the state id baked into the pack at import.
	var sid := MapIndex.state_at(state_img, px)
	if sid < 0:
		return {"kind": "water"}
	var pid := MapIndex.id_at(province_img, px)
	if cell_img != null:
		var cell := MapIndex.id_at(cell_img, px)
		if cell >= 0 and repo.manors.has(cell):
			return {"kind": "manor", "cell": cell, "state_id": owner_state_id(repo, state, pid, sid),
				"province_id": pid, "x": native.x, "y": native.y}
	return {"kind": "land", "state_id": owner_state_id(repo, state, pid, sid),
		"province_id": pid,
		"biome_id": MapIndex.biome_at(biome_img, px),
		"x": native.x, "y": native.y}

## The state id of whoever holds province `pid` now; `fallback` when the
## province is unknown (an older pack, or a pixel outside every province).
static func owner_state_id(repo: DataRepository, state: GameState, pid: int,
		fallback: int) -> int:
	var prov: Dictionary = repo.province_by_id(pid)
	if prov.is_empty():
		return fallback
	var owner := MapOwnership.owner_of(repo, state, String(prov["province_code"]))
	var king: Dictionary = repo.kingdoms.get(owner, {})
	return int(king["state_id"]) if not king.is_empty() else fallback

## --- Terrain symbols (owner request 2026-09-12) -------------------------
## The land tells its biome through SYMBOLS — a wood, a hill, a stand of
## reeds — rather than through its tint, the way a drawn map does. Which
## symbol and how thickly is data/terrain_art.csv: the FIRST row whose height
## band or biome matches a cell wins, so "a summit is a summit whatever grows
## on it" comes before the biome rules.
##
## Placement is derived from the cell id, never from RNG: the same pack always
## decorates the same way, across runs and across saves, with nothing to seed
## and nothing to store.
static var _decor_cache: Dictionary = {}

static func forget_decor() -> void:
	_decor_cache.clear()
	_sea_decor_cache.clear()
	_estate_cache.clear()
	_estate_rows_cache.clear()

## A stable float in [0, 1) for an integer — an integer hash, masked to 32
## bits at every step so it cannot drift with the word size.
static func hash01(n: int) -> float:
	var x := (n * 0x9E3779B1) & 0xFFFFFFFF
	x = ((x ^ (x >> 15)) * 0x85EBCA6B) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF
	x = x ^ (x >> 16)
	return float(x & 0xFFFFFF) / 16777216.0

## A smooth field over the sheet in [0, 1): value noise on a lattice of
## `wavelength` native px, hashed from the lattice corner and `seed`,
## smoothstepped between corners, two octaves. Low where marks gather (a
## cell is picked when its score is under the row's density). Pure and
## deterministic — no RNG, nothing to store.
static func decor_field(p: Vector2, wavelength: float, seed_value: int) -> float:
	var total := 0.0
	var norm := 0.0
	var amp := 1.0
	var w := maxf(wavelength, 1.0)
	for octave in 2:
		var q := p / w
		var ix := int(floor(q.x))
		var iy := int(floor(q.y))
		var fx := q.x - float(ix)
		var fy := q.y - float(iy)
		fx = fx * fx * (3.0 - 2.0 * fx)
		fy = fy * fy * (3.0 - 2.0 * fy)
		var s := seed_value * 1000003 + octave * 7919
		var a := hash01(ix * 73856093 + iy * 19349663 + s)
		var b := hash01((ix + 1) * 73856093 + iy * 19349663 + s)
		var c := hash01(ix * 73856093 + (iy + 1) * 19349663 + s)
		var d := hash01((ix + 1) * 73856093 + (iy + 1) * 19349663 + s)
		total += lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy) * amp
		norm += amp
		amp *= 0.5
		w *= 0.5
	return total / norm

## The terrain_art row a land cell takes, or {} for bare ground.
## Rows carry `clump` (how many marks) and `spread` (how far across the cell
## they scatter, as a fraction of its radius) alongside the size.
static func decor_row(repo: DataRepository, cell: Dictionary) -> Dictionary:
	var h := float(cell["height"])
	var biome := int(cell["biome_id"])
	for row: Dictionary in repo.terrain_art:
		var lo := String(row["min_height"])
		var hi := String(row["max_height"])
		if lo != "" and h < float(lo):
			continue
		if hi != "" and h >= float(hi):
			continue
		var want := String(row["biome_id"])
		if want != "" and int(want) != biome:
			continue
		if lo == "" and hi == "" and want == "":
			continue  # a row that matches everything is a mistake, not a rule
		return row
	return {}

## Every terrain symbol on the sheet: [{pos, texture, height}] in native
## coordinates, sorted back to front so the nearer one overlaps. Cached per
## repository — the pack's cells never move.
static func terrain_decor(repo: DataRepository) -> Array:
	var key := repo.get_instance_id()
	if _decor_cache.has(key):
		return _decor_cache[key]
	var out: Array = []
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		var row := decor_row(repo, cell)
		if row.is_empty():
			continue
		# Woods gather into FORESTS and peaks into RANGES (owner 2026-09-14):
		# a row's `cluster` share of the pick comes from a smooth field over
		# the sheet rather than the cell's own hash, so neighbouring cells are
		# chosen together and whole tracts fill while others stay open.
		var cluster := clampf(float(row.get("cluster", "0")), 0.0, 1.0)
		var score := hash01(id)
		var centre := MapTerrain.cell_center(repo, cell)
		if cluster > 0.0:
			score = lerpf(score, decor_field(centre, repo.bal("map_decor_cluster_px"),
				int(repo.bal("map_decor_cluster_seed"))), cluster)
		if score >= float(row["density"]) * repo.bal("map_decor_density"):
			continue
		# One tree is not a forest and one peak is not a range (owner request
		# 2026-09-12): a chosen cell gets `clump` SMALL marks scattered inside
		# it, not one big one on its centre. Offsets and per-mark size come
		# from the cell id, so the wood stands in the same place every run.
		var reach := MapTerrain.cell_radius(repo, cell) * float(row["spread"])
		var base := float(row["height_px"]) * repo.bal("map_decor_scale")
		for k in maxi(int(row["clump"]), 1):
			var a := hash01(id * 7919 + k * 104729) * TAU
			# sqrt spreads the marks evenly over the disc instead of bunching
			# them in the middle.
			var d := sqrt(hash01(id * 31337 + k * 15485863)) * reach
			out.append({
				"pos": centre + Vector2(cos(a), sin(a)) * d,
				"texture": String(row["texture"]),
				"height": base * (0.8 + 0.4 * hash01(id * 2654435761 + k * 40503))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).y < (b["pos"] as Vector2).y)
	_decor_cache[key] = out
	return out

## The estate a manor wears in the MANORS view (owner 2026-09-13/14: ONE
## drawing per manor, its house and its INDUSTRY's workplace together —
## the scattered houses-and-fields marks it replaced were the owner's
## veto). The rows of data/manor_estates.csv for the manor's focus (the
## first industry's rows when its focus has none), and among them the
## last whose min_people the manor's ledger people reach: {} for no rows.
static func estate_tier(repo: DataRepository, focus_code: String, people: float) -> Dictionary:
	var rows := estate_rows(repo, focus_code)
	var out: Dictionary = {}
	for row: Dictionary in rows:
		if people >= float(row["min_people"]):
			out = row
	return out

## An industry's rows ascending by min_people; the first industry's when
## the code has none. Cached per repo.
static var _estate_rows_cache: Dictionary = {}

static func estate_rows(repo: DataRepository, focus_code: String) -> Array:
	var rkey := repo.get_instance_id()
	if not _estate_rows_cache.has(rkey):
		var grouped: Dictionary = {}
		var order: Array = []
		for row: Dictionary in repo.manor_estates:
			var code := String(row["focus_code"])
			if not grouped.has(code):
				grouped[code] = []
				order.append(code)
			(grouped[code] as Array).append(row)
		for code: String in grouped:
			(grouped[code] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["min_people"]) < float(b["min_people"]))
		_estate_rows_cache[rkey] = {"by": grouped, "first": String(order[0]) if not order.is_empty() else ""}
	var cache: Dictionary = _estate_rows_cache[rkey]
	var by: Dictionary = cache["by"]
	if by.has(focus_code):
		return by[focus_code]
	return by.get(String(cache["first"]), [])

## [{pos, texture, height, cell, tier, focus, flip, foot}] in native
## coordinates: every manor without a town, its estate drawing centred on
## its cell, ONE height for all (map_manor_estate_px x map_decor_scale,
## never taller than map_manor_estate_fit of the cell's radius), mirrored
## by the cell id's hash for variety. A manor with a town carries none
## (the town drawing is there). Cached on the ledger, whose people set the
## sizes, and the chosen focuses, which set the industries.
static var _estate_cache: Dictionary = {}

static func manor_estates(repo: DataRepository, state: GameState) -> Array:
	var key := hash([repo.get_instance_id(), 0 if state == null else state.world.hash(),
		0 if state == null else state.manor_focus.hash()])
	if _estate_cache.has(key):
		return _estate_cache[key]
	var out: Array = []
	if repo.manor_estates.is_empty():
		_estate_cache[key] = out
		return out
	var ids: Array = repo.manors.keys()
	ids.sort()
	var px := repo.bal("map_manor_estate_px") * repo.bal("map_decor_scale")
	var fit := repo.bal("map_manor_estate_fit")
	var foot := repo.bal("map_manor_estate_foot")
	for id: int in ids:
		if MapManors.burg_of(repo, id) != "":
			continue
		var cell: Dictionary = repo.cells.get(id, {})
		if cell.is_empty():
			continue
		var pop := float(MapManors.people_of(repo, state, id))
		var focus := MapManors.focus_of(repo, state, id)
		var row := estate_tier(repo, focus, pop)
		if row.is_empty():
			continue
		var radius := MapTerrain.cell_radius(repo, cell)
		out.append({
			"pos": MapTerrain.cell_center(repo, cell),
			"texture": String(row["texture"]),
			"height": minf(px, radius * fit),
			"cell": id, "tier": int(float(row["tier"])), "focus": String(row["focus_code"]),
			"flip": hash01(id * 48271) > 0.5, "foot": foot})
	_estate_cache[key] = out
	return out

## How far out each estate still shows (owner 2026-09-14: zoomed out, only a
## scattering; zoomed in, every one). The sheet is laid in square grids of
## `base_px` x 2^L native px for L = 0..levels-1; in each square of a level
## the best estate — the largest tier, ties to the lower hash of its cell —
## is that square's representative. An estate's rank is the COARSEST level
## it represents (every estate represents level 0). The squares nest and
## the order is total, so a representative of a coarse square also wins
## every finer square it stands in: drawing the levels at or above some L
## shows an even scattering that only grows as L falls. Pure; returns an
## Array of ints parallel to `estates`.
static func estate_lod_ranks(estates: Array, base_px: float, levels: int) -> Array:
	var ranks: Array = []
	ranks.resize(estates.size())
	ranks.fill(0)
	var better := func(i: int, j: int) -> bool:
		var ti := int(estates[i].get("tier", 0))
		var tj := int(estates[j].get("tier", 0))
		if ti != tj:
			return ti > tj
		var hi := hash01(int(estates[i].get("cell", i)) * 69069)
		var hj := hash01(int(estates[j].get("cell", j)) * 69069)
		return hi < hj if hi != hj else int(estates[i].get("cell", i)) < int(estates[j].get("cell", j))
	for level in range(1, maxi(levels, 1)):
		var side := maxf(base_px, 1.0) * float(1 << level)
		var best: Dictionary = {}
		for i in estates.size():
			var p: Vector2 = estates[i]["pos"]
			var key := Vector2i(int(floor(p.x / side)), int(floor(p.y / side)))
			if not best.has(key) or better.call(i, int(best[key])):
				best[key] = i
		for key: Vector2i in best:
			ranks[int(best[key])] = level
	return ranks

## The sea's decoration — ships and a whale, the way an old chart fills its
## open water (owner request 2026-09-13): [{pos, texture, height}] in native
## coordinates from data/sea_art.csv. The pack's sea cells are few and huge
## (beria: 1314 cells, none more than two hops from land), so marks are not
## one per cell: candidates are spread over each sea cell by its AREA, one
## per map_sea_decor_spacing_px square of its bounding box, hashed from the
## cell id, kept inside the polygon, thinned by map_sea_decor_density, and
## dropped within the row's min_shore_px of the land coast so they stay off
## the hatching, and kept map_sea_decor_min_gap_px apart from one another
## (owner 2026-09-13: spread out, never overlapping) — a candidate too
## near any mark already placed is dropped, in cell order, so the result
## is still the same every run. The row is drawn by weight. The same determinism as
## terrain_decor: nothing to seed or store. No monsters (owner ruling
## 2026-09-12): a whale is an animal. Cached per repository.
static var _sea_decor_cache: Dictionary = {}

static func sea_decor(repo: DataRepository) -> Array:
	var key := repo.get_instance_id()
	if _sea_decor_cache.has(key):
		return _sea_decor_cache[key]
	var out: Array = []
	if repo.sea_art.is_empty():
		_sea_decor_cache[key] = out
		return out
	var spacing := maxf(repo.bal("map_sea_decor_spacing_px"), 1.0)
	var gap_sq := pow(repo.bal("map_sea_decor_min_gap_px"), 2.0)
	var take := repo.bal("map_sea_decor_density")
	var scale := repo.bal("map_sea_decor_scale")
	var shore := shore_points(repo)
	var total_weight := 0.0
	for row: Dictionary in repo.sea_art:
		total_weight += float(row["weight"])
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if not MapTerrain.is_sea(cell):
			continue
		var poly := PackedVector2Array()
		for v: int in (cell["vertex_ids"] as PackedInt32Array):
			poly.append(repo.vertices[v] as Vector2)
		if poly.size() < 3:
			continue
		var box := MapGeometry.bounds(poly)
		var quota := int(box.size.x * box.size.y / (spacing * spacing)) + 1
		for q in quota:
			var p := box.position + Vector2(hash01(id * 7919 + q * 104729),
				hash01(id * 31337 + q * 15485863)) * box.size
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			if hash01(id * 6700417 + q * 999983) >= take:
				continue
			var pick := hash01(id * 2654435761 + q * 40503) * total_weight
			var row: Dictionary = repo.sea_art[0]
			for r: Dictionary in repo.sea_art:
				row = r
				pick -= float(r["weight"])
				if pick < 0.0:
					break
			if _to_shore(p, shore) < float(row["min_shore_px"]):
				continue
			if _crowded(p, out, gap_sq):
				continue
			out.append({"pos": p, "texture": String(row["texture"]),
				"height": float(row["height_px"]) * scale})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).y < (b["pos"] as Vector2).y)
	_sea_decor_cache[key] = out
	return out

## Every point of every LAND coast loop — the shore a sea mark keeps away
## from. Lake shores do not bound the sea.
static func shore_points(repo: DataRepository) -> PackedVector2Array:
	var out := PackedVector2Array()
	for row: Dictionary in repo.coasts:
		if String(row.get("kind", "land")) == "land":
			out.append_array(row["polyline"])
	return out

## Whether a spot lies within the minimum gap of a mark already placed.
static func _crowded(p: Vector2, placed: Array, gap_sq: float) -> bool:
	for m: Dictionary in placed:
		if p.distance_squared_to(m["pos"]) < gap_sq:
			return true
	return false

static func _to_shore(p: Vector2, shore: PackedVector2Array) -> float:
	var best := INF
	for s: Vector2 in shore:
		best = minf(best, p.distance_squared_to(s))
	return sqrt(best)

## Whether the pack's points of interest are on the sheet at all. Owner
## ruling 2026-09-12: they are off — the map is for realms and settlements —
## and this is the ONE place that decides, so a click can never pick
## something that is not drawn.
static func markers_visible(repo: DataRepository) -> bool:
	return repo.bal("map_show_markers") > 0.0

static func nearest_pin(repo: DataRepository, native: Vector2, radius: float,
		min_burg_pop: int) -> Dictionary:
	var best := {}
	var best_d := radius
	for code: String in (repo.markers if markers_visible(repo) else {}):
		var m: Dictionary = repo.markers[code]
		var d := native.distance_to(Vector2(float(m["x"]), float(m["y"])))
		if d <= best_d:
			best_d = d
			best = {"kind": "marker", "code": code}
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if not burg_visible(b, min_burg_pop):
			continue
		var d := native.distance_to(Vector2(float(b["x"]), float(b["y"])))
		if d < best_d:  # strict: a marker on the same spot keeps priority
			best_d = d
			best = {"kind": "burg", "code": code}
	return best

static func nearest_line(repo: DataRepository, native: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	var best_rank := 99
	for code: String in repo.routes:
		var row: Dictionary = repo.routes[code]
		var d := _line_distance(row, native, radius)
		var rank := int(LINE_RANK.get(String(row.get("group", "")), 2))
		if _closer(d, rank, best_d, best_rank):
			best_d = d
			best_rank = rank
			best = {"kind": "route", "code": code}
	for code: String in repo.rivers:
		var d := _line_distance(repo.rivers[code], native, radius)
		if _closer(d, RIVER_RANK, best_d, best_rank):
			best_d = d
			best_rank = RIVER_RANK
			best = {"kind": "river", "code": code}
	return best

## Nearer wins; at (float-)equal distance the higher-ranked line does
## (road > trail > sea route > river), so a trail stub ending on a road never
## steals the road's click. A candidate exactly at the radius still counts.
static func _closer(d: float, rank: int, best_d: float, best_rank: int) -> bool:
	if d > best_d + LINE_TIE_EPS:
		return false
	if d < best_d - LINE_TIE_EPS:
		return true
	return rank < best_rank

static func _line_distance(row: Dictionary, native: Vector2, radius: float) -> float:
	var bbox: Rect2 = row["bbox"]
	if not bbox.grow(radius).has_point(native):
		return INF
	return MapGeometry.distance_to_polyline(native, row["polyline"])

## Closest burg regardless of LOD ("" if the pack has none).
static func nearest_burg(repo: DataRepository, native: Vector2) -> String:
	var best := ""
	var best_d := INF
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		var d := native.distance_to(Vector2(float(b["x"]), float(b["y"])))
		if d < best_d:
			best_d = d
			best = code
	return best

## Tooltip text: the object's name ("" for land/water, which have no pin).
static func label_of(repo: DataRepository, obj: Dictionary, state: GameState = null) -> String:
	match String(obj.get("kind", "")):
		"burg":
			return String(repo.burgs.get(obj["code"], {}).get("label", ""))
		"marker":
			return String(repo.markers.get(obj["code"], {}).get("label", ""))
		"route":
			return String(repo.routes.get(obj["code"], {}).get("label", ""))
		"river":
			return String(repo.rivers.get(obj["code"], {}).get("label", ""))
		"army":
			return String(repo.world_table("military", "regiments")
				.get(obj["code"], {}).get("label", ""))
		"manor":
			return MapManors.label_of(repo, int(obj.get("cell", -1)))
		"landmark":
			var id := int(obj.get("cell", -1))
			var m := Elevation.landmark_at(repo, id)
			if m.is_empty():
				return ""
			return String(m["name"]) + "\n" + "\n".join(landmark_lines(repo, state, id))
	return ""

## Card text per kind: {title, lines, ask}. {} means "nothing to show".
static func describe(repo: DataRepository, obj: Dictionary,
		state: GameState = null) -> Dictionary:
	match String(obj.get("kind", "")):
		"kingdom":
			return _describe_kingdom(repo,
				_kingdom_by_state(repo, int(obj.get("state_id", -1))), state)
		"burg":
			return _describe_burg(repo, String(obj["code"]))
		"route":
			return _describe_route(repo, String(obj["code"]))
		"river":
			return _describe_river(repo, String(obj["code"]))
		"marker":
			return _describe_marker(repo, String(obj["code"]))
		"army":
			return _describe_army(repo, String(obj["code"]), state)
		"land":
			return _describe_land(repo, obj, state)
		"manor":
			return _describe_manor(repo, int(obj.get("cell", -1)), state)
	return {}

## A manor's entry: its card's title and a few lines, for the floating
## card; the detail column asks for manor_card itself.
static func _describe_manor(repo: DataRepository, cell: int, state: GameState) -> Dictionary:
	var card := manor_card(repo, state, cell)
	if card.is_empty():
		return {}
	var lines: Array[String] = []
	for f in card["fields"]:
		lines.append("%s: %s" % [String(f[0]), String(f[1])])
	return {"title": card["title"], "lines": lines, "ask": card["ask"]}

static func _kingdom_by_state(repo: DataRepository, sid: int) -> Dictionary:
	for row: Dictionary in repo.kingdoms.values():
		if int(row["state_id"]) == sid:
			return row
	return {}

static func _province_by_id(repo: DataRepository, pid: int) -> Dictionary:
	return repo.province_by_id(pid)

static func _label(table: Dictionary, code: String) -> String:
	return String(table.get(code, {}).get("label", code))

## "where — holder", collapsed: no "Wickhampia — Wickhampia" when the
## holder's house wears the province's own name, no leading " — " when
## there is no province to name (an off-pack cell) but a holder still
## reads, and just the province when there is no holder at all.
static func _landmark_where_line(where: String, holder: String) -> String:
	if holder == "":
		return where
	if where == "" or where == holder:
		return holder
	return "%s — %s" % [where, holder]

## A landmark's facts, one per line (spec 2026-09-19-map3d-heights §4):
## height · tier · biome; province — holder; the garrison's supply; the
## edge over the land round it and what it is worth in a fight.
static func landmark_lines(repo: DataRepository, state: GameState, cell: int) -> PackedStringArray:
	var c: Dictionary = repo.cells[cell]
	var tier := Elevation.tier_of(repo, float(c["height"]))
	var biome := String((repo.biomes.get(int(c["biome_id"]), {}) as Dictionary).get("label", ""))
	var province := MapManors.province_of(repo, cell, state)
	var where := _label(repo.provinces, province) if province != "" else ""
	var holder := MapManors.owner_of(repo, state, cell)
	var mult := float(int(tier["supply_permille"])) / 1000.0
	var edge := Elevation.local_edge_m(repo, cell)
	var pct := (ArmySystem.height_factor(repo, absi(edge)) - 1000) / 10
	var out := PackedStringArray()
	out.append("%d m · %s · %s" % [Elevation.metres_of_cell(repo, cell), String(tier["tier"]).capitalize(), biome])
	out.append(_landmark_where_line(where, holder))
	out.append("Garrison: supplies ×%.1f (%s)" % [mult, String(tier["tier"])])
	if edge >= 0:
		out.append("%d m above the land around — +%d%% in a fight against it" % [edge, pct])
	else:
		out.append("%d m below the land around — −%d%% fighting up out of it" % [-edge, pct])
	return out

## Native px -> "N unit" via map_info.csv (falls back to px when absent).
static func format_distance(repo: DataRepository, native_px: float) -> String:
	var scale := float(repo.map_info.get("distance_scale", "1"))
	var unit := String(repo.map_info.get("distance_unit", "px"))
	return "%d %s" % [roundi(native_px * scale), unit]

## The kingdom overview lines (the pre-2026-09-08 card, unchanged in content).
static func _kingdom_lines(repo: DataRepository, row: Dictionary,
		state: GameState = null) -> Array[String]:
	var code := String(row["kingdom_code"])
	# Counted from who holds what NOW, not from the pack's starting map, so a
	# conquered province leaves one card and appears on the other's.
	var held := MapOwnership.provinces_of(repo, state, code)
	var province_count := held.size()
	var held_set: Dictionary = {}
	for pc in held:
		held_set[pc] = true
	var town_count := 0
	for b: Dictionary in repo.burgs.values():
		if held_set.has(String(b["province_code"])):
			town_count += 1
	var neighbors: Array[String] = []
	for n: String in String(row.get("neighbor_codes", "")).split("|", false):
		neighbors.append(_label(repo.kingdoms, n))
	var court: Array[String] = []
	for role: Dictionary in repo.roles:
		if String(role.get("kingdom", "")) == code:
			court.append(String(role["display_name"]))
	var lines: Array[String] = [
		"Capital: %s" % _label(repo.burgs, String(row.get("capital_burg", ""))),
		"Provinces: %d" % province_count,
		"Towns: %d" % town_count,
		"Population: %s" % row.get("population", "—"),
		"Neighbors: %s" % (", ".join(neighbors) if not neighbors.is_empty() else "—"),
	]
	if not court.is_empty():
		lines.append("Court: %s" % ", ".join(court))
	return lines

static func _describe_kingdom(repo: DataRepository, row: Dictionary,
		state: GameState = null) -> Dictionary:
	if row.is_empty():
		return {}
	var label := String(row["label"])
	return {"title": label, "lines": _kingdom_lines(repo, row, state),
		"ask": "What do we know of %s?" % label}

static func _describe_burg(repo: DataRepository, code: String) -> Dictionary:
	var b: Dictionary = repo.burgs.get(code, {})
	if b.is_empty():
		return {}
	var label := String(b["label"])
	var where := "%s, %s" % [_label(repo.provinces, String(b["province_code"])),
		_label(repo.kingdoms, String(b["kingdom_code"]))]
	var lines: Array[String] = []
	lines.append(("Capital of %s" if String(b.get("is_capital", "0")) == "1" else "Town in %s") % where)
	lines.append("Population: %s" % b.get("population", "—"))
	var traits: Array[String] = []
	if String(b.get("is_port", "0")) == "1":
		traits.append("Port")
	for f: String in String(b.get("features", "")).split("|", false):
		traits.append(String(FEATURE_WORDS.get(f, f.capitalize())))
	if not traits.is_empty():
		lines.append(", ".join(traits))
	var roads := 0
	for r: Dictionary in repo.routes.values():
		if String(r["from_burg"]) == code or String(r["to_burg"]) == code:
			roads += 1
	if roads > 0:
		lines.append("Roads: %d" % roads)
	return {"title": label, "lines": lines, "ask": "What do we know of %s?" % label}

static func _describe_route(repo: DataRepository, code: String) -> Dictionary:
	var r: Dictionary = repo.routes.get(code, {})
	if r.is_empty():
		return {}
	var label := String(r["label"])
	var lines: Array[String] = [String(GROUP_WORDS.get(String(r["group"]), "Route"))]
	var from := String(r["from_burg"])
	var to := String(r["to_burg"])
	if from != "" and to != "":
		lines.append("From %s to %s" % [_label(repo.burgs, from), _label(repo.burgs, to)])
	elif from != "" or to != "":
		lines.append("Ends at %s" % _label(repo.burgs, from if from != "" else to))
	lines.append("Length: %s" % format_distance(repo, float(r["length"])))
	return {"title": label, "lines": lines, "ask": "What do we know of the %s?" % label}

static func _describe_river(repo: DataRepository, code: String) -> Dictionary:
	var rv: Dictionary = repo.rivers.get(code, {})
	if rv.is_empty():
		return {}
	var label := String(rv["label"])
	var lines: Array[String] = [String(rv.get("type", "River")),
		"Length: %s" % format_distance(repo, float(rv["length"]))]
	var through: Array[String] = []
	for k: String in String(rv.get("kingdom_codes", "")).split("|", false):
		through.append(_label(repo.kingdoms, k))
	if not through.is_empty():
		lines.append("Flows through: %s" % ", ".join(through))
	return {"title": label, "lines": lines, "ask": "What do we know of the %s?" % label}

static func _describe_marker(repo: DataRepository, code: String) -> Dictionary:
	var m: Dictionary = repo.markers.get(code, {})
	if m.is_empty():
		return {}
	var label := String(m["label"])
	var lines: Array[String] = [humanize(String(m.get("type", "")))]
	var legend := String(m.get("legend", ""))
	if legend != "":
		lines.append(legend)
	return {"title": label, "lines": lines, "ask": "What is known of %s?" % label}

## Land: the province first, then terrain and the nearest town, then the
## kingdom overview so the old kingdom card stays one click away.
static func _describe_land(repo: DataRepository, obj: Dictionary,
		state: GameState = null) -> Dictionary:
	var kingdom := _kingdom_by_state(repo, int(obj.get("state_id", -1)))
	if kingdom.is_empty():
		return {}
	var province := _province_by_id(repo, int(obj.get("province_id", -1)))
	var title := String(province.get("label", kingdom["label"]))
	var lines: Array[String] = [String(kingdom["label"])]
	var biome: Dictionary = repo.biomes.get(int(obj.get("biome_id", -1)), {})
	if not biome.is_empty():
		lines.append("Terrain: %s" % biome["label"])
	var here := Vector2(float(obj.get("x", 0.0)), float(obj.get("y", 0.0)))
	var near := nearest_burg(repo, here)
	if near != "":
		var b: Dictionary = repo.burgs[near]
		var dist := here.distance_to(Vector2(float(b["x"]), float(b["y"])))
		lines.append("Nearest town: %s (%s)" % [b["label"], format_distance(repo, dist)])
	lines.append_array(_kingdom_lines(repo, kingdom, state))
	return {"title": title, "lines": lines, "ask": "What do we know of %s?" % title}

## "hot-springs" -> "Hot springs".
static func humanize(kind: String) -> String:
	var t := kind.replace("-", " ").replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else ""

## The house holding a province: the pack's house_bindings.csv when it binds
## one, else a house named after the province's capital town (so foreign
## land always has a holder without authoring anything).
static func house_of(repo: DataRepository, province_code: String) -> String:
	return "House " + house_name_of(repo, province_code)

## The same house as a bare family name — what Character.family_name and
## GameState.manor_owner carry (MapManors).
static func house_name_of(repo: DataRepository, province_code: String) -> String:
	var bound := String(repo.house_bindings.get(province_code, ""))
	if bound != "":
		return bound
	var prov: Dictionary = repo.provinces.get(province_code, {})
	var cap: Dictionary = repo.burgs.get(String(prov.get("capital_burg", "")), {})
	return String(cap.get("label", prov.get("label", province_code)))

## Whether the player's realm holds the province NOW.
static func province_is_players(repo: DataRepository, state: GameState,
		province_code: String) -> bool:
	return MapOwnership.owner_of(repo, state, province_code) == repo.resolve_realm("player_realm")

## The province panel's text (user request 2026-09-09). The player's own
## provinces get the full account; a foreign province shows only what is
## commonly known — its name, its kingdom, its house, its seat. "known" says
## which ("full" / "basic"). Follows live ownership.
static func describe_province(repo: DataRepository, state: GameState,
		province_code: String) -> Dictionary:
	var prov: Dictionary = repo.provinces.get(province_code, {})
	if prov.is_empty():
		return {}
	var label := String(prov["label"])
	var title := String(prov.get("full_name", ""))
	if title == "":
		title = label
	var owner := MapOwnership.owner_of(repo, state, province_code)
	var lines: Array[String] = [
		"Province of %s" % _label(repo.kingdoms, owner),
		"Held by %s" % house_of(repo, province_code),
		"Seat: %s" % _label(repo.burgs, String(prov.get("capital_burg", ""))),
	]
	var ask := "What do we know of %s?" % label
	if not province_is_players(repo, state, province_code):
		return {"title": title, "lines": lines, "ask": ask, "known": "basic"}
	# Towns, largest first.
	var towns: Array = []
	for b: Dictionary in repo.burgs.values():
		if String(b["province_code"]) == province_code:
			towns.append(b)
	towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(float(a["population"])) > int(float(b["population"])))
	var names: Array[String] = []
	for i in mini(towns.size(), int(repo.bal("province_card_max_towns"))):
		names.append(String(towns[i]["label"]))
	lines.append("Towns: %d%s" % [towns.size(), (" — " + ", ".join(names)) if not names.is_empty() else ""])
	# Population, live through the ledger.
	var urban: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.urban_population" % province_code)
	var rural: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % province_code)
	if urban != null and rural != null:
		lines.append("Population: %d (%d in towns, %d rural)" % [int(urban) + int(rural), int(urban), int(rural)])
	else:
		lines.append("Population: %s" % prov.get("population", "—"))
	var scale := float(repo.map_info.get("distance_scale", "1"))
	var unit := String(repo.map_info.get("distance_unit", "px"))
	lines.append("Area: %d %s²" % [roundi(float(prov.get("area", 0)) * scale * scale), unit])
	var biome: Dictionary = repo.biomes.get(int(float(prov.get("biome_id", "0"))), {})
	if not biome.is_empty():
		lines.append("Terrain: %s" % biome["label"])
	# Goods the province's towns produce, by units.
	var goods_units: Dictionary = {}
	for row: Dictionary in repo.world_table("economy", "production").values():
		var b: Dictionary = repo.burgs.get(String(row["burg_code"]), {})
		if String(b.get("province_code", "")) != province_code:
			continue
		var g := String(row["good_code"])
		goods_units[g] = float(goods_units.get(g, 0.0)) + float(row.get("units", 0))
	if not goods_units.is_empty():
		var gs := goods_units.keys()
		gs.sort_custom(func(a: String, b: String) -> bool:
			return float(goods_units[a]) > float(goods_units[b]) \
				or (float(goods_units[a]) == float(goods_units[b]) and a < b))
		var top: Array[String] = []
		for i in mini(gs.size(), int(repo.bal("province_card_max_goods"))):
			top.append(_label(repo.world_table("economy", "goods"), String(gs[i])))
		lines.append("Produces: %s" % ", ".join(top))
	# Regiments quartered here.
	var regs: Array[String] = []
	for row: Dictionary in repo.world_table("military", "regiments").values():
		if String(row.get("province_code", "")) == province_code:
			regs.append(String(row["label"]))
	if not regs.is_empty():
		lines.append("Regiments: %s" % ", ".join(regs))
	# Hazard zones touching it.
	for row: Dictionary in repo.world_table("society", "zones").values():
		if province_code in String(row.get("province_codes", "")).split("|", false):
			lines.append("Hazard: %s (%s)" % [row["label"], String(row["type"]).to_lower()])
	# The last time it changed hands.
	if state != null:
		for i in range(state.territory_log.size() - 1, -1, -1):
			var t: Dictionary = state.territory_log[i]
			if String(t["province"]) == province_code:
				lines.append("Changed hands: from %s to %s, tick %d (%s)" % [
					_label(repo.kingdoms, String(t["from"])), _label(repo.kingdoms, String(t["to"])),
					int(t["tick"]), String(t["reason"])])
				break
	return {"title": title, "lines": lines, "ask": ask, "known": "full"}

## --- Info cards (user request 2026-09-09, after Azgaar's burg editor) ------
## A card is structured, not lines: {title, subtitle, kingdom_code, initial,
## fields: [[label, value], ...], features: [feature keys], production:
## [{label, units, tag}], wealth, treasury, center: Vector2, known}. The
## detail column renders it with heraldry, a field grid, glyph rows, and a
## map preview around `center`.

## The tag a good is shown under: the first of its tags that has a glyph row
## (tag_<name> in resource_icons.csv), else "".
static func good_tag(repo: DataRepository, good_code: String) -> String:
	var g: Dictionary = repo.world_row("economy", "goods", good_code)
	for t: String in String(g.get("tags", "")).split("|", false):
		if repo.resource_icons.has("tag_" + t):
			return "tag_" + t
	return ""

## Goods produced by these burgs, summed by good, largest first.
static func production_of(repo: DataRepository, burg_codes: Array) -> Array:
	var units: Dictionary = {}
	var wanted: Dictionary = {}
	for b in burg_codes:
		wanted[String(b)] = true
	for row: Dictionary in repo.world_table("economy", "production").values():
		if not wanted.has(String(row["burg_code"])):
			continue
		var g := String(row["good_code"])
		units[g] = float(units.get(g, 0.0)) + float(row.get("units", 0))
	var out: Array = []
	for g: String in units:
		out.append({"good": g, "label": _label(repo.world_table("economy", "goods"), g),
			"units": float(units[g]), "tag": good_tag(repo, g)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["units"]) > float(b["units"]) \
			or (float(a["units"]) == float(b["units"]) and String(a["good"]) < String(b["good"])))
	return out

static func burg_card(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var b: Dictionary = repo.burgs.get(code, {})
	if b.is_empty():
		return {}
	var prov: Dictionary = repo.provinces.get(String(b["province_code"]), {})
	var owner := MapOwnership.owner_of(repo, state, String(b["province_code"]))
	var kingdom: Dictionary = repo.kingdoms.get(owner, {})
	var econ: Dictionary = repo.world_row("economy", "burgs", code)
	var culture: Dictionary = repo.world_row("society", "cultures", String(b.get("culture_code", "")))
	var fields: Array = [
		["Group", String(b.get("group", "")).replace("_", " ").capitalize()],
		["Type", String(b.get("type", ""))],
		["Culture", String(culture.get("label", b.get("culture_code", "")))],
		["Population", String(b.get("population", "—"))],
	]
	var features: Array = []
	if String(b.get("is_port", "0")) == "1":
		features.append("port")
	for f: String in String(b.get("features", "")).split("|", false):
		features.append(f)
	var label := String(b["label"])
	return {
		"kind": "burg", "code": code, "title": label,
		"subtitle": "%s, %s" % [String(prov.get("full_name", prov.get("label", ""))),
			String(kingdom.get("full_name", kingdom.get("label", "")))],
		"kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": fields, "features": features,
		"production": production_of(repo, [code]),
		"wealth": float(econ.get("product", 0.0)), "treasury": float(econ.get("treasury", 0.0)),
		"center": Vector2(float(b["x"]), float(b["y"])),
		"ask": "What do we know of %s?" % label, "known": "full",
	}

## The player's own province in full; foreign land only by what is commonly
## known (name, kingdom, house, seat).
static func province_card(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var prov: Dictionary = repo.provinces.get(code, {})
	if prov.is_empty():
		return {}
	var owner := MapOwnership.owner_of(repo, state, code)
	var kingdom: Dictionary = repo.kingdoms.get(owner, {})
	var label := String(prov["label"])
	var title := String(prov.get("full_name", ""))
	if title == "":
		title = label
	var card := {
		"kind": "province", "code": code, "title": title,
		"subtitle": String(kingdom.get("full_name", kingdom.get("label", ""))),
		"kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": [["Held by", house_of(repo, code)],
			["Seat", _label(repo.burgs, String(prov.get("capital_burg", "")))]],
		"features": [], "production": [], "wealth": 0.0, "treasury": 0.0,
		"center": Vector2(float(prov.get("center_x", 0.0)), float(prov.get("center_y", 0.0))),
		"ask": "What do we know of %s?" % label,
		"known": "full" if province_is_players(repo, state, code) else "basic",
	}
	if card["known"] == "basic":
		return card
	var towns: Array = []
	for b: Dictionary in repo.burgs.values():
		if String(b["province_code"]) == code:
			towns.append(b)
	towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(float(a["population"])) > int(float(b["population"])))
	var names: Array[String] = []
	var codes: Array = []
	for t: Dictionary in towns:
		codes.append(String(t["burg_code"]))
	for i in mini(towns.size(), int(repo.bal("province_card_max_towns"))):
		names.append(String(towns[i]["label"]))
	var urban: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.urban_population" % code)
	var rural: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % code)
	var fields: Array = card["fields"]
	# Who holds the province's manors (MANOR_SYSTEM.md §4) — the crown's
	# own land is known in this detail; abroad it is not.
	fields.append(["Manors", holdings_text(repo, state, code)])
	var controller := MapManors.controller_of(repo, state, code)
	fields.append(["Controlled by", "the crown" if controller == MapManors.crown(state)
		else ("House " + controller if controller != "" else "no one")])
	if urban != null and rural != null:
		fields.append(["Population", "%d (%d in towns)" % [int(urban) + int(rural), int(urban)]])
	else:
		fields.append(["Population", String(prov.get("population", "—"))])
	var scale := float(repo.map_info.get("distance_scale", "1"))
	fields.append(["Area", "%d %s²" % [roundi(float(prov.get("area", 0)) * scale * scale),
		String(repo.map_info.get("distance_unit", "px"))]])
	var biome: Dictionary = repo.biomes.get(int(float(prov.get("biome_id", "0"))), {})
	if not biome.is_empty():
		fields.append(["Terrain", String(biome["label"])])
	fields.append(["Towns", "%d%s" % [towns.size(), (": " + ", ".join(names)) if not names.is_empty() else ""]])
	var regs: Array[String] = []
	for row: Dictionary in repo.world_table("military", "regiments").values():
		if String(row.get("province_code", "")) == code:
			regs.append(String(row["label"]))
	if not regs.is_empty():
		fields.append(["Regiments", ", ".join(regs)])
	for row: Dictionary in repo.world_table("society", "zones").values():
		if code in String(row.get("province_codes", "")).split("|", false):
			fields.append(["Hazard", "%s (%s)" % [row["label"], String(row["type"]).to_lower()]])
	if state != null:
		for i in range(state.territory_log.size() - 1, -1, -1):
			var t: Dictionary = state.territory_log[i]
			if String(t["province"]) == code:
				fields.append(["Changed hands", "from %s to %s, tick %d (%s)" % [
					_label(repo.kingdoms, String(t["from"])), _label(repo.kingdoms, String(t["to"])),
					int(t["tick"]), String(t["reason"])]])
				break
	var wealth := 0.0
	var treasury := 0.0
	for c in codes:
		var e: Dictionary = repo.world_row("economy", "burgs", String(c))
		wealth += float(e.get("product", 0.0))
		treasury += float(e.get("treasury", 0.0))
	card["production"] = production_of(repo, codes)
	card["wealth"] = wealth
	card["treasury"] = treasury
	return card

## The manor card (MANOR_SYSTEM.md §3): the same shape as province_card,
## plus `cell`, `buildings` and `actions` — the orders the crown could give
## for this manor, each with ActionSystem's own reason when it cannot, so
## the column's buttons say why they are dim. Full inside the crown's
## realm, basic abroad.
static func manor_card(repo: DataRepository, state: GameState, cell: int) -> Dictionary:
	if not MapManors.is_manor(repo, cell):
		return {}
	var province := MapManors.province_of(repo, cell, state)
	var prov: Dictionary = repo.provinces.get(province, {})
	var owner := MapOwnership.owner_of(repo, state, province)
	var kingdom: Dictionary = repo.kingdoms.get(owner, {})
	var label := MapManors.label_of(repo, cell)
	var house := MapManors.owner_of(repo, state, cell)
	var crowns := MapManors.is_crowns(repo, state, cell)
	var subtitle := String(prov.get("full_name", prov.get("label", "")))
	if not kingdom.is_empty():
		subtitle += " · " + String(kingdom.get("label", ""))
	var card := {
		"kind": "manor", "code": MapManors.code_of(repo, cell), "cell": cell, "title": label,
		"subtitle": subtitle, "kingdom_code": owner, "initial": label.substr(0, 1),
		"fields": [["Held by", "The crown" if crowns else ("House " + house if house != "" else "no one")],
			["Province", String(prov.get("label", province))]],
		"features": [], "production": [], "wealth": 0.0, "treasury": 0.0,
		"buildings": [], "works": [], "slots": 0, "slot_actions": [], "actions": [],
		"center": MapTerrain.cell_center(repo, repo.cells.get(cell, {"vertex_ids": PackedInt32Array()})),
		"ask": "What do we know of %s?" % label,
		"known": "full" if (province != "" and province_is_players(repo, state, province)) else "basic",
	}
	var fields: Array = card["fields"]
	var burg := MapManors.burg_of(repo, cell)
	if burg != "":
		fields.append(["Seat", _label(repo.burgs, burg)])
	# The card's face (owner 2026-09-14): the estate's painting over the card,
	# and the manor's facts as icons — a short value beside each, the whole
	# of it in its tooltip. `fields` stays for tools and tests.
	var stats: Array = []
	card["stats"] = stats
	card["rates"] = []
	card["painting"] = estate_painting(repo, state, cell)
	stats.append(_stat("manor_owner", "The crown" if crowns else (house if house != "" else "no one"),
		"Held by — %s" % ("the crown" if crowns else ("House " + house if house != "" else "no one"))))
	stats.append(_stat("manor_province", String(prov.get("label", province)), "Province — %s" % subtitle))
	if burg != "":
		stats.append(_stat("manor_seat", _label(repo.burgs, burg),
			"Seat — the town of %s stands in it" % _label(repo.burgs, burg)))
	if card["known"] == "basic":
		# Across the border a manor that touches the realm may be bought
		# (owner 2026-09-14): its card offers that one order.
		if state != null and not MapManors.is_crowns(repo, state, cell) \
				and String(MapManors.purchase_kind(repo, state, cell)["kind"]) == "foreign":
			card["actions"] = manor_actions(repo, state, cell)
		return card
	var cell_row: Dictionary = repo.cells.get(cell, {})
	var biome: Dictionary = repo.biomes.get(int(cell_row.get("biome_id", -1)), {})
	var terrain := String(biome.get("label", ""))
	for n: int in (cell_row.get("neighbor_ids", PackedInt32Array()) as PackedInt32Array):
		if MapTerrain.is_sea(repo.cells.get(n, {})):
			terrain += " · coast"
			break
	if terrain != "":
		fields.append(["Terrain", terrain])
	fields.append(["Land", "%d%%" % roundi(MapManors.land_value_of(repo, cell) * 100.0)])
	var scale := float(repo.map_info.get("distance_scale", "1"))
	fields.append(["Area", "%d %s²" % [roundi(MapManors.area_of(repo, cell) * scale * scale),
		String(repo.map_info.get("distance_unit", "px"))]])
	# One economy on the card (2026-09-14): people, tax and yield are all
	# ManorEconomy's whole-number month, the same figures the tick settles
	# and the ECONOMY column sums.
	var line := ManorEconomy.line_of(repo, state, cell, state.tick)
	var people := int(line["people"])
	var town := MapManors.burg_of(repo, cell)
	if town != "":
		fields.append(["People", "%d (%s stands in it)" % [people,
			String(repo.burgs.get(town, {}).get("label", town))]])
	else:
		fields.append(["People", str(people)])
	fields.append(["Tax", "%d gold a month" % int(line["tax"])])
	# The chief good (owner 2026-09-13): what the manor works at, what it
	# ships of that good in a month, and how far a switch has settled in.
	var focus_code := MapManors.focus_of(repo, state, cell)
	var focus: Dictionary = repo.manor_focus.get(focus_code, {})
	if not focus.is_empty():
		var good := String(focus.get("good_code", ""))
		var text := "%s — %d %s a month" % [String(focus.get("label", focus_code)),
			int((line["units"] as Dictionary).get(good, 0)),
			String(repo.world_row("economy", "goods", good).get("label", good)).to_lower()]
		var ramp := MapManors.focus_ramp(repo, state, cell)
		if ramp < 1.0:
			text += " (settling in, %d%%)" % roundi(ramp * 100.0)
		fields.append(["Chief good", text])
	else:
		fields.append(["Chief good", "none the land allows"])
	var tier := MapManors.burg_of(repo, cell) == ""
	if tier and not repo.manor_estates.is_empty():
		var est := estate_tier(repo, MapManors.focus_of(repo, state, cell), float(people))
		if not est.is_empty():
			var industry := String((repo.manor_focus.get(String(est["focus_code"]), {}) as Dictionary).get("label", est["focus_code"])).to_lower()
			fields.append(["Estate", "%s, size %d of %d" % [industry, int(float(est["tier"])),
				estate_rows(repo, String(est["focus_code"])).size()]])
	fields.append(["Defence", str(roundi(MapManors.defence_of(repo, state, cell)))])
	var built: Array = MapManors.buildings_of(state, cell)
	card["buildings"] = built
	var names: Array[String] = []
	for b: String in built:
		names.append(String((repo.manor_buildings.get(b, {}) as Dictionary).get("label", b)))
	# Works in progress (2026-09-13): the slot row draws them dim with the
	# days left; the field names them too.
	var works: Array = []
	for w: Dictionary in MapManors.works_of(state, cell):
		var b := String(w["building"])
		var left := MapManors.work_days_left(state, cell, b)
		var name := String((repo.manor_buildings.get(b, {}) as Dictionary).get("label", b))
		works.append({"building": b, "label": name, "days_left": left,
			"progress": MapManors.work_progress(state, cell, b)})
		names.append("%s (%d days to go)" % [name, left])
	card["works"] = works
	card["slots"] = MapManors.slots_of(repo, cell)
	fields.append(["Buildings", ", ".join(names) if not names.is_empty() else "none"])
	fields.append(["Slots", "%d of %d taken" % [MapManors.slots_used(state, cell), MapManors.slots_of(repo, cell)]])
	fields.append(["Value", "%d gold" % roundi(MapManors.base_value_of(repo, state, cell))])
	if crowns:
		fields.append(["Sells for", "%d gold" % roundi(MapManors.sell_price_of(repo, state, cell))])
	else:
		fields.append(["Asking price", "%d gold" % roundi(MapManors.price_of(repo, state, cell))])
	var land_pct := roundi(MapManors.land_value_of(repo, cell) * 100.0)
	var area := roundi(MapManors.area_of(repo, cell) * scale * scale)
	var unit := String(repo.map_info.get("distance_unit", "px"))
	if terrain != "":
		stats.append(_stat("manor_terrain", terrain.split(" · ")[0], "Terrain — %s" % terrain))
	stats.append(_stat("manor_land", "%d%%" % land_pct,
		"Land — how kindly the ground is to farming: %d%%" % land_pct))
	stats.append(_stat("manor_area", "%d %s²" % [area, unit], "Area — %d %s²" % [area, unit]))
	stats.append(_stat("manor_people", _short_num(float(people)),
		"People — %d live on the manor%s" % [people, ", its town included" if town != "" else ""]))
	var tariff := int(line["tariff"])
	stats.append(_stat("manor_tax", "%d/mo" % int(line["tax"]), "Tax — %d gold a month%s" % [int(line["tax"]),
		(", %d of it the town's tariff" % tariff) if tariff > 0 else ""]))
	stats.append(_stat("manor_strategic", "%d/mo" % int(line["strategic"]),
		"Strategic goods — %d gold's worth a month" % int(line["strategic"])))
	stats.append(_stat("manor_civil", "%d/mo" % int(line["civil"]),
		"Civil goods — %d gold's worth a month" % int(line["civil"])))
	var focus_now: Dictionary = repo.manor_focus.get(MapManors.focus_of(repo, state, cell), {})
	stats.append(_stat("manor_focus", String(focus_now.get("label", "none")),
		"Chief good — %s" % _field_text(fields, "Chief good")))
	var estate_text := _field_text(fields, "Estate")
	if estate_text != "":
		stats.append(_stat("manor_estate", estate_text.get_slice(", ", estate_text.get_slice_count(", ") - 1).replace("size ", ""),
			"Estate — %s" % estate_text))
	stats.append(_stat("manor_defence", str(roundi(MapManors.defence_of(repo, state, cell))),
		"Defence — how hard the manor is to take"))
	stats.append(_stat("manor_slots", "%d/%d" % [MapManors.slots_used(state, cell), MapManors.slots_of(repo, cell)],
		"Building slots — %s; buildings: %s" % [_field_text(fields, "Slots"), _field_text(fields, "Buildings")]))
	stats.append(_stat("manor_value", _short_num(MapManors.base_value_of(repo, state, cell)),
		"Value — %s" % _field_text(fields, "Value")))
	if crowns:
		stats.append(_stat("manor_price", _short_num(MapManors.sell_price_of(repo, state, cell)),
			"Sells for — %s" % _field_text(fields, "Sells for")))
	else:
		stats.append(_stat("manor_price", _short_num(MapManors.price_of(repo, state, cell)),
			"Asking price — %s" % _field_text(fields, "Asking price")))
	# What it makes a month, good by good (owner 2026-09-14): the same line
	# the month's settlement reads.
	card["rates"] = production_rates(repo, line)
	if state != null:
		for i in range(state.manor_log.size() - 1, -1, -1):
			var t: Dictionary = state.manor_log[i]
			if int(t.get("cell", -1)) == cell and t.has("to"):
				fields.append(["Changed hands", "to %s, tick %d (%s)" % [
					"the crown" if String(t["to"]) == MapManors.crown(state) else "House " + String(t["to"]),
					int(t["tick"]), String(t["reason"])]])
				break
	if burg != "":
		card["production"] = production_of(repo, [burg])
		var e: Dictionary = repo.world_row("economy", "burgs", burg)
		card["wealth"] = float(e.get("product", 0.0))
		card["treasury"] = float(e.get("treasury", 0.0))
	card["actions"] = manor_actions(repo, state, cell)
	card["slot_actions"] = slot_actions(repo, state, cell)
	return card

## One fact of a manor card: an icon key (data/resource_icons.csv), a short
## value for beside it, and the whole of it for the tooltip.
static func _stat(key: String, text: String, tooltip: String) -> Dictionary:
	return {"key": key, "text": text, "tooltip": tooltip}

## The value of a named row in a card's fields, or "".
static func _field_text(fields: Array, name: String) -> String:
	for f: Array in fields:
		if String(f[0]) == name:
			return String(f[1])
	return ""

## 1234 -> "1234", 45678 -> "45.7k", 1234567 -> "1.2M": a value that fits
## beside an icon; the tooltip carries the exact figure.
static func _short_num(v: float) -> String:
	if absf(v) >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if absf(v) >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return str(roundi(v))

## The painting of a manor's estate (library B-, owner 2026-09-14): the
## `painting` of the manor_estates.csv row its industry and people choose —
## the same row as its map drawing, so the card and the map show one estate.
## "" when there are no rows or the row names none.
static func estate_painting(repo: DataRepository, state: GameState, cell: int) -> String:
	var row := estate_tier(repo, MapManors.focus_of(repo, state, cell),
		float(MapManors.people_of(repo, state, cell)))
	return String(row.get("painting", ""))

## A manor's output a month, good by good, from its ManorEconomy line:
## [{good, label, units, gold, pool, tag, texture}], most units first, ties
## by code — every good its chief work, its buildings and its town make.
static func production_rates(repo: DataRepository, line: Dictionary) -> Array:
	var out: Array = []
	var units: Dictionary = line.get("units", {})
	for good: String in units:
		var n := int(units[good])
		if n <= 0:
			continue
		var ge := repo.goods_economy_of(good)
		out.append({"good": good, "units": n,
			"label": String(repo.world_row("economy", "goods", good).get("label", good)),
			"gold": n * int(ge["price_gold"]), "pool": String(ge["pool"]),
			"tag": good_tag(repo, good), "texture": String(repo.goods_art.get(good, "")),
			"icon": String(repo.goods_icons.get(good, ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["good"]) < String(b["good"]) if int(a["units"]) == int(b["units"]) \
			else int(a["units"]) > int(b["units"]))
	return out

## One DEMOLISH order per building standing or begun on a crown manor,
## validated — the slot row's cross buttons. [{action_code, params,
## building, label, refund, error}].
static func slot_actions(repo: DataRepository, state: GameState, cell: int) -> Array:
	if state == null or not MapManors.is_crowns(repo, state, cell):
		return []
	var code := MapManors.code_of(repo, cell)
	var specs: Array = []
	var all: Array = MapManors.buildings_of(state, cell)
	for w: Dictionary in MapManors.works_of(state, cell):
		all.append(String(w["building"]))
	var actions := ActionSystem.new(repo)
	for b: String in all:
		var row: Dictionary = repo.manor_buildings.get(b, {})
		var refund := roundf(float(row.get("civil_cost", 0)) * repo.bal("manor_demolish_refund"))
		var spec := {"action_code": "MANOR_DEMOLISH", "params": {"manor": code, "building": b},
			"building": b, "refund": refund,
			"label": "Pull down the %s — %d civil goods back" % [
				String(row.get("label", b)).to_lower(), int(refund)]}
		spec["error"] = actions.validate(ActionRequest.make("MANOR_DEMOLISH", spec["params"]), state)
		specs.append(spec)
	return specs

## The orders the crown could give for a manor, each validated: [{action_code,
## label, params, error}]. Buy or seize what another house holds; sell or
## build on the crown's own. Seizing appears only while manor_seize_enabled.
static func manor_actions(repo: DataRepository, state: GameState, cell: int) -> Array:
	if state == null:
		return []
	var code := MapManors.code_of(repo, cell)
	var specs: Array = []
	if MapManors.is_crowns(repo, state, cell):
		specs.append({"action_code": "MANOR_SELL", "params": {"manor": code},
			"label": "SELL — %d gold to your purse" % roundi(MapManors.sell_price_of(repo, state, cell))})
		# The chief goods the land allows, less the one it works (2026-09-13),
		# ahead of the buildings: the choice the economy turns on.
		var working := MapManors.focus_of(repo, state, cell)
		for f: String in MapManors.focuses_for(repo, cell):
			if f == working:
				continue
			var row_f: Dictionary = repo.manor_focus[f]
			specs.append({"action_code": "MANOR_FOCUS", "params": {"manor": code, "focus": f},
				"label": "WORK %s — %dg" % [String(row_f["label"]).to_upper(), int(float(row_f["switch_cost_gold"]))]})
		# Tier by tier (owner 2026-09-14), and only what the manor's ground takes:
		# a quay is not offered inland. What still needs another building is
		# offered with the reason as its error.
		var codes: Array = repo.manor_buildings.keys()
		codes.sort_custom(func(a: String, b2: String) -> bool:
			var ta := int(float((repo.manor_buildings[a] as Dictionary).get("tier", 1)))
			var tb := int(float((repo.manor_buildings[b2] as Dictionary).get("tier", 1)))
			return a < b2 if ta == tb else ta < tb)
		for b: String in codes:
			if MapManors.has_building(state, cell, b) or MapManors.is_building(state, cell, b):
				continue
			if not MapManors.building_land_ok(repo, state, cell, b):
				continue
			var row: Dictionary = repo.manor_buildings[b]
			# A building is paid for in CIVIL GOODS, not gold (spec §5), so
			# the button says so; gold only hurries it (HURRY below).
			specs.append({"action_code": "MANOR_BUILD", "params": {"manor": code, "building": b},
				"label": "BUILD %s — %d civil, %dd" % [String(row["label"]).to_upper(),
					int(float(row.get("civil_cost", 0))), int(float(row.get("build_days", 0)))]})
		# One HURRY per work in progress: gold off the days still to run.
		var per_click := int(repo.bal("manor_rush_days_per_click"))
		var rush_gold := per_click * int(repo.bal("build_rush_gold_per_day"))
		for w: Dictionary in MapManors.works_of(state, cell):
			var b_w := String(w["building"])
			var row_w: Dictionary = repo.manor_buildings.get(b_w, {})
			specs.append({"action_code": "MANOR_RUSH",
				"params": {"manor": code, "building": b_w, "days": per_click},
				"label": "HURRY %s — %dg" % [String(row_w.get("label", b_w)).to_upper(), rush_gold]})
	else:
		# The button says which purse pays (owner 2026-09-14): your own for
		# the realm, the crown's treasury across the border.
		var how := MapManors.purchase_kind(repo, state, cell)
		var purse := "the crown's treasury" if String(how["kind"]) == "foreign" else "your purse"
		specs.append({"action_code": "MANOR_BUY", "params": {"manor": code},
			"label": "BUY — %d gold from %s" % [roundi(MapManors.price_of(repo, state, cell)), purse]})
		if repo.bal("manor_seize_enabled") > 0.0:
			specs.append({"action_code": "MANOR_SEIZE", "params": {"manor": code},
				"label": "SEIZE BY FORCE"})
	var actions := ActionSystem.new(repo)
	for spec: Dictionary in specs:
		spec["error"] = actions.validate(ActionRequest.make(String(spec["action_code"]), spec["params"]), state)
	return specs

## "12 — the crown 7, House Weighhouse 5": a province's manors by holder.
static func holdings_text(repo: DataRepository, state: GameState, province_code: String) -> String:
	var counts := MapManors.holdings_of_province(repo, state, province_code)
	var total := 0
	var parts: Array[String] = []
	var houses: Array = counts.keys()
	houses.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	for h: String in houses:
		total += int(counts[h])
		parts.append("%s %d" % ["the crown" if h == MapManors.crown(state) else "House " + h, int(counts[h])])
	return "%d — %s" % [total, ", ".join(parts)] if total > 0 else "none"

## The settlement drawing for a burg (data/settlement_art.csv): its group,
## and for groups that distinguish it, whether it has walls. {} when the
## pack's group has no art.
static func settlement_art(repo: DataRepository, b: Dictionary) -> Dictionary:
	var group := String(b.get("group", ""))
	var walled := "walls" in String(b.get("features", "")).split("|", false)
	for row: Dictionary in repo.settlement_art:
		if String(row["group"]) != group:
			continue
		var want := String(row.get("walled", ""))
		if want == "" or (want == "1") == walled:
			return row
	return {}

## ONE OF A TIER'S PAINTED DRAWINGS (owner 2026-09-16: "每一种定居点给我生成
## 10种不同的variants image，随机apply上去"). A tier's row names `variants`
## drawings, installed beside its own file as <tier>_01.png ..; a settlement
## wears the one ITS OWN CODE picks, so two towns of the same size are not
## twins. The pick is a hash, never the RNG: the same burg must wear the same
## drawing every run, every save and every reload (determinism, CLAUDE.md §2).
## The row is DUPLICATED — repo.settlement_art is shared table data.
static func settlement_variant(row: Dictionary, code: String) -> Dictionary:
	if row.is_empty():
		return row
	var count := int(row.get("variants", 0))
	if count <= 1:
		return row
	var n := 1
	if code != "":
		n = abs(code.hash()) % count + 1
	var texture := String(row.get("texture", ""))
	if texture == "":
		return row
	var picked := row.duplicate()
	picked["texture"] = "%s/%s_%02d.%s" % [
		texture.get_base_dir(), String(row.get("tier", "")), n, texture.get_extension()]
	return picked

## The drawing a settlement wears NOW (owner 2026-09-15: the painted drawing
## stays where it is but changes with its development): its pack row
## (settlement_art), then promoted by data/settlement_growth.csv while a rule
## holds — its manor's live people past a row's min_people, or one of a row's
## buildings standing on the manor. Promotion only: a settlement is never
## drawn smaller than the pack made it. Without a state, the pack row. Whatever
## row it lands on, the burg's own variant of it is what comes back.
static func settlement_look(repo: DataRepository, state: GameState, b: Dictionary) -> Dictionary:
	var code := String(b.get("burg_code", ""))
	var art := settlement_art(repo, b)
	if art.is_empty() or state == null or repo.settlement_growth.is_empty():
		return settlement_variant(art, code)
	var cell := int(MapEconomy.burg_cells(repo).get(code, -1))
	if cell < 0:
		return settlement_variant(art, code)
	var people := MapManors.people_of(repo, state, cell)
	var buildings := MapManors.buildings_of(state, cell)
	var tier := String(art["tier"])
	for _step in repo.settlement_growth.size():
		var grown := ""
		for rule: Dictionary in repo.settlement_growth:
			if String(rule["from_tier"]) != tier:
				continue
			var min_people := String(rule.get("min_people", "")).strip_edges()
			if min_people != "" and people < int(min_people):
				continue
			var needs := String(rule.get("building", "")).split("|", false)
			if not needs.is_empty():
				var standing := false
				for need: String in needs:
					if buildings.has(need):
						standing = true
						break
				if not standing:
					continue
			grown = String(rule["to_tier"])
			break
		if grown == "" or grown == tier:
			break
		tier = grown
	if tier == String(art["tier"]):
		return settlement_variant(art, code)
	for row: Dictionary in repo.settlement_art:
		if String(row["tier"]) == tier:
			return settlement_variant(row, code)
	return settlement_variant(art, code)

## The point-of-interest icon for a marker row (data/marker_art.csv by the
## marker's type), or {} when the type has none and the view falls back to
## its diamond.
static func marker_art(repo: DataRepository, m: Dictionary) -> Dictionary:
	return repo.marker_art.get(String(m.get("type", "")), {})

## --- Regiments (user request 2026-09-10) -------------------------------
## The military layer draws the realm's own regiments where the pack puts
## them. The counts per arm live in data/maps/<id>/military/regiments.csv;
## these read them so the map and the MILITARY panel agree on every number.

## Every regiment of a kingdom, in the pack's order.
static func regiments_of(repo: DataRepository, kingdom_code: String) -> Array:
	var out: Array = []
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) == kingdom_code:
			out.append(r)
	return out

## Heads under a regiment's banner: every arm in unit_types added up.
static func regiment_size(repo: DataRepository, regiment: Dictionary) -> float:
	var total := 0.0
	for unit: String in repo.world_table("military", "unit_types"):
		total += float(regiment.get(unit, 0))
	return total

## The arm a regiment is mostly made of — what its map marker wears. Ties go
## to the earlier arm in unit_types, so the choice is data-ordered.
static func regiment_arm(repo: DataRepository, regiment: Dictionary) -> String:
	var best := ""
	var most := -1.0
	for unit: String in repo.world_table("military", "unit_types"):
		var n := float(regiment.get(unit, 0))
		if n > most:
			most = n
			best = unit
	return best

## The regiment the crown's own banner flies over: the LAND regiment quartered
## nearest the kingdom's capital (ties to the earlier code). "" when the
## kingdom has no land regiment or no capital. The military layer draws it
## with a crown.
static func royal_regiment(repo: DataRepository, kingdom_code: String) -> String:
	var realm: Dictionary = repo.kingdoms.get(kingdom_code, {})
	var capital: Dictionary = repo.burgs.get(String(realm.get("capital_burg", "")), {})
	if capital.is_empty():
		return ""
	var seat := Vector2(float(capital["x"]), float(capital["y"]))
	var best := ""
	var best_d := INF
	for r: Dictionary in regiments_of(repo, kingdom_code):
		if String(r.get("is_naval", "0")) == "1":
			continue
		var code := String(r["regiment_code"])
		var d := seat.distance_squared_to(Vector2(float(r["x"]), float(r["y"])))
		if d < best_d or (d == best_d and code < best):
			best_d = d
			best = code
	return best

static func _describe_army(repo: DataRepository, code: String, state: GameState = null) -> Dictionary:
	var r: Dictionary = repo.world_table("military", "regiments").get(code, {})
	if r.is_empty():
		return {}
	var label := String(r["label"])
	var lines: Array[String] = ["%s of %s" % [
		"Fleet" if String(r.get("is_naval", "0")) == "1" else "Regiment",
		_label(repo.kingdoms, String(r["kingdom_code"]))]]
	var province := String(r.get("province_code", ""))
	if province != "":
		lines.append("Quartered in %s" % _label(repo.provinces, province))
	for unit: String in repo.world_table("military", "unit_types"):
		var n := float(r.get(unit, 0))
		if n > 0.0:
			lines.append("%s: %d" % [String((repo.resource_icons.get(unit, {}) as Dictionary)
				.get("label", unit.capitalize())), int(n)])
	lines.append("Under arms: %d" % int(regiment_size(repo, r)))
	# The player's own regiment shows its state and its march (owner
	# 2026-09-19: a click on a counter shows the regiment).
	var st := ArmySystem.state_of(repo, state, code)
	if not st.is_empty():
		var use := ArmySystem.supply_use(repo, r)
		var supplies := int(st["supplies"])
		lines.append("Morale: %d / 100" % int(st["morale"]))
		lines.append("Wounded: %d" % int(st["wounded"]))
		lines.append("Supplies: %d (%s months)" % [supplies,
			("%.1f" % (float(supplies) / float(use))) if use > 0 else "-"])
		lines.append("Training: %s" % ArmySystem.training_grade(repo, int(st["training"])))
		lines.append("Strength: %s" % ArmySystem.strength_grade(repo, state, code))
		lines.append("Ground: %s" % ArmySystem.terrain_label(repo, r))
		lines.append("March: %.1f km a day" % ArmySystem.speed_km_per_day(repo, state, code))
	return {"title": label, "lines": lines,
		"ask": "What is the state of the %s?" % label}

## The painted piece a regiment is drawn with, whose painting heads its card
## (owner 2026-09-15, data/army_art.csv): the fleet for a naval regiment, the
## royal piece for the crown's own (royal_regiment), else its chief arm.
static func army_piece(repo: DataRepository, regiment: Dictionary) -> String:
	if String(regiment.get("is_naval", "0")) == "1":
		return "fleet"
	if String(regiment.get("regiment_code", "")) == royal_regiment(repo, String(regiment.get("kingdom_code", ""))):
		return "royal"
	return regiment_arm(repo, regiment)

## A regiment's fact card (owner 2026-09-15: "军队的 card info 还是 2D 彩绘风格"):
## its piece's painting over the card, and its facts as icons — each arm it
## musters, the whole host under arms, and where it is quartered, and, for
## the player's own regiment with a state, its terrain, morale, wounded,
## supplies, training and strength (ArmySystem, owner 2026-09-17).
static func army_card(repo: DataRepository, code: String, state: GameState = null) -> Dictionary:
	var r: Dictionary = repo.world_table("military", "regiments").get(code, {})
	if r.is_empty():
		return {}
	var label := String(r["label"])
	var kingdom := String(r["kingdom_code"])
	var naval := String(r.get("is_naval", "0")) == "1"
	var province := String(r.get("province_code", ""))
	var total := int(regiment_size(repo, r))
	var piece := army_piece(repo, r)
	var stats: Array = []
	for unit: String in repo.world_table("military", "unit_types"):
		var n := int(float(r.get(unit, 0)))
		if n <= 0:
			continue
		var unit_label := String((repo.resource_icons.get(unit, {}) as Dictionary).get("label", unit.capitalize()))
		stats.append(_stat(unit, str(n), "%s — %d" % [unit_label, n]))
	var st := ArmySystem.state_of(repo, state, code) if state != null else {}
	if st.is_empty():
		stats.append(_stat("army", str(total), "Under arms — %d" % total))
	else:
		var wounded := int(st["wounded"])
		stats.append(_stat("army", "%d (%d wounded)" % [total, wounded],
			"Under arms — %d, of whom %d are wounded" % [total, wounded]))
	var fields: Array = [["Under arms", str(total)]]
	if province != "":
		var where := _label(repo.provinces, province)
		stats.append(_stat("manor_province", where, "Quartered in %s" % where))
		fields.append(["Quartered in", where])
	if not st.is_empty():
		var ground := ArmySystem.terrain_label(repo, r)
		stats.append(_stat("army_terrain", ground, "Quartered on %s" % ground.to_lower()))
		var metres := ArmySystem.elevation_of(repo, r)
		var tier := ArmySystem.height_tier(repo, r)
		var mult := float(int(tier["supply_permille"])) / 1000.0
		stats.append(_stat("army_height", "%d m · ×%.1f" % [metres, mult],
			"Height — %d m, %s: supplies are used ×%.1f here. In a fight each 100 m above the foe is +%d%% (at most +%d%%), and below it as much less" % [
				metres, String(tier["tier"]), mult,
				int(repo.bal("army_height_bonus_permille_per_100m")) / 10,
				int(repo.bal("army_height_bonus_cap_permille")) / 10]))
		stats.append(_stat("army_morale", str(int(st["morale"])), "Morale — %d of 100" % int(st["morale"])))
		var back := ArmySystem.wound_recovery(repo, int(st["wounded"]))
		stats.append(_stat("army_wounded", "+%d / mo" % back,
			"%d wounded return to the ranks each month" % back))
		var use := ArmySystem.supply_use(repo, r)
		stats.append(_stat("army_supply", "%d (−%d / mo)" % [int(st["supplies"]), use],
			"Supplies — %d held, %d used each month" % [int(st["supplies"]), use]))
		var drill := ArmySystem.training_grade(repo, int(st["training"]))
		stats.append(_stat("army_training", drill, "Training — %s" % drill))
		var might := ArmySystem.strength_grade(repo, state, code)
		stats.append(_stat("army_strength", might, "Strength — %s against the realm's others of its kind" % might))
		var km := ArmySystem.speed_km_per_day(repo, state, code)
		stats.append(_stat("army_march", "%.1f km/day" % km,
			"March — %.1f km a day: its slowest arm's pace, slowed by short supplies, low morale and little training" % km))
	return {
		"kind": "army", "code": code, "title": label,
		"subtitle": "%s of %s" % ["Fleet" if naval else "Regiment", _label(repo.kingdoms, kingdom)],
		"kingdom_code": kingdom, "initial": label.substr(0, 1), "piece": piece,
		"painting": String((repo.army_art.get(piece, {}) as Dictionary).get("painting", "")),
		"stats": stats, "rates": [], "fields": fields, "features": [], "production": [],
		"actions": [], "known": "army", "center": Vector2(float(r["x"]), float(r["y"])),
		"ask": "What is the state of the %s?" % label,
		# A regiment's values ("4564 (0 wounded)", "Hills (fortified)") are too
		# wide for the default 4-column (2-pair) grid in the 120px left column
		# (owner 2026-09-17 review); one icon+value pair per row instead.
		"stat_columns": 2,
	}
