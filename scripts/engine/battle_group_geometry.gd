class_name BattleGroupGeometry
extends RefCounted
## Read-only legacy geometry. No production writer or combat reader opts in here.

const INT_MAX: int = 9223372036854775807
const INT_MIN: int = -9223372036854775807 - 1


## Resolve the drawn piece, never an assumed chief-arm radius or a fallback disc.
static func footprint(repo: DataRepository, regiment: Dictionary) -> Dictionary:
	var piece := MapObjects.army_piece(repo, regiment)
	var row: Dictionary = repo.unit_footprints.get(piece, {})
	if not _natural(row.get("radius_m")) or not _natural(row.get("pitch_m")):
		return _error("Missing or invalid piece footprint: " + piece)
	var radius := int(row.radius_m)
	var pitch := int(row.pitch_m)
	var check := pair([0, 0], radius, [pitch, 0], radius, 0)
	if radius == 0 or pitch == 0 or not check.ok or check.overlap:
		return _error("Invalid piece footprint separation: " + piece)
	return {"ok": true, "piece": piece, "radius_m": radius, "pitch_m": pitch}


## Occupied discs may touch; attack reach includes the edge-distance boundary.
static func pair(a: Array, radius_a: int, b: Array, radius_b: int, reach: int) -> Dictionary:
	if not _point(a) or not _point(b) or radius_a < 0 or radius_b < 0 or reach < 0:
		return _error("Invalid pair geometry")
	var dx: Variant = _sub(int(b[0]), int(a[0]))
	var dy: Variant = _sub(int(b[1]), int(a[1]))
	var radius: Variant = _add(radius_a, radius_b)
	var limit: Variant = _add(radius, reach)
	var distance_sq: Variant = _dot(dx, dy, dx, dy)
	var radius_sq: Variant = _mul(radius, radius)
	var limit_sq: Variant = _mul(limit, limit)
	if distance_sq == null or radius_sq == null or limit_sq == null:
		return _error("Pair arithmetic overflow")
	return {"ok": true, "distance_sq": distance_sq,
		"overlap": distance_sq < radius_sq, "in_reach": distance_sq <= limit_sq}


## Open shot segment: interior tangency blocks; endpoint-only tangency does not.
## Swept occupied discs instead allow tangency everywhere (tangent_blocks=false).
static func segment_disc(a: Array, b: Array, centre: Array, radius: int,
		tangent_blocks: bool = true) -> Dictionary:
	if not _point(a) or not _point(b) or not _point(centre) or radius < 0:
		return _error("Invalid segment geometry")
	var dx: Variant = _sub(int(b[0]), int(a[0]))
	var dy: Variant = _sub(int(b[1]), int(a[1]))
	var ox: Variant = _sub(int(centre[0]), int(a[0]))
	var oy: Variant = _sub(int(centre[1]), int(a[1]))
	var length_sq: Variant = _dot(dx, dy, dx, dy)
	var along: Variant = _dot(ox, oy, dx, dy)
	var radius_sq: Variant = _mul(radius, radius)
	if length_sq == null or along == null or radius_sq == null:
		return _error("Segment arithmetic overflow")
	if along <= 0 or along >= length_sq:
		var end: Array = a if along <= 0 else b
		var endpoint := pair(end, radius, centre, 0, 0)
		if not endpoint.ok: return endpoint
		return {"ok": true, "blocked": endpoint.overlap}
	var cross: Variant = _sub(_mul(ox, dy), _mul(oy, dx))
	var cross_sq: Variant = _mul(cross, cross)
	var bound: Variant = _mul(radius_sq, length_sq)
	if cross_sq == null or bound == null: return _error("Segment product overflow")
	return {"ok": true, "blocked": cross_sq <= bound if tangent_blocks else cross_sq < bound}


