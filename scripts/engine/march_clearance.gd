class_name MarchClearance
extends RefCounted
## The geometry of unit clearance (spec docs/superpowers/specs/2026-10-14-unit-
## clearance-and-scouting-design.md §a, §b): every land unit is a disc whose
## radius is its arm's (`data/army/army_clearance.csv`); two units' centres stay
## at least D = r_a + r_b apart. Every function takes D per blocker, and works
## on the disc of D + 1 (the metre's margin that whole-metre rounding cannot eat).
## Pure whole-metre geometry: where a march first comes within C of a unit
## (`first_entry`), the halt point in front of it (`halt_point`), and the way
## round a clump of units (`detour`: an octagon round each, their convex hull,
## the shorter side of it, the right side on a tie). No random number, no state:
## ArmySystem decides what to do with the answers.

## The octagon's corners, east first and on round to the south (y down): their
## signs on the two axes; a corner is round(R8 * these) from the centre.
const _DIRS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const _TOL := 1e-9


## The octagon's radius: ceil(D / cos 22.5 degrees) + 1, so every edge stands
## more than D from the centre even where a whole-metre stop rounds it.
static func r8(d: int) -> int:
	return int(ceil(float(d) / cos(deg_to_rad(22.5)))) + 1


## The eight corners of the octagon round `q` for clearance `d`; the diagonal
## corners round UP.
static func octagon(q: Vector2i, d: int) -> Array:
	var r := r8(d)
	var diag := int(ceil(float(r) * sqrt(0.5)))
	var out: Array = []
	for dir: Vector2i in _DIRS:
		var k := diag if dir.x != 0 and dir.y != 0 else r
		out.append(q + Vector2i(dir.x * k, dir.y * k))
	return out


