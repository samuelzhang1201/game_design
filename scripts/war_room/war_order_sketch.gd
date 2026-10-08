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


## A regiment at `from` on the drawn `path`: its waypoints (pack px) — it
## joins the path on the leg nearest it (a later leg on a tie) and goes on to
## that leg's END, never back to a point behind it; a regiment short of the
## path's start (its nearest point the start itself) marches to the start
## first, unless it stands within war_order_join_km of it. The tip is the
## destination, never a waypoint.
static func route_for(repo: DataRepository, from: Vector2, path: PackedVector2Array) -> Array:
	var n := path.size()
	if n < 2:
		return []
	var leg := 0
	var best := INF
	for i in range(n - 1):
		var d := Geometry2D.get_closest_point_to_segment(from, path[i], path[i + 1]).distance_to(from)
		if d <= best + 0.0001:
			best = d
			leg = i
	var out: Array = []
	var reach := repo.bal("war_order_join_km") * WarSheets.px_per_unit(repo)
	var q := Geometry2D.get_closest_point_to_segment(from, path[0], path[1])
	if leg == 0 and q.distance_to(path[0]) < 0.0001 and from.distance_to(path[0]) > reach:
		out.append(path[0])   # short of the start: onto the path first
	for i in range(leg + 1, n - 1):
		out.append(path[i])
	return out
