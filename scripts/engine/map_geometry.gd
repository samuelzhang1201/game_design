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