## The convex hull of `points` (monotone chain, whole numbers, collinear points
## dropped), starting at the lowest x (then y).
static func hull(points: Array) -> Array:
	var pts := points.duplicate()
	pts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var uniq: Array = []
	for p: Vector2i in pts:
		if uniq.is_empty() or uniq[uniq.size() - 1] != p:
			uniq.append(p)
	if uniq.size() < 3:
		return uniq
	var lower: Array = []
	for p: Vector2i in uniq:
		while lower.size() >= 2 and _cross(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0:
			lower.pop_back()
		lower.append(p)
	var upper: Array = []
	for i in range(uniq.size() - 1, -1, -1):
		var p: Vector2i = uniq[i]
		while upper.size() >= 2 and _cross(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


## (b - o) x (p - o) in whole numbers.
static func _cross(o: Vector2i, b: Vector2i, p: Vector2i) -> int:
	return (b.x - o.x) * (p.y - o.y) - (b.y - o.y) * (p.x - o.x)


## The hull round the octagons of `centres` (`ds[i]` the clearance to centre i).
static func hull_of(centres: Array, ds: Array) -> Array:
	var pts: Array = []
	for i in centres.size():
		pts.append_array(octagon(centres[i], int(ds[i])))
	return hull(pts)


## Whether `p` lies in the hull (its edge included).
static func in_hull(h: Array, p: Vector2i) -> bool:
	if h.size() < 3:
		return false
	for i in h.size():
		if _cross(h[i], h[(i + 1) % h.size()], p) < 0:
			return false
	return true


## The indices of `centres` that make a clump with `first`: every centre whose
## octagon touches a member's (the centres within r8 + r8 of each other),
## transitively, but none further than `limit_m` from the first (a whole host
## strung out along a road is not ONE obstacle; the later passes take the rest)
## (ascending order).
static func clump(first: int, centres: Array, ds: Array, limit_m := 1 << 30) -> Array:
	var members := {first: true}
	var cap2 := limit_m * limit_m
	var grew := true
	while grew:
		grew = false
		for i in centres.size():
			if members.has(i) or dist2(centres[i], centres[first]) > cap2:
				continue
			for m: int in members:
				var reach := r8(int(ds[i])) + r8(int(ds[m]))
				var d: Vector2i = centres[i] - centres[m]
				if d.x * d.x + d.y * d.y <= reach * reach:
					members[i] = true
					grew = true
					break
	var out := members.keys()
	out.sort()
	return out


## Squared distance in whole numbers.
static func dist2(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return d.x * d.x + d.y * d.y


## Where the segment a->b first comes within D + 1 of `q`: the smaller root of
## |a + t(b - a) - q| = D + 1 in [0, 1], rounded to whole metres and, were the
## rounding to leave it inside, stepped back along the path one metre at a time
## until it stands at least D + 1 away. `a` itself when the segment never
## enters the disc, or `a` is already inside it.
static func halt_point(a: Vector2i, b: Vector2i, q: Vector2i, pair: int) -> Vector2i:
	var c := pair + 1
	var t := _entry_t(a, b, q, c)
	if t < 0.0:
		return a
	var d := Vector2(b - a)
	var span_m := d.length()
	var way := d / span_m if span_m > 0.0 else Vector2.ZERO
	var along := t * span_m
	var p := Vector2i(int(round(float(a.x) + way.x * along)), int(round(float(a.y) + way.y * along)))
	var back := 0.0
	while dist2(p, q) < c * c and along - back > 0.0:
		back += 1.0
		var s := maxf(along - back, 0.0)
		p = Vector2i(int(round(float(a.x) + way.x * s)), int(round(float(a.y) + way.y * s)))
	return p


## The segment parameter at which a->b enters the disc (centre q, radius c) in
## [0, 1]; -1.0 when it does not. From a point already INSIDE the disc: 0.0 when
## the leg closes on the centre (it is stopped on the spot), -1.0 when it only
## walks away from it.
static func _entry_t(a: Vector2i, b: Vector2i, q: Vector2i, c: int) -> float:
	if dist2(a, q) < c * c:
		return 0.0 if (b.x - a.x) * (q.x - a.x) + (b.y - a.y) * (q.y - a.y) > 0 else -1.0
	# 64-bit scalars (a Vector2 is 32-bit and loses the tangent)
	var dx := float(b.x - a.x)
	var dy := float(b.y - a.y)
	var fx := float(a.x - q.x)
	var fy := float(a.y - q.y)
	var qa := dx * dx + dy * dy
	if qa <= 0.0:
		return -1.0
	var qb := 2.0 * (fx * dx + fy * dy)
	var qc := fx * fx + fy * fy - float(c) * float(c)
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return -1.0   # a pass at exactly c touches, never enters
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## The first disc a walk along `here` -> `path` enters: {index (into `centres`),
## leg (the index into `path` of the leg's end; the leg starts at `here` or the
## point before), at (the halt point, whole metres), dist (metres along the
## path to it)}; `ds[i]` is the clearance to centre i. {} when none is entered. Within one leg the disc entered at
## the smallest parameter wins, ties to the lower index.
static func first_entry(here: Vector2i, path: Array, centres: Array, ds: Array) -> Dictionary:
	var prev := here
	var walked := 0.0
	for i in path.size():
		var p: Vector2i = path[i]
		var best_t := 2.0
		var best := -1
		for k in centres.size():
			var t := _entry_t(prev, p, centres[k], int(ds[k]) + 1)
			if t >= 0.0 and t < best_t:
				best_t = t
				best = k
		if best >= 0:
			var at := halt_point(prev, p, centres[best], int(ds[best]))
			return {"index": best, "leg": i, "at": at, "dist": walked + Vector2(prev).distance_to(Vector2(at))}
		walked += Vector2(prev).distance_to(Vector2(p))
		prev = p
	return {}


## Where the segment a->b crosses the hull's edges: [{t, edge}] (the edge i runs
## h[i] -> h[i + 1]) in segment order.
static func _crossings(a: Vector2i, b: Vector2i, h: Array) -> Array:
	var out: Array = []
	var d := Vector2(b - a)
	for i in h.size():
		var u: Vector2i = h[i]
		var e := Vector2(h[(i + 1) % h.size()] - u)
		var den := d.x * e.y - d.y * e.x
		if absf(den) < _TOL:
			continue
		var w := Vector2(u - a)
		var t := (w.x * e.y - w.y * e.x) / den
		var s := (w.x * d.y - w.y * d.x) / den
		if t >= -_TOL and t <= 1.0 + _TOL and s >= -_TOL and s <= 1.0 + _TOL:
			out.append({"t": clampf(t, 0.0, 1.0), "edge": i})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x["t"]) < float(y["t"]) or (float(x["t"]) == float(y["t"]) and int(x["edge"]) < int(y["edge"])))
	return out


static func _point_on(a: Vector2i, b: Vector2i, t: float) -> Vector2i:
	return Vector2i(int(round(float(a.x) + float(b.x - a.x) * t)), int(round(float(a.y) + float(b.y - a.y) * t)))


## The length of a polyline as the sum of its edges each rounded to whole metres.
static func length_of(pts: Array) -> int:
	var n := 0
	for i in range(1, pts.size()):
		n += int(round(Vector2(pts[i - 1]).distance_to(Vector2(pts[i]))))
	return n


## The way round the clump `centres` for a walk along `here` -> `path`: the
## hull's two sides between the path's first crossing E and last crossing X,
## the shorter by whole metres (a tie goes to the RIGHT hand: cross(X - E,
## v - E) > 0, +y heading east in the y-down frame), a side any of whose legs
## `leg_ok(a, b)` refuses given up for the other. Returns {kind "route", path
## (the whole new road: the points before E, E, the hull's corners, X, the
## points after X), entry E, exit X} or {kind "wait", at E} when both sides are
## closed (or the walk has no clean crossing: it starts inside the hull, `dist` 0);
## `dist` is the metres of the road up to E, where the column stands. `leg_ok` unset: every leg is open.
static func detour(here: Vector2i, path: Array, centres: Array, ds: Array, leg_ok := Callable(), hull_in := []) -> Dictionary:
	var h: Array = hull_in if not hull_in.is_empty() else hull_of(centres, ds)
	var n := h.size()
	var inside := in_hull(h, here)
	var first := {}
	var last := {}
	var first_leg := -1
	var last_leg := -1
	var prev := here
	var walked := 0.0
	var e_dist := 0.0
	for i in path.size():
		var cr := _crossings(prev, path[i], h)
		if not cr.is_empty():
			if first.is_empty():
				first = cr[0]
				first["a"] = prev
				first["b"] = path[i]
				first_leg = i
				e_dist = walked + Vector2(prev).distance_to(Vector2(_point_on(prev, path[i], float(first["t"]))))
			last = cr[cr.size() - 1]
			last["a"] = prev
			last["b"] = path[i]
			last_leg = i
		walked += Vector2(prev).distance_to(Vector2(path[i]))
		prev = path[i]
	if last.is_empty() or n < 3:
		return {"kind": "wait", "at": here, "dist": 0}
	var e_pt: Vector2i
	var i_e: int
	if inside:
		# the column stands inside the hull (a camp slot 1500 m from a unit, a
		# neighbour's octagon reaching it): it steps out by the nearest point of
		# the hull's edge and goes round from there
		var best := INF
		i_e = 0
		e_pt = here
		for i in n:
			var q := Geometry2D.get_closest_point_to_segment(Vector2(here), Vector2(h[i]), Vector2(h[(i + 1) % n]))
			var d := q.distance_to(Vector2(here))
			if d < best:
				best = d
				i_e = i
				e_pt = Vector2i(int(round(q.x)), int(round(q.y)))
		first_leg = 0
		e_dist = 0.0
	else:
		e_pt = _point_on(first["a"], first["b"], float(first["t"]))
		i_e = int(first["edge"])
	var x_pt := _point_on(last["a"], last["b"], float(last["t"]))
	var i_x := int(last["edge"])
	var fwd: Array = [e_pt]
	var back: Array = [e_pt]
	if i_e != i_x:
		var k := (i_e + 1) % n
		while true:
			fwd.append(h[k])
			if k == i_x:
				break
			k = (k + 1) % n
		k = i_e
		while true:
			back.append(h[k])
			if k == (i_x + 1) % n:
				break
			k = (k - 1 + n) % n
	fwd.append(x_pt)
	back.append(x_pt)
	fwd = MarchRoute.distinct(fwd)
	back = MarchRoute.distinct(back)
	var sides: Array = []
	for side: Array in [fwd, back]:
		sides.append({"pts": side, "len": length_of(side), "right": _rightness(e_pt, x_pt, side)})
	var order := [0, 1]
	var l0 := int(sides[0]["len"])
	var l1 := int(sides[1]["len"])
	if l1 < l0 or (l1 == l0 and int(sides[1]["right"]) > int(sides[0]["right"])):
		order = [1, 0]
	for k2: int in order:
		var s: Dictionary = sides[k2]
		if _open(s["pts"], leg_ok):
			var out: Array = path.slice(0, first_leg)
			out.append_array(s["pts"])
			out.append_array(path.slice(last_leg))
			return {"kind": "route", "path": MarchRoute.distinct(out), "entry": e_pt, "exit": x_pt}
	return {"kind": "wait", "at": e_pt, "dist": int(e_dist)}


## 1 when the side bulges to the right of E -> X (the farthest corner decides),
## else 0.
static func _rightness(e_pt: Vector2i, x_pt: Vector2i, side: Array) -> int:
	var best := 0
	var best_abs := -1
	for p: Vector2i in side:
		var cr := _cross(e_pt, x_pt, p)
		if absi(cr) > best_abs:
			best_abs = absi(cr)
			best = cr
	return 1 if best > 0 else 0


static func _open(side: Array, leg_ok: Callable) -> bool:
	if not leg_ok.is_valid():
		return true
	for i in range(1, side.size()):
		if not bool(leg_ok.call(side[i - 1], side[i])):
			return false
	return true
