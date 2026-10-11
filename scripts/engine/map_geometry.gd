class_name MapGeometry
extends RefCounted
## Pure helpers over the map pack's vector data (tools/import_azgaar.gd writes
## it; DataRepository.load_map reads it). Points travel through the CSVs as
## "x y|x y|..." in native Azgaar map coordinates — the same space as the
## index bitmap and burgs.csv, so the view converts with one scale factor.
## No Nodes, no RNG: safe for headless tests.

static func parse_points(text: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pair in text.split("|", false):
		var xy := pair.strip_edges().split(" ", false)
		if xy.size() == 2:
			out.append(Vector2(float(xy[0]), float(xy[1])))
	return out

## Axis-aligned bounds of a polyline (Rect2() for no points).
static func bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r

## The largest 1, 2 or 5 times a power of ten that does not exceed `raw` —
## the ladder a scale bar is allowed to land on, so it reads "200 km" and
## never "187 km". 0 for nothing to measure.
static func nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 0.0
	var base: float = pow(10.0, floor(log(raw) / log(10.0)))
	var lead := raw / base
	# log/pow round-off can push the leading digit just outside [1, 10)
	if lead >= 10.0:
		base *= 10.0
		lead /= 10.0
	elif lead < 1.0:
		base /= 10.0
		lead *= 10.0
	if lead >= 5.0:
		return 5.0 * base
	if lead >= 2.0:
		return 2.0 * base
	return base

## smooth_closed's open sibling: the same uniform cubic B-spline over a line
## with two ends. The ends are clamped by repeating the endpoint through the
## span, so the curve starts and finishes exactly on them — a smoothed river
## must still meet its coast. Returns (n + 1) * steps + 1 points.
static func smooth_open(pts: PackedVector2Array, steps: int) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or steps < 1:
		return pts
	var out := PackedVector2Array()
	out.resize((n + 1) * steps + 1)
	var k := 0
	for i in range(-2, n - 1):
		var p0 := pts[clampi(i, 0, n - 1)]
		var p1 := pts[clampi(i + 1, 0, n - 1)]
		var p2 := pts[clampi(i + 2, 0, n - 1)]
		var p3 := pts[clampi(i + 3, 0, n - 1)]
		for j in steps:
			var t := float(j) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out[k] = (p0 * (1.0 - 3.0 * t + 3.0 * t2 - t3)
				+ p1 * (4.0 - 6.0 * t2 + 3.0 * t3)
				+ p2 * (1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3)
				+ p3 * t3) / 6.0
			k += 1
	out[k] = pts[n - 1]
	return out


## A polyline swollen into a filled ribbon whose half-width varies PER POINT.
## draw_polyline takes one width for the whole line, which is why every river
## on the sheet came out the same thickness from source to sea; a drawn river
## is a hairline where it rises and widest where it empties. Returns a
## triangle LIST — three points per triangle, ready for
## RenderingServer.canvas_item_add_triangle_array. Empty unless there is one
## half-width per point and at least two points.
static func ribbon(pts: PackedVector2Array, half: PackedFloat32Array) -> PackedVector2Array:
	var n := pts.size()
	if n < 2 or half.size() != n:
		return PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	left.resize(n)
	right.resize(n)
	for i in n:
		# At a bend the offset follows the bisector of the two legs, so the
		# band neither pinches on the inside nor tears on the outside.
		var dir := Vector2.ZERO
		if i > 0:
			dir += (pts[i] - pts[i - 1]).normalized()
		if i < n - 1:
			dir += (pts[i + 1] - pts[i]).normalized()
		if dir.length_squared() == 0.0:
			dir = Vector2.RIGHT
		var off := dir.normalized().orthogonal() * half[i]
		left[i] = pts[i] + off
		right[i] = pts[i] - off
	var tris := PackedVector2Array()
	for i in range(n - 1):
		tris.append(left[i]); tris.append(right[i]); tris.append(left[i + 1])
		tris.append(right[i]); tris.append(right[i + 1]); tris.append(left[i + 1])
	return tris


## smooth_closed's interpolating sibling: a closed Catmull-Rom ring that runs
## THROUGH every control point instead of cutting the corners off.
##
## The B-spline above only approximates, which is fine for a decorative shore
## but wrong for a border: a kingdom's outline is the merge of real province
## loops, and drifting inside them means the line no longer sits on the
## boundary it claims to draw (owner 2026-09-13). Catmull-Rom keeps the fit
## and still smooths everything between the points.
##
## Uniform knots overshoot: a short Voronoi edge sitting between two long
## ones gets a tangent scaled by its long neighbours, and the curve loops or
## cusps past the short span (owner 2026-09-19: 108 self-crossings, 58
## back-tracking vertices on the default pack's kingdom borders). CENTRIPETAL
## knots (alpha 0.5, Barry-Goldman) size each span's parameter interval by
## the square root of its chord length, so a short edge gets a short
## interval and the curve can neither cusp nor loop through it — 0 and 0 on
## the same pack. Near-duplicate points (a near-zero Voronoi edge) are
## dropped first, since a knot of zero length is the degenerate case
## centripetal spacing cannot help.
##
## `pinned[i] == 1` reflects point i's own segment for its neighbour's
## tangent instead of reading past it, so the curve leaves (or arrives at)
## a pinned point along the edge itself. Two kingdoms sharing a border edge
## pin its endpoints (MapOwnership.outline_pins) so both smooth that edge
## into the exact same curve instead of two copies that part company near
## the junction.
static func smooth_closed_through(pts: PackedVector2Array, steps: int,
		pinned := PackedByteArray()) -> PackedVector2Array:
	# Drop near-duplicates first (a 0.0005 px Voronoi edge would make a knot
	# of zero length), carrying each kept point's pin.
	var p := PackedVector2Array()
	var pin := PackedByteArray()
	for i in pts.size():
		if p.size() > 0 and pts[i].distance_to(p[p.size() - 1]) < 1e-3:
			if i < pinned.size() and pinned[i] == 1:
				pin[pin.size() - 1] = 1
			continue
		p.append(pts[i])
		pin.append(1 if i < pinned.size() and pinned[i] == 1 else 0)
	if p.size() > 1 and p[0].distance_to(p[p.size() - 1]) < 1e-3:
		if pin[pin.size() - 1] == 1:
			pin[0] = 1
		p.remove_at(p.size() - 1)
		pin.remove_at(pin.size() - 1)
	var n := p.size()
	if n < 3 or steps < 1:
		return p
	var out := PackedVector2Array()
	out.resize(n * steps)
	var k := 0
	for i in n:
		var p1: Vector2 = p[i]
		var p2: Vector2 = p[(i + 1) % n]
		# A pinned end reflects its own segment, so the curve leaves (or
		# reaches) a junction along the edge itself and both kingdoms that
		# share the edge draw the same curve.
		var p0: Vector2 = 2.0 * p1 - p2 if pin[i] == 1 else p[(i - 1 + n) % n]
		var p3: Vector2 = 2.0 * p2 - p1 if pin[(i + 1) % n] == 1 else p[(i + 2) % n]
		# Centripetal knots (alpha 0.5, Barry-Goldman): a short edge between
		# long ones can neither cusp nor loop (the uniform form made 108 curls
		# on the default pack, owner 2026-09-19).
		var t1 := maxf(sqrt(p0.distance_to(p1)), 1e-4)
		var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-4)
		var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-4)
		for j in steps:
			if j == 0:
				out[k] = p1
				k += 1
				continue
			var t := lerpf(t1, t2, float(j) / float(steps))
			var a1 := p0.lerp(p1, t / t1)
			var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
			var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
			var b1 := a1.lerp(a2, t / t2)
			var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
			out[k] = b1.lerp(b2, (t - t1) / (t2 - t1))
			k += 1
	return out


