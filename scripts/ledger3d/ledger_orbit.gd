# scripts/ledger3d/ledger_orbit.gd
class_name LedgerOrbit
extends RefCounted
## The LEDGER's camera as numbers (spec 2026-09-30 §6.2): it orbits a target
## at a distance, a yaw and a pitch. Turning, panning and zooming change only
## these; the view turns them into the Camera3D's transform.

var target := Vector3.ZERO
var distance := 30.0
var yaw := 0.0      # degrees, 0 looks along -Z
var pitch := -24.0  # degrees, negative looks down from above
var min_distance := 8.0
var max_distance := 90.0


func pose() -> Transform3D:
	var b := _basis(yaw, pitch)
	return Transform3D(b, target + b.z * distance)


func turn(dx_px: float, dy_px: float, deg_per_px: float) -> void:
	yaw -= dx_px * deg_per_px
	pitch = clampf(pitch - dy_px * deg_per_px, -85.0, -5.0)


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)


func pan(screen_delta: Vector2, m_per_px: float) -> void:
	var b := pose().basis
	target += (-b.x * screen_delta.x + b.y * screen_delta.y) * m_per_px


func metres_per_px(fov_deg: float, view_h_px: float) -> float:
	return 2.0 * distance * tan(deg_to_rad(fov_deg) * 0.5) / maxf(view_h_px, 1.0)


## Where a point lands on the screen, in normalised device coordinates
## (-1..1, +y up), seen from the orbit pose (target, distance, yaw, pitch)
## through a camera of vertical fov_deg at this aspect. A point at or behind
## the eye lands at INF.
static func ndc_of(p: Vector3, target: Vector3, distance: float, yaw_deg: float, pitch_deg: float,
		fov_deg: float, aspect: float) -> Vector2:
	var b := _basis(yaw_deg, pitch_deg)
	var v := p - target
	var depth := distance - v.dot(b.z)
	if depth <= 1e-6:
		return Vector2(INF, INF)
	var tv := tan(deg_to_rad(fov_deg) * 0.5)
	return Vector2(v.dot(b.x) / (depth * tv * aspect), v.dot(b.y) / (depth * tv))


## The target and distance that frame `points` (Task 10): seen at this yaw
## and pitch, every point lands inside `safe` — the part of the view, in
## 0..1 of its width and height from its top left, that the screen's own
## chrome leaves clear — and the content is as large as it can be there. A
## pure function of the points: {} when there are none. The caller clamps
## the distance like a zoom.
static func frame(points: Array, yaw_deg: float, pitch_deg: float, fov_deg: float, aspect: float,
		safe: Rect2) -> Dictionary:
	if points.is_empty():
		return {}
	var box := AABB(points[0], Vector3.ZERO)
	for p: Vector3 in points:
		box = box.expand(p)
	var target := box.get_center()
	var b := _basis(yaw_deg, pitch_deg)
	var tv := tan(deg_to_rad(fov_deg) * 0.5)
	var lo := Vector2(safe.position.x * 2.0 - 1.0, 1.0 - safe.end.y * 2.0)
	var hi := Vector2(safe.end.x * 2.0 - 1.0, 1.0 - safe.position.y * 2.0)
	var distance := 1.0
	# Fit, then slide the target so the content's middle meets the safe
	# rect's middle, and fit again: perspective makes the slide approximate,
	# so a few rounds, and the last word is a fit.
	for _round in 4:
		distance = _fit_distance(points, target, yaw_deg, pitch_deg, fov_deg, aspect, lo, hi)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p: Vector3 in points:
			var s := ndc_of(p, target, distance, yaw_deg, pitch_deg, fov_deg, aspect)
			mn = mn.min(s)
			mx = mx.max(s)
		var off := (mn + mx) * 0.5 - (lo + hi) * 0.5
		target += b.x * off.x * distance * tv * aspect + b.y * off.y * distance * tv
	distance = _fit_distance(points, target, yaw_deg, pitch_deg, fov_deg, aspect, lo, hi)
	return {"target": target, "distance": distance}


static func _basis(yaw_deg: float, pitch_deg: float) -> Basis:
	var back := Vector3(0, 0, 1).rotated(Vector3.RIGHT, deg_to_rad(pitch_deg)).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	return Basis.looking_at(-back, Vector3.UP)


static func _fits(points: Array, target: Vector3, distance: float, yaw_deg: float, pitch_deg: float,
		fov_deg: float, aspect: float, lo: Vector2, hi: Vector2) -> bool:
	for p: Vector3 in points:
		var s := ndc_of(p, target, distance, yaw_deg, pitch_deg, fov_deg, aspect)
		if s.x < lo.x or s.x > hi.x or s.y < lo.y or s.y > hi.y:
			return false
	return true


## The least distance at which every point fits, the target held. A point
## only draws toward the screen's middle as the eye backs away, so each
## point and each edge of the safe rect give a least distance in closed form
## — ndc.x = v·x / ((D − v·z)·tan·aspect) reaches the edge `e` (on the side
## the point lies) at D = v·z + v·x / (e·tan·aspect) — and the fit is their
## greatest: one pass over the points, called on every frame a framed chart
## settles. When the safe rect does not straddle the screen's middle the
## closed form does not hold and a bisection finds it.
static func _fit_distance(points: Array, target: Vector3, yaw_deg: float, pitch_deg: float,
		fov_deg: float, aspect: float, lo: Vector2, hi: Vector2) -> float:
	if lo.x < 0.0 and hi.x > 0.0 and lo.y < 0.0 and hi.y > 0.0:
		var b := _basis(yaw_deg, pitch_deg)
		var tv := tan(deg_to_rad(fov_deg) * 0.5)
		var need := 0.0
		for p: Vector3 in points:
			var v := p - target
			var vx := v.dot(b.x)
			var vy := v.dot(b.y)
			var vz := v.dot(b.z)
			var d := vz + 1e-6  # the eye stays in front of every point
			d = maxf(d, vz + vx / ((hi.x if vx > 0.0 else lo.x) * tv * aspect))
			d = maxf(d, vz + vy / ((hi.y if vy > 0.0 else lo.y) * tv))
			need = maxf(need, d)
		return need
	var near := 0.0
	var far := 1.0
	while not _fits(points, target, far, yaw_deg, pitch_deg, fov_deg, aspect, lo, hi) and far < 1e6:
		near = far
		far *= 2.0
	for _i in 40:
		var mid := (near + far) * 0.5
		if _fits(points, target, mid, yaw_deg, pitch_deg, fov_deg, aspect, lo, hi):
			far = mid
		else:
			near = mid
	return far
