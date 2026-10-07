class_name MarchRoute
extends RefCounted
## A march's route (spec 2026-10-07-march-waypoints §1): a CENTRIPETAL
## Catmull-Rom through the column, its waypoints and its end — the ends'
## missing neighbours reflected — sampled into WHOLE-METRE points, every
## control point exactly on it. The maps draw these points and the column
## walks them (ArmySystem), so the line drawn is the line walked. Pure and
## deterministic: the same points give the same samples on every run.

## Centripetal: the knots run on the square root of the chord, which never
## loops or cusps between close points.
const ALPHA := 0.5


## The control points with each repeat of the one before it dropped.
static func _distinct(points: Array) -> Array:
	var out: Array = []
	for p: Vector2i in points:
		if out.is_empty() or out[out.size() - 1] != p:
			out.append(p)
	return out


## The samples of each leg, leg i running from after control point i to
## control point i + 1 (inclusive): ceil(chord / step_m) of them, at least one,
## evenly spaced in the curve's own parameter.
static func legs(points: Array, step_m: int) -> Array:
	var pts := _distinct(points)
	var out: Array = []
	var n := pts.size()
	for i in range(n - 1):
		var p1 := Vector2(pts[i])
		var p2 := Vector2(pts[i + 1])
		var p0 := Vector2(pts[i - 1]) if i > 0 else p1 * 2.0 - p2
		var p3 := Vector2(pts[i + 2]) if i + 2 < n else p2 * 2.0 - p1
		var count := maxi(1, int(ceil(p1.distance_to(p2) / float(maxi(step_m, 1)))))
		var leg: Array = []
		for k in range(1, count):
			var at := point(p0, p1, p2, p3, float(k) / float(count))
			var w := Vector2i(int(round(at.x)), int(round(at.y)))
			if leg.is_empty() or leg[leg.size() - 1] != w:
				leg.append(w)
		leg.append(pts[i + 1])
		out.append(leg)
	return out


## The whole curve, first control point to last.
static func curve(points: Array, step_m: int) -> Array:
	var pts := _distinct(points)
	if pts.is_empty():
		return []
	var out: Array = [pts[0]]
	for leg: Array in legs(pts, step_m):
		out.append_array(leg)
	return out


## The point at `u` (0..1) between p1 and p2 (Barry and Goldman's pyramid).
## The WAR ROOM's staff strokes ride the same curve in floats (WarPlanGeometry).
static func point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + _knot(p0, p1)
	var t2 := t1 + _knot(p1, p2)
	var t3 := t2 + _knot(p2, p3)
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))


## A knot gap: the chord to the power ALPHA, never zero.
static func _knot(a: Vector2, b: Vector2) -> float:
	return maxf(pow(a.distance_to(b), ALPHA), 0.0001)


## Metres along a polyline of whole-metre points.
static func length_m(path: Array) -> float:
	var out := 0.0
	for i in range(1, path.size()):
		out += Vector2(path[i - 1]).distance_to(Vector2(path[i]))
	return out


## Metres from `here` along `path` to its end.
static func length_from(here: Vector2i, path: Array) -> float:
	if path.is_empty():
		return 0.0
	return Vector2(here).distance_to(Vector2(path[0])) + length_m(path)


## `metres` walked from `here` along `path`: {at: where it stops (whole metres),
## path: the points still ahead, passed: the points it reached}. A stop exactly
## on a point stands on it and drops it. `path` itself is never changed (the
## map's day-ahead preview walks a copy of a live entry).
static func walk(here: Vector2i, path: Array, metres: int) -> Dictionary:
	var h := Vector2(here)
	var left := float(metres)
	var i := 0
	var passed: Array = []
	while i < path.size():
		var p := Vector2(path[i])
		var seg := h.distance_to(p)
		if left < seg:
			var way := (p - h) / seg
			var at := Vector2i(int(round(h.x + way.x * left)), int(round(h.y + way.y * left)))
			return {"at": at, "path": path.slice(i), "passed": passed}
		left -= seg
		h = p
		passed.append(path[i])
		i += 1
	return {"at": Vector2i(h), "path": [], "passed": passed}


## The index of the leg whose samples pass nearest `at` (metres): where a
## waypoint grabbed off the line is inserted among the waypoints.
static func nearest_leg(points: Array, step_m: int, at: Vector2) -> int:
	var best := 0
	var best_d := INF
	var pts := _distinct(points)
	var all := legs(pts, step_m)
	for i in all.size():
		var prev := Vector2(pts[i])
		for q: Vector2i in all[i]:
			var d := Geometry2D.get_closest_point_to_segment(at, prev, Vector2(q)).distance_to(at)
			if d < best_d:
				best_d = d
				best = i
			prev = Vector2(q)
	return best


## The save's form: [[x, y], …] whole numbers.
static func to_pairs(points: Array) -> Array:
	var out: Array = []
	for p: Vector2i in points:
		out.append([p.x, p.y])
	return out


## Back from the save's form (a JSON number may come back a float).
static func from_pairs(pairs: Array) -> Array:
	var out: Array = []
	for p: Array in pairs:
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out
