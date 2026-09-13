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

static func polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total

## Shortest distance from p to any segment of the polyline (INF if empty).
static func distance_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	if pts.is_empty():
		return INF
	if pts.size() == 1:
		return p.distance_to(pts[0])
	var best := INF
	for i in range(1, pts.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])
		best = minf(best, p.distance_to(q))
	return best

## A closed polygon as the uniform cubic B-spline through its vertices —
## the curve Azgaar draws its coasts and borders with (d3 curveBasisClosed),
## so an outline drawn this way sits on the render's line instead of cutting
## its corners. `steps` samples per segment; the result has steps * n points
## and stays inside the polygon's convex hull.
##
## NOTHING ON THE MAP USES THIS ANY MORE (2026-09-13): borders and coasts
## moved to smooth_closed_through, because approximating meant the line
## drifted off the province boundary it was drawn from. It is kept as the
## approximating option — right for a purely decorative curve — and as the
## contrast test_the_b_spline_does_not_keep_them pins, so the two are not
## quietly merged back into one.
static func smooth_closed(pts: PackedVector2Array, steps: int) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or steps < 1:
		return pts
	var out := PackedVector2Array()
	out.resize(n * steps)
	var k := 0
	for i in n:
		var p0 := pts[(i - 1 + n) % n]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p3 := pts[(i + 2) % n]
		for j in steps:
			var t := float(j) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out[k] = (p0 * (1.0 - 3.0 * t + 3.0 * t2 - t3)
				+ p1 * (4.0 - 6.0 * t2 + 3.0 * t3)
				+ p2 * (1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3)
				+ p3 * t3) / 6.0
			k += 1
	return out

## A polyline broken into dashes: dash_px drawn, gap_px skipped, measured
## along the line's own arc length so the pattern carries across a vertex.
## Godot's draw_dashed_line restarts the phase on every call, which turns a
## smoothed border (four B-spline samples per segment) into mush — hence
## this. Returns the drawn pieces, each two or more points; the last dash is
## clipped where the line ends, never stretched. A dash or gap of zero means
## "solid": the whole line comes back as one piece.
static func dash_polyline(pts: PackedVector2Array, dash_px: float, gap_px: float) -> Array:
	var out: Array = []
	for run: Dictionary in dash_runs(pts, dash_px, gap_px):
		if bool(run["on"]):
			out.append(run["points"])
	return out

## The same walk, handing back the gaps as well: [{on: bool, points}, ...] in
## order along the line. A border drawn as a chequered ribbon — a dark run,
## then a light one — needs the geometry of both phases, not just the drawn
## half (owner request 2026-09-12).
static func dash_runs(pts: PackedVector2Array, dash_px: float, gap_px: float) -> Array:
	if pts.size() < 2:
		return []
	if dash_px <= 0.0 or gap_px <= 0.0:
		return [{"on": true, "points": pts}]
	var out: Array = []
	var piece := PackedVector2Array([pts[0]])
	var on := true
	var left := dash_px  # how much of the current run is still ahead
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var span := b - a
		var length := span.length()
		if length <= 0.0:
			continue
		var dir := span / length
		var walked := 0.0
		while length - walked > left:
			walked += left
			var p := a + dir * walked
			piece.append(p)
			out.append({"on": on, "points": piece})
			piece = PackedVector2Array([p])
			on = not on
			left = dash_px if on else gap_px
		left -= length - walked
		piece.append(b)
	if piece.size() >= 2:
		out.append({"on": on, "points": piece})
	return out

## The same dashes flattened into the point pairs draw_multiline wants, so a
## whole dashed border is one draw call instead of one per dash.
static func dash_segments(pts: PackedVector2Array, dash_px: float, gap_px: float) -> PackedVector2Array:
	var pairs := PackedVector2Array()
	for piece: PackedVector2Array in dash_polyline(pts, dash_px, gap_px):
		for i in range(1, piece.size()):
			pairs.append(piece[i - 1])
			pairs.append(piece[i])
	return pairs

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
static func smooth_closed_through(pts: PackedVector2Array, steps: int) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or steps < 1:
		return pts
	var out := PackedVector2Array()
	out.resize(n * steps)
	var k := 0
	for i in n:
		var p0: Vector2 = pts[(i - 1 + n) % n]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n]
		for j in steps:
			var t := float(j) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out[k] = 0.5 * ((2.0 * p1)
				+ (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			k += 1
	return out
