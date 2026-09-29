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
	var back := Vector3(0, 0, 1).rotated(Vector3.RIGHT, deg_to_rad(pitch)).rotated(Vector3.UP, deg_to_rad(yaw))
	var eye := target + back * distance
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


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
