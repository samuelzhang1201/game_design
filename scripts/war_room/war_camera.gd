class_name WarCamera
extends RefCounted
## The officer's view over the plotting table (spec 2026-10-02-war-room-v2
## §1.1, after the 3D map): an orbit about a point on the table that turns all
## the way round, its pitch following the distance — oblique close in,
## overhead stepped back (Map3DGeometry.pitch_for's log scale) — and kept
## inside the room's walls. The compass eases it back to the sheet's foot.

var target := Vector3.ZERO
var distance := 1.6
var yaw_deg := 0.0
var min_distance := 0.12
var max_distance := 2.4
var pitch_near_deg := 30.0
var pitch_far_deg := 55.0
var bounds := Rect2(-0.7, -0.5, 1.4, 1.0)
## The floor the camera may stand over (x, z), the walls less their clearance;
## an empty rect keeps no walls.
var room := Rect2()
var _north_from := 0.0
var _north_t := -1.0


func pitch_deg() -> float:
	return _pitch_at(distance)


func _pitch_at(d: float) -> float:
	return Map3DGeometry.pitch_for(d, min_distance, max_distance, pitch_near_deg, pitch_far_deg)


func _back(d: float) -> Vector3:
	var p := deg_to_rad(_pitch_at(d))
	var y := deg_to_rad(yaw_deg)
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * d


func transform() -> Transform3D:
	var origin := target + _back(clear_distance())
	return Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)


## The distance actually drawn: `distance`, shortened until the camera stands
## over `room` (a bisection: the pitch moves with the distance).
func clear_distance() -> float:
	if room.size == Vector2.ZERO or _inside(distance):
		return distance
	var lo := min_distance
	var hi := distance
	for i in 24:
		var mid := (lo + hi) * 0.5
		if _inside(mid):
			lo = mid
		else:
			hi = mid
	return lo


func _inside(d: float) -> bool:
	var o := target + _back(d)
	return o.x >= room.position.x and o.x <= room.end.x and o.z >= room.position.y and o.z <= room.end.y


## Lean toward (factor < 1) or back from `ground`: the distance scales and the
## target walks the same share toward the point, so the point holds its bearing.
func zoom_about(ground: Vector3, factor: float) -> void:
	var d := clampf(distance * factor, min_distance, max_distance)
	var share := 1.0 - d / distance
	target = target.lerp(Vector3(ground.x, target.y, ground.z), share)
	distance = d
	_clamp()


## Move the target by a table-plane delta (world x, z).
func pan(delta_xz: Vector2) -> void:
	target += Vector3(delta_xz.x, 0.0, delta_xz.y)
	_clamp()


## Move the target by a delta in SCREEN directions (x right, y down), turned
## by the yaw, so a drag follows the pointer however the room is turned.
func pan_view(delta: Vector2) -> void:
	var y := deg_to_rad(yaw_deg)
	pan(Vector2(cos(y), -sin(y)) * delta.x + Vector2(sin(y), cos(y)) * delta.y)


func turn(delta_deg: float) -> void:
	_north_t = -1.0
	yaw_deg = wrapf(yaw_deg + delta_deg, -180.0, 180.0)


func start_north() -> void:
	_north_from = yaw_deg
	_north_t = 0.0


func easing() -> bool:
	return _north_t >= 0.0


## One frame of the ease back to yaw 0 over `seconds`; true when it moved.
func step(delta: float, seconds: float) -> bool:
	if _north_t < 0.0:
		return false
	_north_t += delta / maxf(seconds, 0.01)
	yaw_deg = Map3DGeometry.ease_yaw(_north_from, _north_t)
	if _north_t >= 1.0:
		_north_t = -1.0
		yaw_deg = 0.0
	return true


func _clamp() -> void:
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
