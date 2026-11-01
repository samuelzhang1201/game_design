class_name Map3DArcherPivot
extends RefCounted
## Pure, transient contact solve for the installed archer's flattened split legs.
## All poses are COMPLETE parent-relative native transforms, not Skeleton pose deltas.
## rest = {locals, parents ("" = skeleton space), legs:{l,r:{knee_limits:Vector2,
##   rotation_limits:{part:float}, sole_in_foot:Transform3D, toe_in_toes:Transform3D}}}.
## Joint origins: thigh_twist = hip, leg_stretch = knee, foot = ankle.
## Anatomical spans come from rest joint origins, NEVER export bone.length (0.05m).
## operation = {yaw_rad,turn_rad,duration_s,phase,march_entry_phase,march_exit_phase,
##   entry_pose,exit_pose}; numeric scalars are finite floats. Positive pack turn
## means RIGHT, decreasing native world yaw; yaw = yaw_rad - phase * turn_rad.
## contacts = {l,r:{track:[{phase,sole,toe,knee_frame}],
##   support:[{start,end,sole,toe}]}}. Targets/anchors are explicit world frames;
## knee_frame is rigid world Basis, x supplies the projected knee bend direction.
## Track spans [0,1], increasing knots; full frames define the half-turn branch.
## Toe interpolation is relative to sole, retaining a rigid foot/toe offset.
## Support anchors must agree across their entire piecewise interpolated interval.
## knee_limits bound anatomical flexion; rotation_limits bound each local bone's
## geodesic rotation from its native rest. Limits are inputs, not installed policy.
## Returns {ok,locals,diagnostics}; any failure returns NO partial pose.
## This does not plan contacts, sample a clip, or certify a parameter domain.
## Raw MARCH interpolation with inconsistent anatomical spans is explicitly invalid;
## unchanged raw endpoints and exact rest spans cannot both be promised for it.

const PARTS: Array[String] = ["thigh_twist", "thigh_stretch", "leg_stretch", "leg_twist", "foot", "toes_01"]
# Arithmetic tolerance only; this is not a contact-policy or certificate threshold.
const EPS: float = 0.00001


static func sample(rest: Variant, authored_pose: Variant, operation: Variant, contacts: Variant) -> Dictionary:
	if not _dict(rest) or not _dict(authored_pose) or not _dict(operation) or not _dict(contacts):
		return _fail("malformed: expected dictionaries")
	if not _dict(rest.get("locals")) or not _dict(rest.get("parents")) or not _dict(rest.get("legs")):
		return _fail("rest: missing locals, parents or legs")
	var reference: Dictionary = _globals(rest.locals, rest.parents)
	var source: Dictionary = _globals(authored_pose, rest.parents)
	if reference.is_empty() or source.is_empty():
		return _fail("pose: malformed transforms, missing parent or parent cycle")
	if not _topology(rest.parents) or not _legs(rest.legs):
		return _fail("rest: invalid flattened topology or joint/contact definitions")
	if not _geometry(reference, reference) or not _geometry(source, reference):
		return _fail("pose: inconsistent anatomical/split spans; raw interpolated MARCH requires a separate transition solution")
	for field: String in ["yaw_rad", "turn_rad", "duration_s", "phase", "march_entry_phase", "march_exit_phase"]:
		if not _float(operation.get(field)):
			return _fail("operation: invalid " + field)
	if operation.duration_s <= 0.0 or absf(operation.turn_rad) > PI or not _unit(operation.phase):
		return _fail("operation: duration, turn or phase outside domain")
	for field: String in ["march_entry_phase", "march_exit_phase"]:
		if operation[field] < 0.0 or operation[field] >= 1.0:
			return _fail("operation: invalid MARCH phase")
	if not _dict(operation.get("entry_pose")) or not _dict(operation.get("exit_pose")):
		return _fail("transition: explicit MARCH endpoints required")
	var endpoints: Array[Dictionary] = []
	for field: String in ["entry_pose", "exit_pose"]:
		var global: Dictionary = _globals(operation[field], rest.parents)
		if global.is_empty() or not _geometry(global, reference):
			return _fail("transition: inconsistent MARCH endpoint geometry")
		endpoints.append(global)
	if not _contacts(contacts):
		return _fail("contact: malformed track, support interval or moving anchor")
	# Validate complete endpoint poses, not just foot positions: a changed knee can pop too.
	for i: int in range(2):
		var expected: Dictionary = operation.entry_pose if i == 0 else operation.exit_pose
		var endpoint: Dictionary = _solve(rest, reference, endpoints[i], expected, operation, contacts, float(i))
		if not endpoint.ok:
			return _fail("transition: " + str(endpoint.diagnostics[0]))
		for name: String in expected:
			if not _same(endpoint.locals[name], expected[name]):
				return _fail("transition: endpoint would change " + name)
	return _solve(rest, reference, source, authored_pose, operation, contacts, operation.phase)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "locals": {}, "diagnostics": [reason]}


