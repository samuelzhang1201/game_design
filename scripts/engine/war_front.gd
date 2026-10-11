class_name WarFront
extends RefCounted
## A blue FRONT LINE's posts (owner 2026-10-11, spec 2026-10-11-front-line-
## design.md §1): the drawn line cut into one equal-length segment per
## regiment, each regiment sent to its segment's middle to HOLD facing the
## teeth. Pure maths on the stroke's whole-metre points (WarPlans strokes
## `pts`, the same y-down frame as the pack): no state, no RNG, whole metres
## out, a whole degree for the facing. The teeth's side is the stroke's `flip`
## (WarPlans.facing_flip: 0 the drawer's right, 1 the left).


## Each post along `pts` (whole metres, in drawing order) for `n` regiments:
## [{mid: Vector2i, facing_deg: int, normal: Vector2}], post k the middle of
## the k-th of n equal lengths of the polyline. Fewer than two distinct points
## or n < 1: empty.
static func posts(pts: PackedVector2Array, n: int, flip: int) -> Array:
	var out: Array = []
	if n < 1 or pts.size() < 2:
		return out
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	if total <= 0.0:
		return out
	for k in n:
		var along := total * (float(k) + 0.5) / float(n)
		var walked := 0.0
		for i in range(1, pts.size()):
			var seg := pts[i - 1].distance_to(pts[i])
			if walked + seg >= along or i == pts.size() - 1:
				var u := 0.0 if seg <= 0.0 else clampf((along - walked) / seg, 0.0, 1.0)
				var at := pts[i - 1].lerp(pts[i], u)
				var normal := normal_of(pts[i - 1], pts[i], flip)
				out.append({"mid": Vector2i(int(round(at.x)), int(round(at.y))),
					"facing_deg": facing_deg(normal), "normal": normal})
				break
			walked += seg
	return out


## The unit normal a front from `a` to `b` faces: `flip` 0 the drawer's right
## in the y-down frame ((-dir.y, dir.x), as WarPlans.facing_flip reads it),
## 1 the left.
static func normal_of(a: Vector2, b: Vector2, flip: int) -> Vector2:
	var dir := (b - a).normalized()
	var right := Vector2(-dir.y, dir.x)
	return right if flip == 0 else -right


## A direction as a whole degree 0..359, 0 along +x and 90 along +y (the
## y-down frame's south).
static func facing_deg(normal: Vector2) -> int:
	return posmod(int(round(rad_to_deg(atan2(normal.y, normal.x)))), 360)
