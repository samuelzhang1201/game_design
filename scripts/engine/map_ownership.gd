class_name MapOwnership
extends RefCounted
## Who holds which province, and what a kingdom's border looks like as a
## result. The map pack ships the *starting* ownership; conquest moves it.
##
## The province is the unit territory changes hands in. Provinces tile their
## kingdom exactly (the importer checks that every state cell carries one),
## so a kingdom's live border is the merge of the loops of the provinces it
## currently holds — drop every edge two of its own provinces share and the
## internal seams disappear, leaving the outline.
##
## GameState.province_owner holds only the provinces that have MOVED; an
## absent province still belongs to whoever the pack says. That keeps saves
## small, keeps an untouched campaign byte-identical to before this existed,
## and means a pack swap re-reads starting ownership rather than inheriting
## the last map's.
##
## Engine-pure: no Nodes, no RNG, no wall clock.

## Cached kingdom outlines, keyed by kingdom_code. Rebuilt on demand and
## dropped whenever ownership changes — merging ~29 province loops is cheap
## but not something to redo every frame.
static var _outline_cache: Dictionary = {}
## The state the cache was built against; a different one invalidates it.
static var _cache_owner_version := -1
## Cached province seams per kingdom (seams_of), dropped with the outlines.
static var _seam_cache: Dictionary = {}


## The kingdom holding `province_code` right now: the campaign's override if
## there is one, else the pack's own kingdom_code, else "".
static func owner_of(data: DataRepository, state: GameState,
		province_code: String) -> String:
	if state != null and state.province_owner.has(province_code):
		return String(state.province_owner[province_code])
	var row: Dictionary = data.provinces.get(province_code, {})
	return String(row.get("kingdom_code", ""))


## Every province a kingdom holds, in pack order so the result is stable.
static func provinces_of(data: DataRepository, state: GameState,
		kingdom_code: String) -> Array[String]:
	var out: Array[String] = []
	for code: String in data.provinces:
		if owner_of(data, state, code) == kingdom_code:
			out.append(code)
	return out


## Move one province to a new kingdom. Carries a reason, like every other
## state change in the engine — a border that moved without one is a border
## nobody can explain later. Returns false when nothing changed.
static func set_owner(data: DataRepository, state: GameState,
		province_code: String, kingdom_code: String, reason: String) -> bool:
	if not data.provinces.has(province_code):
		return false
	if not data.kingdoms.has(kingdom_code):
		return false
	var before := owner_of(data, state, province_code)
	if before == kingdom_code:
		return false
	state.province_owner[province_code] = kingdom_code
	state.territory_log.append({
		"tick": state.tick, "province": province_code,
		"from": before, "to": kingdom_code, "reason": reason,
	})
	invalidate()
	return true


## Drop the outline cache. Called on every transfer; also public so a pack
## swap or a load can clear outlines built for the previous world.
static func invalidate() -> void:
	_outline_cache.clear()
	_seam_cache.clear()
	_cache_owner_version = -1


## A kingdom's border as closed loops in native map coordinates — the merge
## of the loops of the provinces it holds. Falls back to the pack's own
## borders.csv loops when the pack ships no province outlines, so an older
## pack still draws.
static func outline_of(data: DataRepository, state: GameState,
		kingdom_code: String) -> Array:
	_refresh_caches(state)
	if _outline_cache.has(kingdom_code):
		return _outline_cache[kingdom_code]
	var loops: Array = []
	if data.province_borders.is_empty():
		loops = data.borders.get(kingdom_code, [])
	else:
		loops = _merge_loops(_held_loops(data, state, kingdom_code))
	_outline_cache[kingdom_code] = loops
	return loops


## The seams inside a kingdom (spec 2026-09-09 §5): every edge walked by
## exactly two of the loops of the provinces it holds NOW, as one two-point
## segment each — the province view draws them dashed. The outline's edges
## are walked once and never appear here, so a conquered province's former
## seams vanish from its old owner and it draws none against new neighbours
## until it shares an owner with them. Cached beside the outlines.
static func seams_of(data: DataRepository, state: GameState, kingdom_code: String) -> Array:
	_refresh_caches(state)
	if _seam_cache.has(kingdom_code):
		return _seam_cache[kingdom_code]
	var counted := _count_edges(_held_loops(data, state, kingdom_code))
	var out: Array = []
	for e in counted["order"]:
		if int(counted["count"][e]) == 2:
			out.append(PackedVector2Array([counted["point"][e[0]], counted["point"][e[1]]]))
	_seam_cache[kingdom_code] = out
	return out