static func _dict(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY


static func _float(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT and is_finite(value)


static func _unit(value: float) -> bool:
	return value >= 0.0 and value <= 1.0


static func _transform(value: Variant) -> bool:
	if typeof(value) != TYPE_TRANSFORM3D:
		return false
	var t: Transform3D = value
	if not t.is_finite() or not is_finite(t.basis.determinant()) or t.basis.determinant() <= EPS * EPS:
		return false
	for axis: Vector3 in [t.basis.x, t.basis.y, t.basis.z]:
		if not is_finite(axis.length_squared()) or axis.length_squared() <= 0.0:
			return false
	var rotation: Basis = t.basis.orthonormalized()
	return rotation.is_finite() and absf(rotation.determinant() - 1.0) <= EPS and t.affine_inverse().is_finite()


static func _rigid(value: Variant) -> bool:
	if typeof(value) != TYPE_BASIS:
		return false
	var b: Basis = value
	return b.is_finite() and absf(b.determinant() - 1.0) <= EPS and b.is_equal_approx(b.orthonormalized())


static func _same(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= EPS and a.basis.x.distance_to(b.basis.x) <= EPS and a.basis.y.distance_to(b.basis.y) <= EPS and a.basis.z.distance_to(b.basis.z) <= EPS


static func _globals(locals: Dictionary, parents: Dictionary) -> Dictionary:
	if locals.is_empty() or locals.size() != parents.size():
		return {}
	for name: Variant in locals:
		if typeof(name) != TYPE_STRING or not parents.has(name) or typeof(parents[name]) != TYPE_STRING or not _transform(locals[name]):
			return {}
		var parent: String = parents[name]
		if not parent.is_empty() and not locals.has(parent):
			return {}
	var pending: Array = locals.keys()
	var out: Dictionary = {}
	while not pending.is_empty():
		var changed: bool = false
		for name: String in pending.duplicate():
			var parent: String = parents[name]
			if parent.is_empty() or out.has(parent):
				var t: Transform3D = locals[name] if parent.is_empty() else out[parent] * locals[name]
				if not _transform(t):
					return {}
				out[name] = t
				pending.erase(name)
				changed = true
		if not changed:
			return {}
	return out


static func _topology(parents: Dictionary) -> bool:
	if parents.get("root.x") != "":
		return false
	for side: String in ["l", "r"]:
		var required: Array[String] = ["root.x", "", "", "leg_stretch." + side, "root.x", "foot." + side]
		for i: int in range(PARTS.size()):
			if parents.get(PARTS[i] + "." + side) != required[i]:
				return false
	return true


static func _legs(legs: Dictionary) -> bool:
	for side: String in ["l", "r"]:
		if not _dict(legs.get(side)):
			return false
		var leg: Dictionary = legs[side]
		if typeof(leg.get("knee_limits")) != TYPE_VECTOR2 or not _dict(leg.get("rotation_limits")):
			return false
		var limits: Vector2 = leg.knee_limits
		# Vector2 stores the upper endpoint at float32 precision.
		if not limits.is_finite() or limits.x < 0.0 or limits.y > Vector2(0, PI).y or limits.x > limits.y:
			return false
		for part: String in PARTS:
			var limit: Variant = leg.rotation_limits.get(part)
			if not _float(limit) or limit < 0.0 or limit > PI:
				return false
		if not _transform(leg.get("sole_in_foot")) or not _transform(leg.get("toe_in_toes")):
			return false
	return true


static func _geometry(pose: Dictionary, rest: Dictionary) -> bool:
	for side: String in ["l", "r"]:
		for pair: Array in [["thigh_twist", "leg_stretch"], ["leg_stretch", "foot"], ["foot", "toes_01"], ["thigh_twist", "thigh_stretch"], ["leg_stretch", "leg_twist"]]:
			var a: String = pair[0] + "." + side
			var b: String = pair[1] + "." + side
			var expected: float = rest[a].origin.distance_to(rest[b].origin)
			var observed: float = pose[a].origin.distance_to(pose[b].origin)
			if not is_finite(expected) or not is_finite(observed) or expected <= EPS or absf(observed - expected) > EPS:
				return false
	return true


static func _contacts(contacts: Dictionary) -> bool:
	for side: String in ["l", "r"]:
		if not _dict(contacts.get(side)):
			return false
		var c: Dictionary = contacts[side]
		if typeof(c.get("track")) != TYPE_ARRAY or typeof(c.get("support")) != TYPE_ARRAY or c.track.size() < 2:
			return false
		var previous: float = -1.0
		for knot: Variant in c.track:
			if not _dict(knot) or not _float(knot.get("phase")):
				return false
			if not _unit(knot.phase) or knot.phase <= previous or not _transform(knot.get("sole")) or not _transform(knot.get("toe")) or not _rigid(knot.get("knee_frame")):
				return false
			previous = knot.phase
		if c.track[0].phase != 0.0 or c.track[-1].phase != 1.0:
			return false
		previous = 0.0
		for interval: Variant in c.support:
			if not _dict(interval) or not _float(interval.get("start")) or not _float(interval.get("end")):
				return false
			if not _unit(interval.start) or not _unit(interval.end) or interval.start >= interval.end or interval.start < previous:
				return false
			if not _transform(interval.get("sole")) or not _transform(interval.get("toe")):
				return false
			var phases: Array[float] = [interval.start, interval.end]
			for knot: Dictionary in c.track:
				if knot.phase > interval.start and knot.phase < interval.end:
					phases.append(knot.phase)
			for phase: float in phases:
				var target: Dictionary = _target(c.track, phase)
				if target.is_empty() or not _same(target.sole, interval.sole) or not _same(target.toe, interval.toe):
					return false
			previous = interval.end
	return true


static func _mix(a: Transform3D, b: Transform3D, share: float) -> Transform3D:
	if share == 0.0:
		return a
	if share == 1.0:
		return b
	# Retain native affine residuals instead of silently removing scale/shear.
	var ra: Basis = a.basis.orthonormalized()
	var rb: Basis = b.basis.orthonormalized()
	var aa: Basis = ra.inverse() * a.basis
	var ab: Basis = rb.inverse() * b.basis
	var affine := Basis(aa.x.lerp(ab.x, share), aa.y.lerp(ab.y, share), aa.z.lerp(ab.z, share))
	var rotation := Basis(ra.get_rotation_quaternion().slerp(rb.get_rotation_quaternion(), share))
	return Transform3D(rotation * affine, a.origin.lerp(b.origin, share))


static func _target(track: Array, phase: float) -> Dictionary:
	for i: int in range(1, track.size()):
		var a: Dictionary = track[i - 1]
		var b: Dictionary = track[i]
		if phase <= b.phase:
			var share: float = (phase - a.phase) / (b.phase - a.phase)
			var sole: Transform3D = _mix(a.sole, b.sole, share)
			var relative_a: Transform3D = a.sole.affine_inverse() * a.toe
			var relative_b: Transform3D = b.sole.affine_inverse() * b.toe
			if not _transform(sole) or not _transform(relative_a) or not _transform(relative_b):
				return {}
			var relative: Transform3D = _mix(relative_a, relative_b, share)
			if not _transform(sole * relative):
				return {}
			var frame: Basis = Basis(a.knee_frame.get_rotation_quaternion().slerp(b.knee_frame.get_rotation_quaternion(), share))
			return {"sole": sole, "toe": sole * relative, "knee_frame": frame}
	return {}


static func _frame(direction: Vector3, normal: Vector3) -> Basis:
	var y: Vector3 = direction.normalized()
	var x: Vector3 = (normal - y * normal.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


static func _solve(rest: Dictionary, reference: Dictionary, source: Dictionary, authored: Dictionary, operation: Dictionary, contacts: Dictionary, phase: float) -> Dictionary:
	var solved: Dictionary = source.duplicate(true)
	var yaw: float = operation.yaw_rad - operation.turn_rad * phase
	if not is_finite(yaw):
		return _fail("operation: nonfinite derived yaw")
	var inverse_yaw := Transform3D(Basis(Vector3.UP, -yaw), Vector3.ZERO)
	for side: String in ["l", "r"]:
		var leg: Dictionary = rest.legs[side]
		var target: Dictionary = _target(contacts[side].track, phase)
		if target.is_empty():
			return _fail("contact: invalid interpolated frame")
		var foot: Transform3D = inverse_yaw * target.sole * leg.sole_in_foot.affine_inverse()
		var toe: Transform3D = inverse_yaw * target.toe * leg.toe_in_toes.affine_inverse()
		if not _transform(foot) or not _transform(toe):
			return _fail("contact: nonfinite or degenerate derived frame")
		var hip: Vector3 = source["thigh_twist." + side].origin
		var old_knee: Vector3 = source["leg_stretch." + side].origin
		var old_ankle: Vector3 = source["foot." + side].origin
		var upper: float = reference["thigh_twist." + side].origin.distance_to(reference["leg_stretch." + side].origin)
		var lower: float = reference["leg_stretch." + side].origin.distance_to(reference["foot." + side].origin)
		var delta: Vector3 = foot.origin - hip
		var distance: float = delta.length()
		if not is_finite(distance) or distance <= EPS or distance > upper + lower or distance < absf(upper - lower):
			return _fail("unreachable: " + side)
		var axis: Vector3 = delta / distance
		var hint: Vector3 = inverse_yaw.basis * (target.knee_frame as Basis).x
		var bend: Vector3 = hint - axis * hint.dot(axis)
		if bend.length() <= EPS:
			return _fail("knee_plane: reference parallel to hip-ankle axis " + side)
		bend = bend.normalized()
		var along: float = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
		var height_squared: float = upper * upper - along * along
		if height_squared < -EPS * EPS:
			return _fail("unreachable: triangle " + side)
		var knee: Vector3 = hip + axis * along + bend * sqrt(maxf(0.0, height_squared))
		var flexion: float = (knee - hip).angle_to(foot.origin - knee)
		if flexion < leg.knee_limits.x - EPS or flexion > leg.knee_limits.y + EPS:
			return _fail("joint_limit: anatomical knee " + side)
		var old_normal: Vector3 = (old_knee - hip).cross(old_ankle - old_knee)
		if old_normal.length() <= EPS * EPS:
			old_normal = (reference["leg_stretch." + side].origin - reference["thigh_twist." + side].origin).cross(reference["foot." + side].origin - reference["leg_stretch." + side].origin)
		if not old_normal.is_finite() or not is_finite(old_normal.length_squared()):
			return _fail("knee_plane: nonfinite derived normal " + side)
		if old_normal.length() <= EPS * EPS or old_normal.cross(old_knee - hip).length() <= EPS * EPS:
			return _fail("knee_plane: undefined authored/rest bend plane " + side)
		var normal: Vector3 = bend.cross(axis).normalized()
		# A shared full plane fixes twist even when an individual segment reverses.
		var upper_rotation: Basis = _frame(knee - hip, normal) * _frame(old_knee - hip, old_normal).inverse()
		var lower_rotation: Basis = _frame(foot.origin - knee, normal) * _frame(old_ankle - old_knee, old_normal).inverse()
		for part: String in ["thigh_twist", "thigh_stretch"]:
			var old: Transform3D = source[part + "." + side]
			solved[part + "." + side] = Transform3D(upper_rotation * old.basis, hip + upper_rotation * (old.origin - hip))
		for part: String in ["leg_stretch", "leg_twist"]:
			var old: Transform3D = source[part + "." + side]
			solved[part + "." + side] = Transform3D(lower_rotation * old.basis, knee + lower_rotation * (old.origin - old_knee))
		solved["foot." + side] = foot
		solved["toes_01." + side] = toe
	if not _geometry(solved, reference):
		return _fail("contact: incompatible foot/toe or split geometry")
	var locals: Dictionary = authored.duplicate(true)
	for name: String in source:
		var parent: String = rest.parents[name]
		var modified: bool = name.get_slice(".", 0) in PARTS
		if modified:
			locals[name] = solved[name] if parent.is_empty() else solved[parent].affine_inverse() * solved[name]
		if not _transform(locals[name]):
			return _fail("pose: invalid reconstructed local " + name)
		if modified:
			var side: String = name.get_slice(".", 1)
			var part: String = name.get_slice(".", 0)
			var a: Quaternion = (rest.locals[name] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
			var b: Quaternion = (locals[name] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
			if a.angle_to(b) > rest.legs[side].rotation_limits[part] + EPS:
				return _fail("joint_limit: local rotation " + name)
	return {"ok": true, "locals": locals, "diagnostics": []}
