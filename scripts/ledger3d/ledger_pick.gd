# scripts/ledger3d/ledger_pick.gd
class_name LedgerPick
extends RefCounted
## Picking in the LEDGER without physics (the map's practice since
## Terrain3D's collision was turned off): a ray against spheres, and the
## closest approach of a ray to a segment (the view picks a link by its
## screen distance, nearest first, once no star is under the pointer).


## The nearest t >= 0 at which a ray (d normalised) meets a sphere, or -1.
static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var disc := b * b - (oc.dot(oc) - r * r)
	if disc < 0.0:
		return -1.0
	var s := sqrt(disc)
	var t := -b - s
	if t < 0.0:
		t = -b + s
	return t if t >= 0.0 else -1.0


## The closest approach of a ray to a segment: Vector2(distance, t along the
## ray). A zero-length segment is a point.
static func ray_segment(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Vector2:
	var u := b - a
	var c := u.dot(u)
	var w := o - a
	var dd := d.dot(w)
	if c < 1e-9:
		var t0 := maxf((a - o).dot(d), 0.0)
		return Vector2((o + d * t0).distance_to(a), t0)
	var bb := d.dot(u)
	var e := u.dot(w)
	var denom := c - bb * bb
	var tu := clampf(e / c if denom < 1e-9 else (e - bb * dd) / denom, 0.0, 1.0)
	var s := maxf(bb * tu - dd, 0.0)
	return Vector2((o + d * s).distance_to(a + u * tu), s)


## The sphere a ray meets first ({"kind": "sphere", "id": ...}), or {}.
static func pick(o: Vector3, d: Vector3, spheres: Array) -> Dictionary:
	# Visible surfaces have priority over invisible accessibility padding.
	for field: String in ["draw_radius", "radius"]:
		var best := INF
		var hit := {}
		for sp: Dictionary in spheres:
			var radius := float(sp.get(field, sp["radius"]))
			var t := ray_sphere(o, d, sp["pos"], radius)
			if t >= 0.0 and t < best:
				best = t
				hit = {"kind": "sphere", "id": String(sp["id"])}
		if not hit.is_empty():
			return hit
	return {}


## A pointer position in the control's design px, in the SubViewport's px
## (the view renders at window resolution).
static func screen_to_viewport(pos: Vector2, scale: float) -> Vector2:
	return pos * scale
