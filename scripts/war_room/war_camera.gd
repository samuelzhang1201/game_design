class_name WarCamera
extends RefCounted
## The standing officer's view over the plotting table (spec
## 2026-10-01-war-room-design §1): an orbit about a point on the table, from
## the south (the sheet's foot) by default, its turn held within yaw_max so the
## room is built only where it is seen; the wheel leans in about the pointer.

var target := Vector3.ZERO
var distance := 1.6
var pitch_deg := 52.0
var yaw_deg := 0.0
var min_distance := 0.12
var max_distance := 2.4
var yaw_max := 30.0
var bounds := Rect2(-0.7, -0.5, 1.4, 1.0)


func transform() -> Transform3D:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * distance
	var origin := target + back
	return Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)


## Lean toward (factor < 1) or back from `ground`: the distance scales and the
## target walks the same share toward the point, so the point holds its bearing.
func zoom_about(ground: Vector3, factor: float) -> void:
	var d := clampf(distance * factor, min_distance, max_distance)
	var share := 1.0 - d / distance
	target = target.lerp(Vector3(ground.x, target.y, ground.z), share)
	distance = d
	_clamp()


func pan(delta_xz: Vector2) -> void:
	target += Vector3(delta_xz.x, 0.0, delta_xz.y)
	_clamp()


func turn(delta_deg: float) -> void:
	yaw_deg = clampf(yaw_deg + delta_deg, -yaw_max, yaw_max)


func _clamp() -> void:
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
