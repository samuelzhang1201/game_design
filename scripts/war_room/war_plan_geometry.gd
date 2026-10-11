class_name WarPlanGeometry
extends RefCounted
## The shapes of the staff's strokes (spec 2026-10-07-war-room-annotations-
## and-planning-pieces §2.3), in any 2D frame with y DOWN (texture px, pack
## px, screen px): a drag smoothed to a few control points, a centripetal
## Catmull-Rom through every one of them, the axis arrow's widening band and
## filled head (its tail notched like a pennon), a front's saw teeth on the
## drawer's right, dashes, a crayon band round a line, and hit distances. Pure.

## Ramer–Douglas–Peucker at `tol`, coarsened (the tolerance doubled) until at
## most `max_n` points remain; the ends always kept.
static func simplify(points: PackedVector2Array, tol: float, max_n: int) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var t := maxf(tol, 0.0001)
	var out := _rdp(points, t)
	while out.size() > maxi(max_n, 2):
		t *= 2.0
		out = _rdp(points, t)
	return out


static func _rdp(points: PackedVector2Array, tol: float) -> PackedVector2Array:
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size() - 1] = 1
	var stack: Array = [[0, points.size() - 1]]
	while not stack.is_empty():
		var span: Array = stack.pop_back()
		var a := int(span[0])
		var b := int(span[1])
		var worst := -1.0
		var at := -1
		for i in range(a + 1, b):
			var d := Geometry2D.get_closest_point_to_segment(points[i], points[a], points[b]).distance_to(points[i])
			if d > worst:
				worst = d
				at = i
		if at >= 0 and worst > tol:
			keep[at] = 1
			stack.append([a, at])
			stack.append([at, b])
	var out := PackedVector2Array()
	for i in points.size():
		if keep[i] == 1:
			out.append(points[i])
	return out