## `pts` with its last `gap` of length taken off (the line stops short of its
## end, along its own course); empty when the line is no longer than `gap`.
## Used where a broken supply line stops short of its column.
static func stop_short(pts: PackedVector2Array, gap: float) -> PackedVector2Array:
	if pts.size() < 2:
		return PackedVector2Array()
	var left := gap
	var out := pts.duplicate()
	while out.size() >= 2:
		var a := out[out.size() - 2]
		var b := out[out.size() - 1]
		var seg := a.distance_to(b)
		if seg > left:
			out[out.size() - 1] = b.move_toward(a, left)
			return out
		left -= seg
		out.resize(out.size() - 1)
	return PackedVector2Array()


## A short bar ACROSS the end of `pts`, `half` each way of its last point,
## square to its last segment: [one side, the other]; empty for a line of
## fewer than two distinct points (the break mark of a broken supply line).
static func tick_across(pts: PackedVector2Array, half: float) -> PackedVector2Array:
	if pts.size() < 2:
		return PackedVector2Array()
	var end := pts[pts.size() - 1]
	var dir := (end - pts[pts.size() - 2]).normalized()
	if dir == Vector2.ZERO:
		return PackedVector2Array()
	var n := Vector2(-dir.y, dir.x) * half
	return PackedVector2Array([end + n, end - n])
