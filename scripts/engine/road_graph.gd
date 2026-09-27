class_name RoadGraph
extends RefCounted
## The pack's land routes as one network (spec 2026-09-27-courier-core §1):
## roads and trails, their polyline vertices snapped to a courier_graph_snap_px
## grid and merged into nodes. The routes join each other MID-LINE, so by
## their burg endpoints alone the network falls into dozens of pieces; by
## shared vertices 97% of it is one. Positions are the pack's whole METRES
## (ArmySystem); an edge's cost is its clear-road metres x 1000, so a metre of
## road on the plain costs 1000. Cached per pack, forgotten by load_map.
## Weather is not in the cost: the route is chosen once, on the static
## network; the weather changes the pace along it day by day.

const GROUPS := {"roads": "road", "trails": "trail"}

var nodes: Array[Vector2i] = []
var edges: Array = []

static var _cached: RoadGraph = null
static var _cached_map := ""


static func forget() -> void:
	_cached = null
	_cached_map = ""


static func of_pack(repo: DataRepository) -> RoadGraph:
	if _cached == null or _cached_map != repo.map_id:
		_cached = build(repo, repo.routes)
		_cached_map = repo.map_id
	return _cached


static func build(repo: DataRepository, routes: Dictionary) -> RoadGraph:
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
		var prev := -1
		for p: Vector2 in r["polyline"]:
			var key := Vector2i(roundi(p.x / snap), roundi(p.y / snap))
			var id: int = index.get(key, -1)
			if id < 0:
				id = g.nodes.size()
				index[key] = id
				g.nodes.append(ArmySystem.pack_to_metres(repo, p))
				g.edges.append([])
			if prev >= 0 and prev != id:
				g._link(repo, prev, id, String(GROUPS[group]))
			prev = id
	return g


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


func _link(repo: DataRepository, a: int, b: int, kind: String) -> void:
	var length := int(round(Vector2(nodes[a]).distance_to(Vector2(nodes[b]))))
	var mid := (Vector2(nodes[a]) + Vector2(nodes[b])) * 0.5
	# cost units: clear-road metres x 1000, the weather held at 1000‰
	var cost := stretch_need(length, factor_permille(repo, kind) * tier_permille(repo, mid) * 1000) * 1000
	for e: Array in edges[a]:
		if int(e[0]) == b:
			if cost < int(e[3]):
				_set_edge(e, length, kind, cost)
				for f: Array in edges[b]:
					if int(f[0]) == a:
						_set_edge(f, length, kind, cost)
			return
	edges[a].append([b, length, kind, cost])
	edges[b].append([a, length, kind, cost])


static func _set_edge(e: Array, length: int, kind: String, cost: int) -> void:
	e[1] = length
	e[2] = kind
	e[3] = cost


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


## Dijkstra from one node over a binary heap of [cost, id] (ties by id).
func shortest(from_id: int) -> Dictionary:
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
		out.append([nodes[chain[i]].x, nodes[chain[i]].y, _kind_between(chain[i - 1], chain[i])])
	return out


func _kind_between(u: int, v: int) -> String:
	for e: Array in edges[u]:
		if int(e[0]) == v:
			return String(e[2])
	return "offroad"


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
