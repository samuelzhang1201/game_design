class_name Map3DSupplyRoad
extends RefCounted
## A supply line's road on the 3D map, read by Map3DSupplyLines: laid on the
## DRAWN roads (on_roads), and followed to where its regiment's piece is drawn
## (follow). The line is drawn in two parts so its end keeps up with a walking
## piece every frame (owner 2026-10-07: 实时跟随军队移动) without the whole road
## being laid again: the BODY, the road up to a cut laid at most every
## map3d_supply_follow_s, and the short TAIL from the cut to the piece
## (split), its UV.x carried on from the body's arc so the flow runs on
## unbroken (tail_arrays). Pure but for the static road index. Never the Game
## autoload.

## The drawn roads' segments by grid cell (on_roads), keyed per repo
## instance and map: built once and never refreshed, so it assumes
## repo.routes does not change after the pack is loaded.
static var _index: Dictionary = {}


## The drawn roads' segments (pack px, smoothed as Map3DBorders.route_lines
## draws them) in every grid cell within the snap reach of them.
static func _road_index(repo: DataRepository) -> Dictionary:
	var key := "%d:%s" % [repo.get_instance_id(), repo.map_id]
	if _index.has(key):
		return _index[key]
	var reach := repo.bal("courier_graph_snap_px")
	var size := maxf(reach * 2.0, 1.0)
	var grid: Dictionary = {}
	var steps := int(repo.bal("map_route_smoothing_steps"))
	for code: String in repo.routes:
		var r: Dictionary = repo.routes[code]
		if not RoadGraph.GROUPS.has(String(r.get("group", ""))):
			continue
		var line := MapGeometry.smooth_open(r["polyline"], steps)
		for i in range(1, line.size()):
			var a := line[i - 1]
			var b := line[i]
			var lo := Vector2i(((a.min(b) - Vector2(reach, reach)) / size).floor())
			var hi := Vector2i(((a.max(b) + Vector2(reach, reach)) / size).floor())
			for gy in range(lo.y, hi.y + 1):
				for gx in range(lo.x, hi.x + 1):
					var cell := Vector2i(gx, gy)
					if not grid.has(cell):
						grid[cell] = []
					(grid[cell] as Array).append([a, b])
	_index = {key: {"size": size, "reach": reach, "grid": grid}}
	return _index[key]


## `route` (pack px) moved onto the drawn roads: the courier's road runs
## through RoadGraph's snapped nodes, up to `courier_graph_snap_px` off the
## road the map draws; each point within that reach goes to the nearest point
## of a drawn road, its ends (the town, the column) stay.
static func on_roads(repo: DataRepository, route: PackedVector2Array) -> PackedVector2Array:
	var idx := _road_index(repo)
	var size: float = idx["size"]
	var reach: float = idx["reach"]
	var grid: Dictionary = idx["grid"]
	var out := route.duplicate()
	for i in range(1, route.size() - 1):
		var p := route[i]
		var best := p
		var best_d := reach * reach
		for seg: Array in grid.get(Vector2i((p / size).floor()), []):
			var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
			var d := q.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = q
		out[i] = best
	return out


## [i, point]: the road's nearest point to `piece` lies on its segment i-1..i
## (the end, i = size - 1, when that is as near).
static func nearest(road: PackedVector2Array, piece: Vector2) -> Array:
	var best_i := road.size() - 1
	var best := road[best_i]
	var best_d := best.distance_squared_to(piece)
	for i in range(1, road.size()):
		var q := Geometry2D.get_closest_point_to_segment(piece, road[i - 1], road[i])
		var d := q.distance_squared_to(piece)
		if d < best_d - 0.0001:
			best_d = d
			best_i = i
			best = q
	return [best_i, best]


## `road` ending at `piece`: cut at the road's nearest point to it (the end
## when that is as near) and run on to the piece — a piece walking on past the
## end extends it, one walking back along the road shortens it.
static func follow(road: PackedVector2Array, piece: Vector2) -> PackedVector2Array:
	if road.size() < 2:
		return road
	var at := nearest(road, piece)
	return road.slice(0, int(at[0])) + tail(road, int(at[0]), piece, at).slice(1)


## The road from its point `cut` - 1 on to `piece` by its nearest point `at`
## ([i, point], nearest()): road[cut - 1 .. i - 1], the nearest point, the piece.
static func tail(road: PackedVector2Array, cut: int, piece: Vector2, at: Array) -> PackedVector2Array:
	var out := road.slice(cut - 1, maxi(int(at[0]), cut))
	var best: Vector2 = at[1]
	if out.is_empty() or out[out.size() - 1].distance_to(best) > 0.01:
		out.append(best)
	if best.distance_to(piece) > 0.01:
		out.append(piece)
	return out


## The length of `line`, its points' distances summed (as ribbon_arrays' UV.x).
static func arc(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i - 1].distance_to(line[i])
	return total


## One ribbon mesh of `tails`, each line's UV.x starting at its `offsets`
## entry (the body's arc) so the flow runs on across the cut; [] for none.
static func tail_arrays(tails: Array, offsets: Array, height_fn: Callable) -> Array:
	var out: Array = []
	for i in tails.size():
		var arrays := Map3DBorders.ribbon_arrays([tails[i]], height_fn)
		if arrays.is_empty():
			continue
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for k in uvs.size():
			uvs[k].x += float(offsets[i])
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		if out.is_empty():
			out = arrays
			continue
		var base := (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for k in idx.size():
			idx[k] += base
		for slot: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
			out[slot] = out[slot] + (idx if slot == Mesh.ARRAY_INDEX else arrays[slot])
	return out
