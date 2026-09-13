class_name MapTerrain
extends RefCounted
## The terrain the game draws itself (spec 2026-09-11): the pack's Voronoi
## cells (DataRepository.cells / vertices) fanned into one vertex-coloured
## mesh. Land is its biome's palette tint times a relief shade computed from
## the neighbours' heights; the sea grades from deep to shallow by height;
## lakes are flat. Ring vertices blend the cells around them, but only within
## their own class (land with land, water with water), so the shore stays a
## crisp edge while everything inland is smooth. Pure functions over the
## repository — no Nodes, no RNG — so GUT pins every formula headless.

## Azgaar's convention: cells below this height are water.
const SEA_LEVEL := 20.0
const FALLBACK := Color(0.6, 0.6, 0.6)

## Built meshes, one per repository instance (the pack does not change
## while a repo lives, so the view and every panel share one mesh).
static var _mesh_cache: Dictionary = {}

## Forget every built mesh. DataRepository.load_map calls this: a repo that
## swaps packs must not keep drawing the old world.
static func invalidate() -> void:
	_mesh_cache.clear()
	_hops_cache.clear()
	forget_heat()

static func is_water(cell: Dictionary) -> bool:
	return String(cell.get("water", "")) != ""

## Open water — the sea, not a lake.
static func is_sea(cell: Dictionary) -> bool:
	var kind := String(cell.get("water", ""))
	return kind != "" and kind != "lake"

## Toward the light, unit length (ZERO when balance gives no direction).
static func light_dir(repo: DataRepository) -> Vector2:
	var l := Vector2(repo.bal("map_light_x"), repo.bal("map_light_y"))
	return l.normalized() if l.length_squared() > 0.0 else Vector2.ZERO

## The fan's hub: the mean of the cell's vertices (Voronoi cells are convex,
## so it lies inside).
static func cell_center(repo: DataRepository, cell: Dictionary) -> Vector2:
	var ids: PackedInt32Array = cell["vertex_ids"]
	if ids.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for id in ids:
		sum += repo.vertices[id] as Vector2
	return sum / float(ids.size())

## How far the cell reaches from its hub, on average: the mean distance from
## the centre to its own vertices. Used to scatter a clump of symbols INSIDE
## a cell rather than stacking them on its centre point.
static func cell_radius(repo: DataRepository, cell: Dictionary) -> float:
	var ids: PackedInt32Array = cell["vertex_ids"]
	if ids.is_empty():
		return 0.0
	var here := cell_center(repo, cell)
	var sum := 0.0
	for id in ids:
		sum += here.distance_to(repo.vertices[id] as Vector2)
	return sum / float(ids.size())

## The uphill vector: sum over LAND neighbours of (h_n - h_c) * unit(p_n - p_c),
## divided by their count. Water neighbours are left out so a coast is not a
## cliff on every shore. ZERO for a cell with no land neighbours.
static func gradient_of(repo: DataRepository, cell: Dictionary) -> Vector2:
	var here := cell_center(repo, cell)
	var h := float(cell["height"])
	var g := Vector2.ZERO
	var n := 0
	for id in (cell["neighbor_ids"] as PackedInt32Array):
		var other: Dictionary = repo.cells.get(id, {})
		if other.is_empty() or is_water(other):
			continue
		var dir := cell_center(repo, other) - here
		if dir.length_squared() == 0.0:
			continue
		g += (float(other["height"]) - h) * dir.normalized()
		n += 1
	return g / float(n) if n > 0 else Vector2.ZERO

## Relief times altitude: a slope whose downhill side faces the light is
## lit (1 - strength * dot(uphill, light)), clamped to the balance bounds,
## then brightened with height from sea level to the summit.
static func shade_of(repo: DataRepository, cell: Dictionary) -> float:
	var relief := clampf(
		1.0 - repo.bal("map_relief_strength") * gradient_of(repo, cell).dot(light_dir(repo)),
		repo.bal("map_relief_min"), repo.bal("map_relief_max"))
	var altitude := 1.0 + repo.bal("map_altitude_gain") \
		* (float(cell["height"]) - SEA_LEVEL) / (100.0 - SEA_LEVEL)
	return relief * altitude

## A terrain_palette colour, or `fallback` when the key is not authored.
static func palette_color(repo: DataRepository, key: String, fallback: Color) -> Color:
	var hex := String(repo.terrain_palette.get(key, ""))
	return Color(hex) if hex != "" else fallback