## World-axis bounds of actual rounded row centres, expanded by their piece radius.
static func envelope(rows: Array, radius: int) -> Dictionary:
	if rows.is_empty() or radius < 0: return _error("Empty or invalid envelope")
	var out := {"ok": true, "min_x_m": INT_MAX, "min_y_m": INT_MAX,
		"max_x_m": INT_MIN, "max_y_m": INT_MIN}
	for row: Variant in rows:
		if not _row(row): return _error("Invalid envelope row")
		for axis: String in ["x", "y"]:
			var low: Variant = _sub(int(row[axis + "_m"]), radius)
			var high: Variant = _add(int(row[axis + "_m"]), radius)
			if low == null or high == null: return _error("Envelope coordinate overflow")
			out["min_" + axis + "_m"] = mini(out["min_" + axis + "_m"], low)
			out["max_" + axis + "_m"] = maxi(out["max_" + axis + "_m"], high)
	var width: Variant = _sub(out.max_x_m, out.min_x_m)
	var depth: Variant = _sub(out.max_y_m, out.min_y_m)
	if width == null or depth == null: return _error("Envelope extent overflow")
	out.width_m = width
	out.depth_m = depth
	return out


## Validate a straight rigid translation against a distance budget and stationary
## heterogeneous discs. No terrain, routing, anchor, rows or saved paths are changed.
static func rigid_step(rows: Array, radius: int, delta: Array, max_step: int,
		blockers: Array) -> Dictionary:
	var source := envelope(rows, radius)
	if not source.ok: return source
	var budget := pair([0, 0], 0, delta, 0, max_step)
	if not budget.ok: return budget
	var allowed: bool = budget.in_reach
	var moved: Array = []
	for blocker: Variant in blockers:
		if not _row(blocker) or not _natural(blocker.get("radius_m")):
			return _error("Invalid rigid-step blocker")
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var start: Array = [row.x_m, row.y_m]
		var x: Variant = _add(int(row.x_m), int(delta[0]))
		var y: Variant = _add(int(row.y_m), int(delta[1]))
		if x == null or y == null: return _error("Rigid-step coordinate overflow")
		var end: Array = [x, y]
		moved.append({"x_m": x, "y_m": y})
		for other: Dictionary in rows.slice(0, index):
			var spacing := pair(start, radius, [other.x_m, other.y_m], radius, 0)
			if not spacing.ok: return spacing
			allowed = allowed and not spacing.overlap
		for blocker: Dictionary in blockers:
			var combined: Variant = _add(radius, int(blocker.radius_m))
			if combined == null: return _error("Rigid-step radius overflow")
			var hit := segment_disc(start, end, [blocker.x_m, blocker.y_m], combined, false)
			if not hit.ok: return hit
			allowed = allowed and not hit.blocked
	var bounds := envelope(moved, radius)
	if not bounds.ok: return bounds
	return {"ok": true, "allowed": allowed, "envelope": bounds}


static func _whole(value: Variant) -> bool:
	if value is int: return true
	return value is float and is_finite(value) and value >= float(INT_MIN) \
		and value < float(INT_MAX) and value == floor(value)


static func _natural(value: Variant) -> bool:
	return _whole(value) and value >= 0


static func _point(value: Array) -> bool:
	return value.size() == 2 and _whole(value[0]) and _whole(value[1])


static func _row(value: Variant) -> bool:
	return value is Dictionary and _whole(value.get("x_m")) and _whole(value.get("y_m"))


static func _add(a: Variant, b: Variant) -> Variant:
	if a == null or b == null: return null
	if (b > 0 and a > INT_MAX - b) or (b < 0 and a < INT_MIN - b): return null
	return int(a) + int(b)


static func _sub(a: Variant, b: Variant) -> Variant:
	if b == null or b == INT_MIN: return null
	return _add(a, -int(b))


static func _mul(a: Variant, b: Variant) -> Variant:
	if a == null or b == null or a == INT_MIN or b == INT_MIN: return null
	@warning_ignore("integer_division")
	if b != 0 and absi(a) > INT_MAX / absi(b): return null
	return int(a) * int(b)


static func _dot(ax: Variant, ay: Variant, bx: Variant, by: Variant) -> Variant:
	return _add(_mul(ax, bx), _mul(ay, by))


static func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
