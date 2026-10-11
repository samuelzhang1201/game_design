class_name RoadGraph
extends RefCounted
## The pack's land routes as one network (spec 2026-09-27-courier-core §1):
## roads and trails, their polyline vertices snapped to a courier_graph_snap_px
## grid and merged into nodes. The routes join each other MID-LINE, so by
## their burg endpoints alone the network falls into dozens of pieces; by
## shared vertices 97% of it is one. Positions are the pack's whole METRES
## (ArmySystem); an edge's cost is its clear-road metres x 1000, so a metre of
## road on the plain costs 1000. Cached per pack, forgotten by load_map.
## The COURIER's network (courier_of_pack, owner 2026-10-11) adds the pack's
## rivers (kind "river", at road_speed's river pace) and sends every edge over
## ground too steep for a horse round it (MarchPath, water open): the detour
## rides as offroad / sea stretches, its cost their sum. The drawn network
## (of_pack: trade, the war economy) stays as drawn.
## Weather is not in the cost: the route is chosen once, on the static
## network; the weather changes the pace along it day by day.

const GROUPS := {"roads": "road", "trails": "trail"}
const RIVER := "river"
## The kinds of a stretch off the network: across country, or over open water.
const ACROSS := ["offroad", "sea"]

var nodes: Array[Vector2i] = []
var edges: Array = []

static var _cached: RoadGraph = null
static var _cached_map := ""
static var _courier: RoadGraph = null
static var _courier_key := ""


static func forget() -> void:
	_cached = null
	_cached_map = ""
	_courier = null
	_courier_key = ""


static func of_pack(repo: DataRepository) -> RoadGraph:
	if _cached == null or _cached_map != repo.map_id:
		_cached = build(repo, repo.routes)
		_cached_map = repo.map_id
	return _cached


## The courier's network: the routes, then the rivers, every edge over
## ground too steep gone round (the water-open grid of MarchPath).
static func courier_of_pack(repo: DataRepository) -> RoadGraph:
	var key := "%s:%d:%d" % [repo.map_id, int(repo.bal("army_max_slope")), int(repo.bal("army_march_grid_px"))]
	if _courier == null or _courier_key != key:
		_courier = build(repo, repo.routes, repo.rivers, MarchPath.of_pack(repo, true))
		_courier_key = key
	return _courier


static func build(repo: DataRepository, routes: Dictionary, rivers: Dictionary = {},
		grid: MarchPath = null) -> RoadGraph:
	var g := RoadGraph.new()
	var snap := maxf(repo.bal("courier_graph_snap_px"), 0.001)
	var index: Dictionary = {}
	var codes := routes.keys()
	codes.sort()
	for code in codes:
		var r: Dictionary = routes[code]
		var group := String(r.get("group", ""))
		if not GROUPS.has(group):
			continue
		g._add_line(repo, index, snap, r["polyline"], String(GROUPS[group]), grid)
	var river_codes := rivers.keys()
	river_codes.sort()
	for code in river_codes:
		g._add_line(repo, index, snap, (rivers[code] as Dictionary)["polyline"], RIVER, grid)
	return g


func _add_line(repo: DataRepository, index: Dictionary, snap: float, polyline: PackedVector2Array,
		kind: String, grid: MarchPath) -> void:
	var prev := -1
	for p: Vector2 in polyline:
		var key := Vector2i(roundi(p.x / snap), roundi(p.y / snap))
		var id: int = index.get(key, -1)
		if id < 0:
			id = nodes.size()
			index[key] = id
			nodes.append(ArmySystem.pack_to_metres(repo, p))
			edges.append([])
		if prev >= 0 and prev != id:
			_link(repo, prev, id, kind, grid)
		prev = id


static func factor_permille(repo: DataRepository, kind: String) -> int:
	return maxi(1, int(repo.road_speed.get(kind, 1000)))


## The height tier's per mille at a point in metres; 1000 off the land.
static func tier_permille(repo: DataRepository, at_m: Vector2) -> int:
	var cell := MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, Vector2i(at_m)))
	if not repo.cells.has(cell):
		return 1000
	var tier := String(Elevation.tier_of(repo, float(repo.cells[cell]["height"]))["tier"])
	return maxi(1, int(repo.road_speed.get("tier_" + tier, 1000)))