static func _refresh_caches(state: GameState) -> void:
	var version := 0 if state == null else state.province_owner.size()
	if _cache_owner_version != version:
		_outline_cache.clear()
		_seam_cache.clear()
		_cache_owner_version = version


## Where a kingdom's name belongs: the area-weighted centre of the provinces
## it holds, so the label recentres when territory changes hands. Falls back
## to the pack's own kingdom centre when the pack has no province areas.
static func label_anchor(data: DataRepository, state: GameState,
		kingdom_code: String) -> Vector2:
	var sum := Vector2.ZERO
	var weight := 0.0
	for code in provinces_of(data, state, kingdom_code):
		var row: Dictionary = data.provinces[code]
		var area := absf(float(row.get("area", 0.0)))
		if area <= 0.0:
			area = 1.0
		sum += Vector2(float(row.get("center_x", 0.0)),
			float(row.get("center_y", 0.0))) * area
		weight += area
	if weight > 0.0:
		return sum / weight
	var king: Dictionary = data.kingdoms.get(kingdom_code, {})
	return Vector2(float(king.get("center_x", 0.0)), float(king.get("center_y", 0.0)))


static func _held_loops(data: DataRepository, state: GameState,
		kingdom_code: String) -> Array:
	var out: Array = []
	for code in provinces_of(data, state, kingdom_code):
		for loop: PackedVector2Array in data.province_borders.get(code, []):
			out.append(loop)
	return out


## Merge closed loops into the outline of their union: an edge walked by two
## of the loops is an internal seam between two provinces of the same owner,
## so it is dropped; what remains is chained back into closed rings.
##
## Loops share exact vertex coordinates (they come from the same Azgaar
## mesh), so edges are matched on their quantised endpoints rather than by
## identity.
static func _merge_loops(loops: Array) -> Array:
	var counted := _count_edges(loops)
	var edge_count: Dictionary = counted["count"]
	var edge_order: Array = counted["order"]
	var point_of: Dictionary = counted["point"]
	# Adjacency over the edges walked exactly once — the union's boundary.
	var adjacent: Dictionary = {}
	var boundary: Array = []
	for e in edge_order:
		if int(edge_count[e]) != 1:
			continue
		boundary.append(e)
		for v in [e[0], e[1]]:
			if not adjacent.has(v):
				adjacent[v] = []
			(adjacent[v] as Array).append(e)
	var used: Dictionary = {}
	var out: Array = []
	for start in boundary:
		if used.has(start):
			continue
		var ring := PackedVector2Array()
		var e = start
		var v = e[0]
		while true:
			used[e] = true
			ring.append(point_of[v])
			v = e[1] if e[0] == v else e[0]
			var next_edge = null
			for cand in (adjacent[v] as Array):
				if not used.has(cand):
					next_edge = cand
					break
			if next_edge == null:
				break
			e = next_edge
		if ring.size() >= 3:
			out.append(ring)
	return out


## How many loops walk each undirected edge, in first-seen order, with a
## representative point per vertex key. Once = the union's boundary, twice
## = a seam between two provinces of the same owner.
static func _count_edges(loops: Array) -> Dictionary:
	var edge_count: Dictionary = {}
	var edge_order: Array = []
	var point_of: Dictionary = {}
	for loop: PackedVector2Array in loops:
		for i in loop.size():
			var a := _key(loop[i])
			var b := _key(loop[(i + 1) % loop.size()])
			if a == b:
				continue
			point_of[a] = loop[i]
			point_of[b] = loop[(i + 1) % loop.size()]
			var e := _edge(a, b)
			if edge_count.has(e):
				edge_count[e] = int(edge_count[e]) + 1
			else:
				edge_count[e] = 1
				edge_order.append(e)
	return {"count": edge_count, "order": edge_order, "point": point_of}


## Vertex identity: Azgaar coordinates carry two decimals, so a hundredth of
## a native pixel is well below the mesh's own resolution and two provinces
## meeting at a vertex always agree on this key.
static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0))


## Undirected edge, smaller endpoint first, so the two provinces sharing it
## produce the same key.
static func _edge(a: Vector2i, b: Vector2i) -> Array:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return [a, b]
	return [b, a]
