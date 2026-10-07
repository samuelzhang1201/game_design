class_name WarOrderSketch
extends RefCounted
## A drawn blue arrow as a march's ROUTE (spec 2026-10-08-war-room-draw-
## orders ruling 7): the stroke's samples (pack px) smoothed by
## Ramer–Douglas–Peucker into control points in WHOLE METRES, at most
## army_march_waypoints_max before the tip, the tip the destination; and each
## selected regiment's own waypoints, joining the drawn path at the control
## point nearest it. Pure.

## The drawn path's control points, pack px of whole metres, the tip last;
## `tol` the smoothing tolerance in pack px. Points closer than
## army_route_sample_m to the one kept before them are dropped (the tip kept).
static func fit(repo: DataRepository, samples: PackedVector2Array, tol: float) -> PackedVector2Array:
	if samples.size() < 2:
		return PackedVector2Array()
	var most := int(repo.bal("army_march_waypoints_max")) + 1
	var pts := WarPlanGeometry.simplify(samples, tol, most)
	var near := float(repo.bal("army_route_sample_m"))
	var out: Array[Vector2i] = []
	for i in pts.size():
		var m := ArmySystem.pack_to_metres(repo, pts[i])
		if not out.is_empty() and Vector2(out.back() - m).length() < near:
			if i < pts.size() - 1:
				continue
			out.pop_back()   # the tip stands; the point just short of it goes
			if out.is_empty():
				out.append(ArmySystem.pack_to_metres(repo, pts[0]))
		out.append(m)
	var path := PackedVector2Array()
	for m: Vector2i in out:
		path.append(ArmySystem.metres_to_pack(repo, m))
	return path if path.size() >= 2 and path[0] != path[path.size() - 1] else PackedVector2Array()


## A regiment at `from` on the drawn `path`: its waypoints (pack px) — the
## path's points from the one nearest it (the tip aside) on, that one left
## out when it stands within war_order_join_km of it.
static func route_for(repo: DataRepository, from: Vector2, path: PackedVector2Array) -> Array:
	var n := path.size()
	if n < 2:
		return []
	var j := 0
	for i in range(1, n - 1):
		if path[i].distance_to(from) < path[j].distance_to(from):
			j = i
	if from.distance_to(path[n - 1]) < from.distance_to(path[j]):
		return []   # nearer the end than any bend: straight there
	var reach := repo.bal("war_order_join_km") * WarSheets.px_per_unit(repo)
	var out: Array = []
	for i in range(j, n - 1):
		if i == j and path[i].distance_to(from) <= reach:
			continue
		out.append(path[i])
	return out