static func _land_tint(repo: DataRepository, cell: Dictionary) -> Color:
	var bid := int(cell["biome_id"])
	var pack_hex := String((repo.biomes.get(bid, {}) as Dictionary).get("color", ""))
	return palette_color(repo, "biome_%d" % bid, Color(pack_hex) if pack_hex != "" else FALLBACK)

static func cell_color(repo: DataRepository, cell: Dictionary) -> Color:
	var kind := String(cell.get("water", ""))
	if kind == "lake":
		return palette_color(repo, "lake", FALLBACK)
	if kind != "":
		# A cell that is not in the repo (a bare fixture) has no shore near
		# it and is open sea.
		return sea_color(repo, float(shore_hops(repo).get(int(cell.get("cell_id", -1)), INF)))
	var s := shade_of(repo, cell)
	var tint := _land_tint(repo, cell)
	return Color(tint.r * s, tint.g * s, tint.b * s, 1.0)

## --- The shelf ---------------------------------------------------------
## Shallow water is a BAND along the shore, not a height class (owner
## 2026-09-13: the sea graded too much, and the deep/shallow edge was
## abrupt). The pack's sea heights form broad shelves and stray pools, and
## colouring by height painted the ocean in hard-edged pale blotches far
## from any coast. Instead every sea cell's distance from land is counted
## in CELL HOPS — 0 for a cell touching land — by one breadth-first walk
## over the neighbour lists, and the tint runs from sea_shallow at the
## shore to sea_deep map_sea_shelf_cells hops out, shaped by
## map_sea_shelf_gamma; the ring-vertex blending then smooths the steps
## between cells into a gradient. Lakes stay flat and take no part.
static var _hops_cache: Dictionary = {}

