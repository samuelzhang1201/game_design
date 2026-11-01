class_name Map3DCavalryPivotMath
extends RefCounted
## Numerical kernel for Map3DCavalryPivot; its seam validates raw inputs.
## Native affine FK, contact curves and constrained rotations have no I/O.

const EPS: float = 0.00001


static func _finite(value: Variant, depth: int = 0) -> bool:
	# The schema has at most four container edges; cycles are never valid input.
	if depth > 4:
		return false
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR2, TYPE_VECTOR3:
			return value.is_finite()
		TYPE_BASIS:
			return value.x.is_finite() and value.y.is_finite() and value.z.is_finite()
		TYPE_TRANSFORM3D:
			return value.origin.is_finite() and _finite(value.basis, depth)
		TYPE_ARRAY:
			for item: Variant in value:
				if not _finite(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _finite(value[key], depth + 1):
					return false
			return true
		TYPE_INT, TYPE_STRING:
			return true
	return false


static func _affine(value: Variant) -> bool:
	return value is Transform3D and is_finite(value.basis.determinant()) and value.basis.determinant() != 0.0


static func _bone(bones: Array, name: String) -> Dictionary:
	for bone: Dictionary in bones:
		if bone.name == name:
			return bone
	return {}


static func _parent(bones: Array, name: String) -> String:
	return _bone(bones, name).parent


static func _fk(bones: Array, locals: Dictionary) -> Dictionary:
	var globals: Dictionary = {}
	for bone: Dictionary in bones:
		globals[bone.name] = locals[bone.name] if bone.parent == "" else globals[bone.parent] * locals[bone.name]
	return globals


static func _zero(value: Transform3D) -> bool:
	return value.origin == Vector3.ZERO and value.basis.x == Vector3.ZERO and value.basis.y == Vector3.ZERO and value.basis.z == Vector3.ZERO


static func _close(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= EPS and _basis_error(a.basis, b.basis) <= EPS


static func _basis_error(a: Basis, b: Basis) -> float:
	return maxf((a.x - b.x).length(), maxf((a.y - b.y).length(), (a.z - b.z).length()))


static func _add(a: Basis, b: Basis, scale: float = 1.0) -> Basis:
	return Basis(a.x + b.x * scale, a.y + b.y * scale, a.z + b.z * scale)


static func _scaled(a: Basis, scale: float) -> Basis:
	return Basis(a.x * scale, a.y * scale, a.z * scale)


static func _hat(v: Vector3) -> Basis:
	return Basis(Vector3(0, v.z, -v.y), Vector3(-v.z, 0, v.x), Vector3(v.y, -v.x, 0))


static func _polar(a: Basis) -> Dictionary:
	var parity: Basis = Basis.IDENTITY
	if a.determinant() < 0.0:
		parity.x = -parity.x
	var source: Basis = a * parity
	var rotation: Basis = source
	for _i: int in 32:
		if rotation.determinant() == 0.0 or not _finite(rotation):
			return {"ok": false}
		var next: Basis = _scaled(_add(rotation, rotation.inverse().transposed()), 0.5)
		if _basis_error(next, rotation) < 0.0000002:
			rotation = next
			break
		rotation = next
	if not _finite(rotation) or _basis_error(rotation.transposed() * rotation, Basis.IDENTITY) > EPS:
		return {"ok": false}
	return {"ok": true, "rotation": rotation, "stretch": rotation.transposed() * source, "parity": parity}


static func _rotation_vector(rotation: Basis, tie_axis: Vector3) -> Vector3:
	var q: Quaternion = rotation.get_rotation_quaternion().normalized()
	if q.w < 0.0:
		q = -q
	var vector: Vector3 = Vector3(q.x, q.y, q.z)
	var length: float = vector.length()
	if length < 0.0000001:
		return vector * 2.0
	if absf(q.w) < 0.0000001 and vector.dot(tie_axis) < 0.0:
		vector = -vector
	return vector * (2.0 * atan2(length, absf(q.w)) / length)


static func _exp(v: Vector3) -> Basis:
	var angle: float = v.length()
	return Basis.IDENTITY if angle == 0.0 else Basis(v / angle, angle)


static func _left_jacobian_inverse(v: Vector3) -> Basis:
	var angle: float = v.length()
	var skew: Basis = _hat(v)
	var coefficient: float = 1.0 / 12.0
	if angle > 0.0001:
		coefficient = (1.0 - 0.5 * angle / tan(0.5 * angle)) / (angle * angle)
	return _add(_add(Basis.IDENTITY, skew, -0.5), skew * skew, coefficient)


static func _polar_derivative(value: Transform3D, derivative: Transform3D) -> Dictionary:
	var parts: Dictionary = _polar(value.basis)
	if not parts.ok:
		return parts
	var rotation: Basis = parts.rotation
	var stretch: Basis = parts.stretch
	var m: Basis = rotation.transposed() * derivative.basis * parts.parity
	var antisymmetric: Basis = _add(m, m.transposed(), -1.0)
	var trace: float = stretch.x.x + stretch.y.y + stretch.z.z
	var system: Basis = _add(_scaled(Basis.IDENTITY, trace), stretch, -1.0)
	if system.determinant() == 0.0:
		return {"ok": false}
	var angular_local: Vector3 = system.inverse() * Vector3(antisymmetric.y.z, antisymmetric.z.x, antisymmetric.x.y)
	parts["angular"] = rotation * angular_local
	parts["stretch_derivative"] = _add(m, _hat(angular_local) * stretch, -1.0)
	return parts


static func _contact_at(contact: Dictionary, phase: float, tie_axis: Vector3) -> Dictionary:
	for segment: Dictionary in contact.segments:
		if phase < segment.start or phase > segment.end:
			continue
		if phase == segment.start or segment.mode == "stance":
			return {"ok": true, "value": segment.from}
		if phase == segment.end:
			return {"ok": true, "value": segment.to}
		var first: Dictionary = _polar_derivative(segment.from, segment.from_derivative)
		var last: Dictionary = _polar_derivative(segment.to, segment.to_derivative)
		if not first.ok or not last.ok:
			return {"ok": false, "reason": "contact_polar"}
		var dt: float = segment.end - segment.start
		var t: float = (phase - segment.start) / dt
		var h00: float = 2.0 * t * t * t - 3.0 * t * t + 1.0
		var h10: float = t * t * t - 2.0 * t * t + t
		var h01: float = -2.0 * t * t * t + 3.0 * t * t
		var h11: float = t * t * t - t * t
		var end_vector: Vector3 = _rotation_vector(last.rotation * first.rotation.transposed(), tie_axis)
		var end_tangent: Vector3 = _left_jacobian_inverse(end_vector) * last.angular
		var vector: Vector3 = first.angular * dt * h10 + end_vector * h01 + end_tangent * dt * h11
		var stretch: Basis = _add(_add(_add(_scaled(first.stretch, h00), first.stretch_derivative, dt * h10), last.stretch, h01), last.stretch_derivative, dt * h11)
		var basis: Basis = _exp(vector) * first.rotation * stretch * first.parity
		var position: Vector3 = segment.from.origin * h00 + segment.from_derivative.origin * dt * h10 + segment.to.origin * h01 + segment.to_derivative.origin * dt * h11
		var value: Transform3D = Transform3D(basis, position)
		if not _finite(value) or not _affine(value):
			return {"ok": false, "reason": "contact_singular"}
		return {"ok": true, "value": value}
	return {"ok": false, "reason": "contact_partition"}


static func _chain_fk(names: Array, locals: Dictionary, frame: Transform3D = Transform3D.IDENTITY) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	var parent: Transform3D = frame
	for name: String in names:
		parent = parent * locals[name]
		globals.append(parent)
	return globals


static func _limits(rest: Dictionary, chain: Dictionary, locals: Dictionary) -> bool:
	var globals: Array[Transform3D] = _chain_fk(chain.bones, locals)
	for i: int in chain.bones.size():
		var name: String = chain.bones[i]
		var native_rotation: Dictionary = _polar(locals[name].basis)
		var bind_rotation: Dictionary = _polar(_bone(rest.bones, name).bind.basis)
		if not native_rotation.ok or not bind_rotation.ok or _rotation_vector(native_rotation.rotation * bind_rotation.rotation.transposed(), rest.turn_axis).length() > chain.rotation_limits[i] + EPS:
			return false
	for i: int in chain.bend_limits.size():
		var a: Vector3 = globals[i + 1].origin - globals[i].origin
		var b: Vector3 = globals[i + 2].origin - globals[i + 1].origin
		var cross: Vector3 = a.cross(b)
		var angle: float = atan2(cross.length(), a.dot(b))
		if cross.dot(chain.bend_normals[i]) < 0.0:
			angle = -angle
		if angle < chain.bend_limits[i].x - EPS or angle > chain.bend_limits[i].y + EPS:
			return false
	return true


static func _residual(value: Transform3D, target: Transform3D) -> Array[float]:
	var p: Vector3 = value.origin - target.origin
	var x: Vector3 = value.basis.x - target.basis.x
	var y: Vector3 = value.basis.y - target.basis.y
	var z: Vector3 = value.basis.z - target.basis.z
	return [p.x, p.y, p.z, x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z]


static func _norm_squared(values: Array) -> float:
	var out: float = 0.0
	for value: float in values:
		out += value * value
	return out


static func _jacobian(globals: Array[Transform3D], frame: Transform3D, turn: Transform3D, offset: Transform3D) -> Array:
	var rows: Array = []
	for _row: int in 12:
		rows.append([])
	var end: Transform3D = turn * globals[-1] * offset
	for i: int in globals.size():
		var parent: Transform3D = turn * (frame if i == 0 else globals[i - 1])
		if not _finite(parent) or not _affine(parent):
			return []
		var inverse: Basis = parent.basis.inverse()
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var p: Vector3 = parent.basis * axis.cross(inverse * (end.origin - turn * globals[i].origin))
			var x: Vector3 = parent.basis * axis.cross(inverse * end.basis.x)
			var y: Vector3 = parent.basis * axis.cross(inverse * end.basis.y)
			var z: Vector3 = parent.basis * axis.cross(inverse * end.basis.z)
			var column: Array[float] = [p.x, p.y, p.z, x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z]
			for row: int in 12:
				rows[row].append(column[row])
	return rows


static func _linear_solve(matrix: Array, right: Array) -> Array[float]:
	var rows: Array = matrix.duplicate(true)
	var out: Array[float] = []
	for value: float in right:
		out.append(value)
	for i: int in out.size():
		var pivot: int = i
		for j: int in range(i + 1, out.size()):
			if absf(rows[j][i]) > absf(rows[pivot][i]):
				pivot = j
		if rows[pivot][i] == 0.0:
			return []
		var saved: Array = rows[i]
		rows[i] = rows[pivot]
		rows[pivot] = saved
		var saved_value: float = out[i]
		out[i] = out[pivot]
		out[pivot] = saved_value
		var divisor: float = rows[i][i]
		for j: int in range(i, out.size()):
			rows[i][j] /= divisor
		out[i] /= divisor
		for j: int in out.size():
			if j == i:
				continue
			var factor: float = rows[j][i]
			for k: int in range(i, out.size()):
				rows[j][k] -= factor * rows[i][k]
			out[j] -= factor * out[i]
	return out


static func _solve(rest: Dictionary, chain: Dictionary, native: Dictionary, target: Transform3D, frame: Transform3D, turn: Transform3D, offset: Transform3D) -> Dictionary:
	var locals: Dictionary = {}
	var corrections: Dictionary = {}
	for name: String in chain.bones:
		locals[name] = native[name]
		corrections[name] = Quaternion.IDENTITY
	# Match final native FK multiplication order and fixed-ground contact units.
	var globals: Array[Transform3D] = _chain_fk(chain.bones, locals, frame)
	if not _limits(rest, chain, locals):
		return {"ok": false, "reason": "native_joint_limits", "iterations": 0}
	var damping: float = 0.00001
	var attempts: int = 0
	for iteration: int in 96:
		var observed: Transform3D = turn * globals[-1] * offset
		if not _finite(observed) or not _affine(observed):
			return {"ok": false, "reason": "contact_affine", "iterations": attempts}
		if _close(observed, target):
			return {"ok": true, "locals": locals, "iterations": iteration}
		attempts = iteration + 1
		var residual: Array[float] = _residual(observed, target)
		var score: float = _norm_squared(residual)
		var jacobian: Array = _jacobian(globals, frame, turn, offset)
		if jacobian.is_empty():
			return {"ok": false, "reason": "singular_joint_frame", "iterations": attempts}
		var system: Array = []
		for i: int in 12:
			var row: Array[float] = []
			for j: int in 12:
				var value: float = damping if i == j else 0.0
				for k: int in jacobian[i].size():
					value += jacobian[i][k] * jacobian[j][k]
				row.append(value)
			system.append(row)
		var dual: Array[float] = _linear_solve(system, residual)
		if dual.is_empty():
			return {"ok": false, "reason": "numerical_system", "iterations": iteration}
		var steps: Array[Vector3] = []
		var largest: float = 0.0
		for i: int in chain.bones.size():
			var vector: Vector3 = Vector3.ZERO
			for axis: int in 3:
				for row: int in 12:
					vector[axis] -= jacobian[row][3 * i + axis] * dual[row]
			steps.append(vector)
			largest = maxf(largest, vector.length())
		var fraction: float = minf(1.0, 0.35 / largest) if largest > 0.0 else 1.0
		var accepted: bool = false
		for _line: int in 12:
			var candidate: Dictionary = locals.duplicate(true)
			var candidate_corrections: Dictionary = corrections.duplicate(true)
			for i: int in chain.bones.size():
				var name: String = chain.bones[i]
				var step: Quaternion = _exp(steps[i] * fraction).get_rotation_quaternion()
				candidate_corrections[name] = (step * corrections[name]).normalized()
				var local: Transform3D = candidate[name]
				local.basis = Basis(candidate_corrections[name]) * native[name].basis
				candidate[name] = local
			var proposed: Array[Transform3D] = _chain_fk(chain.bones, candidate, frame)
			var proposed_contact: Transform3D = turn * proposed[-1] * offset
			if _finite(proposed) and _finite(proposed_contact) and _affine(proposed_contact) and _norm_squared(_residual(proposed_contact, target)) < score and _limits(rest, chain, candidate):
				locals = candidate
				corrections = candidate_corrections
				globals = proposed
				accepted = true
				break
			fraction *= 0.5
		if accepted:
			damping = maxf(0.0000001, damping * 0.5)
		else:
			damping *= 10.0
			if damping > 1000.0:
				break
	# Nonconvergence is not a proof of impossibility and must stay RED when a
	# feasible mandatory case reaches this diagnostic; no relaxed-pose fallback.
	return {"ok": false, "reason": "constraints_not_solved", "iterations": attempts}