## Clear-road metres a stretch takes, rounded up: length x 10^9 / factor,
## the factor a product of per-milles out of 10^9 (segment x tier x weather).
static func stretch_need(length_m: int, factor: int) -> int:
	var f := maxi(1, factor)
	@warning_ignore("integer_division")  # rounded up, whole metres
	return (length_m * 1_000_000_000 + f - 1) / f


func _link(repo: DataRepository, a: int, b: int, kind: String, grid: MarchPath = null) -> void:
	var length := int(round(Vector2(nodes[a]).distance_to(Vector2(nodes[b]))))
	var mid := (Vector2(nodes[a]) + Vector2(nodes[b])) * 0.5
	# cost units: clear-road metres x 1000, the weather held at 1000‰
	var cost := stretch_need(length, factor_permille(repo, kind) * tier_permille(repo, mid) * 1000) * 1000
	var via: Array = []   # the way round too-steep ground: [x_m, y_m, kind] each, ending on b
	if grid != null:
		var ca := grid.cell_of(nodes[a])
		var cb := grid.cell_of(nodes[b])
		if not grid.clear(nodes[a], nodes[b], [ca, cb]):
			var corners := grid.road(nodes[a], nodes[b])
			if corners.size() > 1:   # one corner back: no way round, the drawn edge stays
				via = _pieces(repo, grid, nodes[a], corners)
				length = 0
				cost = 0
				var at := nodes[a]
				for q: Array in via:
					var to := Vector2i(int(q[0]), int(q[1]))
					var len_i := int(round(Vector2(at).distance_to(Vector2(to))))
					length += len_i
					cost += _stretch_cost(repo, String(q[2]), at, to, len_i)
					at = to
	for e: Array in edges[a]:
		if int(e[0]) == b:
			if cost < int(e[3]):
				_set_edge(e, length, kind, cost, via)
				for f: Array in edges[b]:
					if int(f[0]) == a:
						_set_edge(f, length, kind, cost, _reversed(nodes[a], via))
			return
	edges[a].append([b, length, kind, cost, via])
	edges[b].append([a, length, kind, cost, _reversed(nodes[a], via)])


## A stretch's cost units: its need (kind pace x the tier where it starts, none
## on water) in clear-road metres x 1000.
static func _stretch_cost(repo: DataRepository, kind: String, from: Vector2i, to: Vector2i, length: int) -> int:
	var tier := 1000 if kind == "sea" else tier_permille(repo, (Vector2(from) + Vector2(to)) * 0.5)
	return stretch_need(length, factor_permille(repo, kind) * tier * 1000) * 1000


## The same way walked from its far end: the points before each end, each
## carrying the kind of the stretch it now closes.
static func _reversed(start: Vector2i, via: Array) -> Array:
	var out: Array = []
	for i in range(via.size() - 1, -1, -1):
		var p: Vector2i = start if i == 0 else Vector2i(int(via[i - 1][0]), int(via[i - 1][1]))
		out.append([p.x, p.y, String(via[i][2])])
	return out


static func _set_edge(e: Array, length: int, kind: String, cost: int, via: Array) -> void:
	e[1] = length
	e[2] = kind
	e[3] = cost
	e[4] = via


static func leg_kind(repo: DataRepository, a: Vector2i, b: Vector2i) -> String:
	var step := maxf(repo.bal("courier_sea_sample_km") * 1000.0, 1.0)
	var length := Vector2(a).distance_to(Vector2(b))
	for i in range(1, int(length / step) + 1):
		var p := Vector2(a).lerp(Vector2(b), float(i) * step / length)
		if MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, Vector2i(p))) < 0:
			return "sea"
	return "offroad"


## The stretches of a leg off the network, [x_m, y_m, kind] each: round
## ground a horse cannot climb (the open grid's road), water at "sea" pace,
## land "offroad". No grid: one straight leg, "sea" when sampled off the land.
static func across(repo: DataRepository, grid: MarchPath, a: Vector2i, b: Vector2i) -> Array:
	if grid == null:
		return [[b.x, b.y, leg_kind(repo, a, b)]]
	return _pieces(repo, grid, a, grid.road(a, b))