## sea cell id -> hops from the nearest land cell. Sea with no land
## reachable through sea (none, on a real pack) is absent: open sea.
static func shore_hops(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _hops_cache.has(key):
		return _hops_cache[key]
	var hops: Dictionary = {}
	var frontier: Array[int] = []
	for id: int in _sorted_ids(repo):
		var cell: Dictionary = repo.cells[id]
		if not is_sea(cell):
			continue
		for n: int in (cell["neighbor_ids"] as PackedInt32Array):
			var other: Dictionary = repo.cells.get(n, {})
			if not other.is_empty() and not is_water(other):
				hops[id] = 0
				frontier.append(id)
				break
	var head := 0
	while head < frontier.size():
		var id: int = frontier[head]
		head += 1
		var next: int = int(hops[id]) + 1
		for n: int in ((repo.cells[id] as Dictionary)["neighbor_ids"] as PackedInt32Array):
			if hops.has(n):
				continue
			var other: Dictionary = repo.cells.get(n, {})
			if other.is_empty() or not is_sea(other):
				continue
			hops[n] = next
			frontier.append(n)
	_hops_cache[key] = hops
	return hops

## The sea's tint `hops` cells out from the shore: sea_shallow at 0, sea_deep
## from map_sea_shelf_cells on, (1 - hops / shelf)^gamma between.
static func sea_color(repo: DataRepository, hops: float) -> Color:
	var shelf := maxf(repo.bal("map_sea_shelf_cells"), 0.000001)
	var t := pow(clampf(1.0 - hops / shelf, 0.0, 1.0), maxf(repo.bal("map_sea_shelf_gamma"), 0.01))
	return palette_color(repo, "sea_deep", FALLBACK).lerp(
		palette_color(repo, "sea_shallow", FALLBACK), t)

static func _sorted_ids(repo: DataRepository) -> Array:
	var ids: Array = repo.cells.keys()
	ids.sort()
	return ids

## vertex_id -> the cells (ids, in cell order) whose polygon touches it.
static func vertex_cells(repo: DataRepository) -> Dictionary:
	var out: Dictionary = {}
	for id in _sorted_ids(repo):
		for v in ((repo.cells[id] as Dictionary)["vertex_ids"] as PackedInt32Array):
			if not out.has(v):
				out[v] = []
			(out[v] as Array).append(id)
	return out

## The mean colour of the cells around a vertex that share `water` with the
## fan being built; the fan's own colour when none does.
static func _ring_color(touching: Array, colors: Dictionary, cells: Dictionary,
		water: bool, own: Color) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for id in touching:
		if is_water(cells[id]) != water:
			continue
		sum += colors[id] as Color
		n += 1
	return sum / float(n) if n > 0 else own

## The mesh arrays in native map coordinates: per cell (in id order) one
## centre vertex then one ring vertex per polygon vertex, and a triangle
## (centre, ring[i], ring[i + 1]) per edge.
## `tint` overrides how a cell is coloured (the HEIGHTS view passes a height
## ramp); the blending, fanning and indexing are the same either way.
static func build(repo: DataRepository, tint: Callable = Callable()) -> Dictionary:
	var ids := _sorted_ids(repo)
	var colors: Dictionary = {}
	for id in ids:
		colors[id] = tint.call(repo, repo.cells[id]) if tint.is_valid() else cell_color(repo, repo.cells[id])
	var touching := vertex_cells(repo)
	# map_terrain_blend 1: ring vertices average the cells around them, so
	# tints flow across cell edges (a soft, painterly land). 0: every cell is
	# one flat colour with a crisp edge (a mosaic of the pack's cells).
	var blend := repo.bal("map_terrain_blend") != 0.0
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for id in ids:
		var cell: Dictionary = repo.cells[id]
		var ring: PackedInt32Array = cell["vertex_ids"]
		if ring.size() < 3:
			continue
		var water := is_water(cell)
		var own: Color = colors[id]
		var base := verts.size()
		verts.append(cell_center(repo, cell))
		cols.append(own)
		for v in ring:
			verts.append(repo.vertices[v] as Vector2)
			cols.append(_ring_color(touching[v], colors, repo.cells, water, own) if blend else own)
		var n := ring.size()
		for i in n:
			idx.append(base)
			idx.append(base + 1 + i)
			idx.append(base + 1 + (i + 1) % n)
	return {"vertices": verts, "colors": cols, "indices": idx}

static func to_mesh(built: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built["vertices"]
	arrays[Mesh.ARRAY_COLOR] = built["colors"]
	arrays[Mesh.ARRAY_INDEX] = built["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## The mesh for this repository, built on first use. null when the pack
## carries no cells (an older pack): the view then stays hidden.
static func shared_mesh(repo: DataRepository) -> ArrayMesh:
	if repo.cells.is_empty():
		return null
	var key := repo.get_instance_id()
	if not _mesh_cache.has(key):
		_mesh_cache[key] = to_mesh(build(repo))
	return _mesh_cache[key]


## --- The HEIGHTS view (owner request 2026-09-13) ------------------------
## Contour lines read badly on this sheet, so the relief is a HEAT MAP: land
## ramped through the heat_N stops of data/terrain_palette.csv by where its
## height falls between sea level and the pack's own summit. Water keeps its
## normal colour, so the coastline still tells you where the land starts.
static var _heat_cache: Dictionary = {}
static var _summit_cache: Dictionary = {}

static func forget_heat() -> void:
	_heat_cache.clear()
	_summit_cache.clear()

## The pack's highest land cell — the top of the ramp. Nothing is assumed
## about the scale: a flat map ramps across its own flat range.
static func summit(repo: DataRepository) -> float:
	var key := repo.get_instance_id()
	if not _summit_cache.has(key):
		var top := SEA_LEVEL
		for id: int in repo.cells:
			var cell: Dictionary = repo.cells[id]
			if not is_water(cell):
				top = maxf(top, float(cell["height"]))
		_summit_cache[key] = maxf(top, SEA_LEVEL + 1.0)
	return _summit_cache[key]

## The heat_N stops in order. Empty when the palette carries none.
static func heat_stops(repo: DataRepository) -> Array:
	var out: Array = []
	var n := 1
	while repo.terrain_palette.has("heat_%d" % n):
		out.append(palette_color(repo, "heat_%d" % n, FALLBACK))
		n += 1
	return out

## Where a cell sits on that ramp. Water is left as it is.
static func heat_color(repo: DataRepository, cell: Dictionary) -> Color:
	if is_water(cell):
		return cell_color(repo, cell)
	var stops := heat_stops(repo)
	if stops.is_empty():
		return cell_color(repo, cell)
	if stops.size() == 1:
		return stops[0]
	var t := clampf((float(cell["height"]) - SEA_LEVEL)
		/ (summit(repo) - SEA_LEVEL), 0.0, 1.0)
	var span := t * float(stops.size() - 1)
	var i := mini(int(span), stops.size() - 2)
	return (stops[i] as Color).lerp(stops[i + 1], span - float(i))

static func heat_mesh(repo: DataRepository) -> ArrayMesh:
	if repo.cells.is_empty():
		return null
	var key := repo.get_instance_id()
	if not _heat_cache.has(key):
		_heat_cache[key] = to_mesh(build(repo, Callable(MapTerrain, "heat_color")))
	return _heat_cache[key]
