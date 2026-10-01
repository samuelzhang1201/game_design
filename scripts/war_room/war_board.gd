class_name WarBoard
extends RefCounted
## The Missive board on its easel in the WAR ROOM (spec 2026-10-02-war-room-v2
## §1.3), pure: a ray's hit on the panel as a UV of the board's SubViewport
## (u right, v down), the camera's pose square in front of the panel, and the
## flight between two poses. The panel is a quad centred on `panel.origin`,
## facing its basis' +Z, `size_m` across and high.


static func uv_of(panel: Transform3D, size_m: Vector2, origin: Vector3, dir: Vector3) -> Vector2:
	var n := panel.basis.z.normalized()
	var denom := dir.dot(n)
	if denom >= -0.000001:
		return Vector2(-1, -1)   # parallel, or seen from behind
	var t := (panel.origin - origin).dot(n) / denom
	if t < 0.0:
		return Vector2(-1, -1)
	var local := panel.affine_inverse() * (origin + dir * t)
	var uv := Vector2(local.x / size_m.x + 0.5, 0.5 - local.y / size_m.y)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


static func pose(panel: Transform3D, distance: float, offset: Vector2) -> Transform3D:
	var up := panel.basis.y.normalized()
	var at := panel.origin + panel.basis.x.normalized() * offset.x + up * offset.y
	var eye := at + panel.basis.z.normalized() * distance
	return Transform3D(Basis.looking_at(at - eye, up), eye)


static func fly(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	var k := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var q := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), k)
	return Transform3D(Basis(q), from.origin.lerp(to.origin, k))


static func clamp_offset(offset: Vector2, size_m: Vector2) -> Vector2:
	return Vector2(clampf(offset.x, -size_m.x * 0.5, size_m.x * 0.5),
		clampf(offset.y, -size_m.y * 0.5, size_m.y * 0.5))