## `corners` (the road after `from`) as stretches, each straight piece cut
## where it enters or leaves water.
static func _pieces(_repo: DataRepository, grid: MarchPath, from: Vector2i, corners: Array) -> Array:
	var out: Array = []
	var at := from
	for c: Vector2i in corners:
		for run: Array in grid.water_runs(at, c):
			var p: Vector2i = run[0]
			out.append([p.x, p.y, "sea" if bool(run[1]) else "offroad"])
		at = c
	return out


## The node nearest a point, the lowest id on a tie; among `reached` only
## (a shortest() dist array: -1 = unreached) when one is given. -1 if none.
func nearest(at_m: Vector2i, reached: Array = []) -> int:
	var best := -1
	var best_d := INF
	for id in nodes.size():
		if not reached.is_empty() and int(reached[id]) < 0:
			continue
		var d := Vector2(nodes[id]).distance_squared_to(Vector2(at_m))
		if d < best_d:
			best_d = d
			best = id
	return best


## Dijkstra from one node over a binary heap of [cost, id] (ties by id). A
## graph never changes once built, so each start's tree is run ONCE and kept
## (perf 2026-10-02: the month's supply plan ran it afresh every time, ~4 ms);
## the tree is shared, so its arrays are read-only.
func shortest(from_id: int) -> Dictionary:
	if _trees.has(from_id):
		return _trees[from_id]
	var tree := _dijkstra(from_id)
	(tree["dist"] as Array).make_read_only()
	(tree["prev"] as Array).make_read_only()
	tree.make_read_only()
	_trees[from_id] = tree
	return tree


## Trees run so far by shortest(), {start id: tree}, and how many (a test seam).
var _trees: Dictionary = {}
var dijkstra_runs := 0


func _dijkstra(from_id: int) -> Dictionary:
	dijkstra_runs += 1
	var n := nodes.size()
	var dist: Array[int] = []
	var prev: Array[int] = []
	dist.resize(n)
	dist.fill(-1)
	prev.resize(n)
	prev.fill(-1)
	if from_id < 0 or from_id >= n:
		return {"dist": dist, "prev": prev}
	var heap: Array = []
	dist[from_id] = 0
	_push(heap, [0, from_id])
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var d := int(top[0])
		var u := int(top[1])
		if d != dist[u]:
			continue
		for e: Array in edges[u]:
			var v := int(e[0])
			var nd := d + int(e[3])
			if dist[v] < 0 or nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				_push(heap, [nd, v])
	return {"dist": dist, "prev": prev}


## The waypoints from the tree's start to `goal`, each [x_m, y_m, kind of the
## edge into it]; the start node itself is not included.
func route(tree: Dictionary, goal: int) -> Array:
	var prev: Array = tree["prev"]
	var chain: Array[int] = []
	var at := goal
	while at >= 0:
		chain.push_front(at)
		at = int(prev[at])
	var out: Array = []
	for i in range(1, chain.size()):
		var e := _edge_between(chain[i - 1], chain[i])
		if e.is_empty() or (e[4] as Array).is_empty():
			out.append([nodes[chain[i]].x, nodes[chain[i]].y, String(e[2]) if not e.is_empty() else "offroad"])
		else:
			out.append_array((e[4] as Array).duplicate(true))
	return out


func _kind_between(u: int, v: int) -> String:
	var e := _edge_between(u, v)
	return String(e[2]) if not e.is_empty() else "offroad"


func _edge_between(u: int, v: int) -> Array:
	for e: Array in edges[u]:
		if int(e[0]) == v:
			return e
	return []


static func _less(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1]))


static func _push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		@warning_ignore("integer_division")  # the heap's parent index
		var p := (i - 1) / 2
		if not _less(h[i], h[p]):
			break
		var t: Array = h[i]
		h[i] = h[p]
		h[p] = t
		i = p


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < h.size() and _less(h[l], h[m]):
			m = l
		if r < h.size() and _less(h[r], h[m]):
			m = r
		if m == i:
			break
		var t: Array = h[i]
		h[i] = h[m]
		h[m] = t
		i = m
	return top
