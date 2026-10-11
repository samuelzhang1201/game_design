class_name WarFront
extends RefCounted
## A blue FRONT LINE's posts (owner 2026-10-11, spec 2026-10-11-war-room-
## front-line-design §1): the drawn line cut into one equal length per
## regiment, each regiment sent to its length's middle to HOLD facing the
## teeth. Pure maths; whole metres and a whole degree out, no state written,
## no RNG. The facing is the pack's y-down frame: 0 east, 90 south, 180 west,
## 270 north (the WarPlans pieces' `facing_deg`). The teeth's side is the
## stroke's `flip` (WarPlans.facing_flip: 0 the drawer's right, 1 the left).

const HOLD_STANCE := "hold"


## The polyline's point `d` metres along it (clamped to its ends).
static func at_length(path_m: Array, d: float) -> Vector2:
	if path_m.is_empty():
		return Vector2.ZERO
	var walked := 0.0
	for i in range(1, path_m.size()):
		var a := Vector2(path_m[i - 1])
		var b := Vector2(path_m[i])
		var seg := a.distance_to(b)
		if walked + seg >= d and seg > 0.0:
			return a.lerp(b, clampf((d - walked) / seg, 0.0, 1.0))
		walked += seg
	return Vector2(path_m[path_m.size() - 1])


## The polyline's length in metres.
static func length_of(path_m: Array) -> float:
	var total := 0.0
	for i in range(1, path_m.size()):
		total += Vector2(path_m[i - 1]).distance_to(Vector2(path_m[i]))
	return total


## The posts of `n` regiments along `path_m` (whole-metre Vector2i, in
## drawing order): [{dest_m: Vector2i, facing_deg: int}], post k the middle
## of the k-th of n equal lengths, facing the normal of that length's CHORD on
## the teeth's side. n < 1 or a line without length: [].
static func split(path_m: Array, flip: int, n: int) -> Array:
	var out: Array = []
	var total := length_of(path_m)
	if n < 1 or total <= 0.0:
		return out
	for k in n:
		var a := at_length(path_m, total * float(k) / float(n))
		var b := at_length(path_m, total * float(k + 1) / float(n))
		var mid := at_length(path_m, total * (float(k) + 0.5) / float(n))
		out.append({"dest_m": Vector2i(int(round(mid.x)), int(round(mid.y))),
			"facing_deg": facing_deg(normal_of(a, b, flip))})
	return out


## The unit normal a front from `a` to `b` faces: `flip` 0 the drawer's
## right ((-dir.y, dir.x), as WarPlans.facing_flip reads it), 1 the left.
static func normal_of(a: Vector2, b: Vector2, flip: int) -> Vector2:
	var dir := (b - a).normalized()
	var right := Vector2(-dir.y, dir.x)
	return right if flip == 0 else -right


## A direction as a whole degree 0..359 (0 along +x, 90 along +y).
static func facing_deg(normal: Vector2) -> int:
	return posmod(int(round(rad_to_deg(atan2(normal.y, normal.x)))), 360)


## A facing back as a unit direction in the same frame.
static func facing_vector(deg: int) -> Vector2:
	return Vector2.from_angle(deg_to_rad(float(deg)))


## How far along `path_m` (metres) the point `p_m` projects, nearest first
## (the regiment's place on the line, for the assignment's order).
static func along_of(path_m: Array, p_m: Vector2) -> float:
	var best := INF
	var at := 0.0
	var walked := 0.0
	for i in range(1, path_m.size()):
		var a := Vector2(path_m[i - 1])
		var b := Vector2(path_m[i])
		var q := Geometry2D.get_closest_point_to_segment(p_m, a, b)
		var d := q.distance_to(p_m)
		if d < best:
			best = d
			at = walked + a.distance_to(q)
		walked += a.distance_to(b)
	return at


## The posts assigned to `codes` for a front stroke (WarPlans' dict: `pts`
## whole-metre pairs, `flip`): [{code, dest_m, facing_deg}] — the line is the
## stroke's own curve (MarchRoute.curve at army_route_sample_m), the posts
## taken in the order of each regiment's place projected along it (ties by
## code), so columns never cross (ruling 2). `positions_m` is code -> Vector2
## (metres) where each stands.
static func assign(repo: DataRepository, stroke: Dictionary, codes: Array, positions_m: Dictionary) -> Array:
	var out: Array = []
	if codes.is_empty():
		return out
	var path := MarchRoute.curve(MarchRoute.from_pairs(stroke.get("pts", [])), int(repo.bal("army_route_sample_m")))
	var posts := split(path, int(stroke.get("flip", 0)), codes.size())
	if posts.is_empty():
		return out
	var ordered: Array = []
	for c: Variant in codes:
		ordered.append(String(c))
	ordered.sort_custom(func(x: String, y: String) -> bool:
		var ax := along_of(path, positions_m.get(x, Vector2.ZERO))
		var ay := along_of(path, positions_m.get(y, Vector2.ZERO))
		return ax < ay if not is_equal_approx(ax, ay) else x < y)
	for k in ordered.size():
		out.append({"code": ordered[k], "dest_m": posts[k]["dest_m"], "facing_deg": posts[k]["facing_deg"]})
	return out


## A facing in words for the scroll and the receipts: the compass point and
## the bearing, e.g. 90 -> "S (180°)".
static func compass_words(deg: int) -> String:
	var bearing := posmod(deg + 90, 360)
	var points := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx := int(round(float(bearing) / 45.0)) % 8
	return "%s (%d°)" % [points[idx], bearing]