## The curve through every control point, sampled about `step` apart: the
## march route's centripetal Catmull-Rom (MarchRoute.point, the ends'
## missing neighbours reflected as there), in floats rather than whole metres.
static func curve(ctrl: PackedVector2Array, step: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in ctrl:
		if pts.is_empty() or pts[pts.size() - 1] != p:
			pts.append(p)
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	var n := pts.size()
	for i in range(n - 1):
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p0 := pts[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := pts[i + 2] if i + 2 < n else p2 * 2.0 - p1
		var count := maxi(1, ceili(p1.distance_to(p2) / maxf(step, 0.0001)))
		for k in range(1, count):
			out.append(MarchRoute.point(p0, p1, p2, p3, float(k) / float(count)))
		out.append(p2)
	return out


static func length(path: PackedVector2Array) -> float:
	var out := 0.0
	for i in range(1, path.size()):
		out += path[i - 1].distance_to(path[i])
	return out


## The path from `from_len` to `to_len` along it, ends interpolated.
static func cut(path: PackedVector2Array, from_len: float, to_len: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var run := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var seg := a.distance_to(b)
		var s0 := run
		var s1 := run + seg
		run = s1
		if s1 < from_len or s0 > to_len or seg <= 0.0:
			continue
		if out.is_empty():
			out.append(a.lerp(b, clampf((from_len - s0) / seg, 0.0, 1.0)))
		out.append(a.lerp(b, clampf((to_len - s0) / seg, 0.0, 1.0)))
		if s1 >= to_len:
			break
	return out


## The unit direction of the path at each point (y down).
static func _dirs(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := path.size()
	for i in n:
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, n - 1)]
		var d := (b - a).normalized()
		out.append(d if d != Vector2.ZERO else Vector2.RIGHT)
	return out


## The drawer's right of a direction, y down.
static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## The axis arrow: {band, head} — the band widening from tail_w at its tail to
## neck_w at the head's base, a pennon's notch at its tail; the head a filled
## triangle head_w across, its tip the path's last point on its last tangent.
## A short path keeps its head at half its length, in proportion.
static func arrow(path: PackedVector2Array, tail_w: float, neck_w: float, head_len: float, head_w: float) -> Dictionary:
	var total := length(path)
	if path.size() < 2 or total <= 0.0:
		return {"band": PackedVector2Array(), "head": PackedVector2Array()}
	var hl := minf(head_len, total * 0.5)
	var hw := head_w * hl / head_len
	var body := cut(path, 0.0, total - hl)
	var dirs := _dirs(body)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var run := 0.0
	for i in body.size():
		if i > 0:
			run += body[i - 1].distance_to(body[i])
		var half := lerpf(tail_w, neck_w, run / maxf(total - hl, 0.0001)) * 0.5
		var n := right_of(dirs[i])
		left.append(body[i] - n * half)
		right.append(body[i] + n * half)
	var band := PackedVector2Array()
	band.append_array(left)
	right.reverse()
	band.append_array(right)
	band.append(body[0] + dirs[0] * tail_w * 0.55)   # the pennon's notch
	var tip := path[path.size() - 1]
	var d := (tip - body[body.size() - 1]).normalized()
	var base := tip - d * hl
	var n2 := right_of(d)
	var head := PackedVector2Array([base - n2 * hw * 0.5, tip, base + n2 * hw * 0.5, base + d * hl * 0.12])
	return {"band": band, "head": head}


## The front's teeth: a triangle `base` along the line and `height` off it
## every `every`, on the drawer's right (`side` 1) or left (-1).
static func teeth(path: PackedVector2Array, every: float, base: float, height: float, side: int) -> Array:
	var out: Array = []
	var total := length(path)
	var count := int(floor(total / maxf(every, 0.0001)))
	for k in count:
		var s := every * (float(k) + 0.5)
		var seg := cut(path, s - base * 0.5, s + base * 0.5)
		if seg.size() < 2:
			continue
		var a := seg[0]
		var b := seg[seg.size() - 1]
		var mid := cut(path, 0.0, s)
		var m := mid[mid.size() - 1] if mid.size() > 0 else a
		var n := right_of((b - a).normalized()) * float(side)
		out.append(PackedVector2Array([a, m + n * height, b]))
	return out


## Dashes `dash` long with `gap` between, from the path's start.
static func dashes(path: PackedVector2Array, dash: float, gap: float) -> Array:
	var out: Array = []
	var total := length(path)
	var s := 0.0
	while s < total:
		var piece := cut(path, s, minf(s + dash, total))
		if piece.size() >= 2 and length(piece) > 0.0:
			out.append(piece)
		s += dash + gap
	return out


## A closed outline `width` across round a path: what a crayon covers.
static func band(path: PackedVector2Array, width: float) -> PackedVector2Array:
	var dirs := _dirs(path)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in path.size():
		var n := right_of(dirs[i]) * width * 0.5
		left.append(path[i] - n)
		right.append(path[i] + n)
	right.reverse()
	left.append_array(right)
	return left


## How far `at` is from the path.
static func hit(path: PackedVector2Array, at: Vector2) -> float:
	if path.size() == 1:
		return path[0].distance_to(at)
	var best := INF
	for i in range(1, path.size()):
		best = minf(best, Geometry2D.get_closest_point_to_segment(at, path[i - 1], path[i]).distance_to(at))
	return best


## How far `at` is from a ring's rim.
static func ring_hit(centre: Vector2, radius: float, at: Vector2) -> float:
	return absf(centre.distance_to(at) - radius)


## The runs of `pts` lying inside `rect`, each cut exactly at the rect's edge
## (Liang-Barsky per segment); a road that leaves and comes back gives two.
static func clip_to_rect(pts: PackedVector2Array, rect: Rect2) -> Array:
	var out: Array = []
	var run := PackedVector2Array()
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := b - a
		var t0 := 0.0
		var t1 := 1.0
		var ok := true
		var ps := [-d.x, d.x, -d.y, d.y]
		var qs := [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
		for k in 4:
			var pk: float = ps[k]
			var qk: float = qs[k]
			if is_zero_approx(pk):
				if qk < 0.0:
					ok = false
					break
			else:
				var r := qk / pk
				if pk < 0.0:
					t0 = maxf(t0, r)
				else:
					t1 = minf(t1, r)
		if not ok or t0 > t1:
			if run.size() >= 2:
				out.append(run)
			run = PackedVector2Array()
			continue
		var ca := a + d * t0
		var cb := a + d * t1
		if run.is_empty() or t0 > 0.0:
			if run.size() >= 2:
				out.append(run)
			run = PackedVector2Array([ca])
		elif run[run.size() - 1] != ca:
			run.append(ca)
		run.append(cb)
		if t1 < 1.0:
			out.append(run)
			run = PackedVector2Array()
	if run.size() >= 2:
		out.append(run)
	return out
