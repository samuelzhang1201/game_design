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
## Raw leg matrices are pose/twist references; rest anatomy fixes lengths and split
## placement. Zero-turn sample is the same canonical MARCH pose source used at
## pivot endpoints. Direct raw clip playback to corrected pivot is not continuous.

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
	if not _geometry(reference, reference):
		return _fail("rest: invalid anatomical spans or split placement")
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
		if global.is_empty():
			return _fail("transition: malformed raw MARCH endpoint")
		endpoints.append(global)
	if not _contacts(contacts):
		return _fail("contact: malformed track, support interval or moving anchor")
	# Raw foot/toe frames remain authoritative; legs share the canonical physical solve.
	for i: int in range(2):
		var expected: Dictionary = operation.entry_pose if i == 0 else operation.exit_pose
		var world := Transform3D(Basis(Vector3.UP, operation.yaw_rad - operation.turn_rad * i), Vector3.ZERO)
		for side: String in ["l", "r"]:
			var target: Dictionary = _target(contacts[side].track, float(i))
			if target.is_empty() or not _same(target.sole, world * endpoints[i]["foot." + side] * rest.legs[side].sole_in_foot) or not _same(target.toe, world * endpoints[i]["toes_01." + side] * rest.legs[side].toe_in_toes):
				return _fail("transition: raw MARCH foot/toe frame disagrees with contact endpoint")
		var endpoint: Dictionary = _solve(rest, reference, endpoints[i], expected, operation, contacts, float(i))
		if not endpoint.ok:
			return _fail("transition: " + str(endpoint.diagnostics[0]))
		if operation.phase == float(i):
			for name: String in expected:
				if not _same(authored_pose[name], expected[name]):
					return _fail("transition: sampled raw reference disagrees with MARCH endpoint " + name)

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


static func _same_affine(a: Basis, b: Basis) -> bool:
	# The Gram matrix retains scale/shear while ignoring an allowed rigid rotation.
	return _same(Transform3D(a.transposed() * a, Vector3.ZERO), Transform3D(b.transposed() * b, Vector3.ZERO))


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
		for pair: Array in [["thigh_twist", "leg_stretch"], ["leg_stretch", "foot"], ["foot", "toes_01"]]:
			var a: String = pair[0] + "." + side
			var b: String = pair[1] + "." + side
			var expected: float = rest[a].origin.distance_to(rest[b].origin)
			var observed: float = pose[a].origin.distance_to(pose[b].origin)
			if not is_finite(expected) or not is_finite(observed) or expected <= EPS or absf(observed - expected) > EPS:
				return false
		for triple: Array in [["thigh_twist", "thigh_stretch", "leg_stretch"], ["leg_stretch", "leg_twist", "foot"]]:
			var a: String = triple[0] + "." + side
			var split: String = triple[1] + "." + side
			var b: String = triple[2] + "." + side
			var segment: Vector3 = rest[b].origin - rest[a].origin
			var fraction: float = (rest[split].origin - rest[a].origin).dot(segment) / segment.length_squared()
			if not is_finite(fraction) or fraction <= 0.0 or fraction >= 1.0 or rest[split].origin.distance_to(rest[a].origin.lerp(rest[b].origin, fraction)) > EPS or pose[split].origin.distance_to(pose[a].origin.lerp(pose[b].origin, fraction)) > EPS:
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
		var old_upper: Vector3 = old_knee - hip
		var old_lower: Vector3 = old_ankle - old_knee
		if not old_upper.is_finite() or not old_lower.is_finite() or not is_finite(old_upper.length()) or not is_finite(old_lower.length()) or old_upper.length() <= EPS or old_lower.length() <= EPS:
			return _fail("pose: undefined raw anatomical direction " + side)
		var rest_normal: Vector3 = (reference["leg_stretch." + side].origin - reference["thigh_twist." + side].origin).cross(reference["foot." + side].origin - reference["leg_stretch." + side].origin)
		var body_rotation: Basis = source["root.x"].basis.orthonormalized() * reference["root.x"].basis.orthonormalized().transposed()
		var old_normal: Vector3 = body_rotation * rest_normal
		if not old_normal.is_finite() or not is_finite(old_normal.length_squared()) or old_normal.length() <= EPS * EPS:
			return _fail("knee_plane: undefined physical rest reference " + side)
		var normal: Vector3 = bend.cross(axis).normalized()
		# The body reference stays oriented when the raw knee passes through straight.
		var from_upper: Basis = _frame(old_upper, old_normal)
		var from_lower: Basis = _frame(old_lower, old_normal)
		var to_upper: Basis = _frame(knee - hip, normal)
		var to_lower: Basis = _frame(foot.origin - knee, normal)
		if not _rigid(from_upper) or not _rigid(from_lower) or not _rigid(to_upper) or not _rigid(to_lower):
			return _fail("knee_plane: undefined segment reference " + side)
		var upper_rotation: Basis = to_upper * from_upper.transposed()
		var lower_rotation: Basis = to_lower * from_lower.transposed()
		for part: String in ["thigh_twist", "thigh_stretch"]:
			var old: Transform3D = source[part + "." + side]
			var fraction: float = 0.0 if part == "thigh_twist" else reference["thigh_twist." + side].origin.distance_to(reference["thigh_stretch." + side].origin) / upper
			solved[part + "." + side] = Transform3D(upper_rotation * old.basis, hip.lerp(knee, fraction))
		for part: String in ["leg_stretch", "leg_twist"]:
			var old: Transform3D = source[part + "." + side]
			var fraction: float = 0.0 if part == "leg_stretch" else reference["leg_stretch." + side].origin.distance_to(reference["leg_twist." + side].origin) / lower
			solved[part + "." + side] = Transform3D(lower_rotation * old.basis, knee.lerp(foot.origin, fraction))

		solved["foot." + side] = foot
		solved["toes_01." + side] = toe
	if not _geometry(solved, reference):
		return _fail("contact: incompatible foot/toe or split geometry")
	var locals: Dictionary = authored.duplicate(true)
	var rebuilt: Dictionary = {}
	var pending: Array = authored.keys()
	while not pending.is_empty():
		var advanced: bool = false
		for name: String in pending.duplicate():
			var parent: String = rest.parents[name]
			if not parent.is_empty() and not rebuilt.has(parent):
				continue
			var parent_world: Transform3D = Transform3D.IDENTITY if parent.is_empty() else rebuilt[parent]
			var part: String = name.get_slice(".", 0)
			var side: String = name.get_slice(".", 1)
			var modified: bool = part in PARTS and side in ["l", "r"] and name == part + "." + side
			if modified:
				var local: Transform3D = parent_world.affine_inverse() * solved[name]
				if not _transform(local):
					return _fail("pose: invalid reconstructed local " + name)
				if part in ["foot", "toes_01"]:
					if not _same_affine(local.basis, authored[name].basis):
						return _fail("contact: incompatible native affine " + name)
				else:
					var native: Basis = authored[name].basis
					local.basis = local.basis.orthonormalized() * native.orthonormalized().transposed() * native
				if not _transform(local) or not _same_affine(local.basis, authored[name].basis):
					return _fail("pose: incompatible native affine " + name)
				locals[name] = local
				var a: Quaternion = (rest.locals[name] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
				var b: Quaternion = local.basis.orthonormalized().get_rotation_quaternion()
				if a.angle_to(b) > rest.legs[side].rotation_limits[part] + EPS:
					return _fail("joint_limit: local rotation " + name)
			rebuilt[name] = parent_world * locals[name]
			if not _transform(rebuilt[name]):
				return _fail("pose: invalid reconstructed global " + name)
			pending.erase(name)
			advanced = true
		if not advanced:
			return _fail("pose: inconsistent reconstructed parents")
	if not _geometry(rebuilt, reference):
		return _fail("pose: reconstructed physical geometry disagrees with rest")
	return {"ok": true, "locals": locals, "diagnostics": []}


## Read-only finite boundary measurement. All poses/rest are full native locals.
## meshes: {id:{binds:[{bone,pose}], vertices:[{position,influences:[{bind,weight}]}],
## sole_indices:[int]}}. Keep EVERY raw influence, including zero/nonunit sums.
## rest.segments explicitly names {a,b,split?} anatomical spans; no inferred rig.
## model_from_native includes the full skeleton ancestor affine transform.
## Length/split residuals are native skeleton metres; displacement/height is model metres.
## ground: {origin,normal} in model metres, unit normal. ok means valid inputs,
## never acceptable contact or continuity; no physical E is installed here.
static func measure_boundary(rest: Variant, raw: Variant, candidate: Variant, meshes: Variant, model_from_native: Variant, ground: Variant) -> Dictionary:
	if not _dict(rest) or not _dict(raw) or not _dict(candidate) or not _dict(meshes) or meshes.is_empty() or not _dict(ground):
		return _fail("boundary: expected complete dictionaries")
	if not _dict(rest.get("locals")) or not _dict(rest.get("parents")) or typeof(rest.get("segments")) != TYPE_ARRAY:
		return _fail("boundary: missing native rest/parents/segments")
	if not _transform(model_from_native) or typeof(ground.get("origin")) != TYPE_VECTOR3 or typeof(ground.get("normal")) != TYPE_VECTOR3:
		return _fail("boundary: malformed model/ground frame")
	if not ground.origin.is_finite() or not ground.normal.is_finite() or absf(ground.normal.length() - 1.0) > EPS:
		return _fail("boundary: ground normal must be unit length")
	var reference: Dictionary = _globals(rest.locals, rest.parents)
	var poses: Array[Dictionary] = [_globals(raw, rest.parents), _globals(candidate, rest.parents)]
	if reference.is_empty() or poses[0].is_empty() or poses[1].is_empty() or rest.parents.has(""):
		return _fail("boundary: invalid complete pose or parent graph")
	var out: Dictionary = {"ok": true, "physical_error_status": "unknown", "diagnostics": ["finite samples only; no contact or full-domain certificate"],
		"body_displacement_m": 0.0, "sole_displacement_m": 0.0, "sole_normal_displacement_m": 0.0, "sole_tangent_displacement_m": 0.0,
		"meshes": {}, "bones": {}, "segments": []}
	for name: String in reference:
		var gram_raw: Basis = raw[name].basis.transposed() * raw[name].basis
		var gram_candidate: Basis = candidate[name].basis.transposed() * candidate[name].basis
		var gram_rest: Basis = rest.locals[name].basis.transposed() * rest.locals[name].basis
		var raw_rest_residual: float = 0.0
		var candidate_rest_residual: float = 0.0
		var affine_residual: float = 0.0
		for axis: int in range(3):
			affine_residual = maxf(affine_residual, gram_raw[axis].distance_to(gram_candidate[axis]))
			raw_rest_residual = maxf(raw_rest_residual, gram_raw[axis].distance_to(gram_rest[axis]))
			candidate_rest_residual = maxf(candidate_rest_residual, gram_candidate[axis].distance_to(gram_rest[axis]))
		var row: Dictionary = {"origin_displacement_m": (model_from_native * poses[0][name].origin).distance_to(model_from_native * poses[1][name].origin), "local_gram_residual": affine_residual, "raw_rest_gram_residual": raw_rest_residual, "candidate_rest_gram_residual": candidate_rest_residual}
		var parent: String = rest.parents[name]
		if not parent.is_empty():
			var length: float = reference[name].origin.distance_to(reference[parent].origin)
			row.raw_length_residual_native_m = poses[0][name].origin.distance_to(poses[0][parent].origin) - length
			row.candidate_length_residual_native_m = poses[1][name].origin.distance_to(poses[1][parent].origin) - length
		for field: String in row:
			if not is_finite(row[field]):
				return _fail("boundary: overflowing bone metric")
		out.bones[name] = row
	for segment: Variant in rest.segments:
		if not _dict(segment) or not reference.has(segment.get("a")) or not reference.has(segment.get("b")):
			return _fail("boundary: invalid anatomical segment")
		var a: String = segment.a
		var b: String = segment.b
		var span: Vector3 = reference[b].origin - reference[a].origin
		if span.length() <= EPS:
			return _fail("boundary: degenerate anatomical segment")
		var row: Dictionary = {"a": a, "b": b, "raw_length_residual_native_m": poses[0][a].origin.distance_to(poses[0][b].origin) - span.length(),
			"candidate_length_residual_native_m": poses[1][a].origin.distance_to(poses[1][b].origin) - span.length()}
		if segment.has("split"):
			if not reference.has(segment.split):
				return _fail("boundary: unknown split bone")
			var fraction: float = (reference[segment.split].origin - reference[a].origin).dot(span) / span.length_squared()
			row.split = segment.split
			row.rest_fraction = fraction
			row.raw_split_residual_native_m = poses[0][segment.split].origin.distance_to(poses[0][a].origin.lerp(poses[0][b].origin, fraction))
			row.candidate_split_residual_native_m = poses[1][segment.split].origin.distance_to(poses[1][a].origin.lerp(poses[1][b].origin, fraction))
		for field: String in row:
			if typeof(row[field]) == TYPE_FLOAT and not is_finite(row[field]):
				return _fail("boundary: overflowing segment metric")
		out.segments.append(row)
	var sole_count: int = 0
	for mesh_name: Variant in meshes:
		var mesh: Variant = meshes[mesh_name]
		if typeof(mesh_name) != TYPE_STRING or mesh_name.is_empty() or not _dict(mesh):
			return _fail("boundary: invalid mesh identity")
		for field: String in ["binds", "vertices", "sole_indices"]:
			if typeof(mesh.get(field)) != TYPE_ARRAY:
				return _fail("boundary: missing mesh " + field)
		if mesh.binds.is_empty() or mesh.vertices.is_empty():
			return _fail("boundary: empty skin/mesh")
		var bind_names: Dictionary = {}
		var transforms: Array = [[], []]
		for bind: Variant in mesh.binds:
			if not _dict(bind) or not reference.has(bind.get("bone")) or bind_names.has(bind.bone) or not _transform(bind.get("pose")):
				return _fail("boundary: invalid named Skin bind")
			bind_names[bind.bone] = true
			for i: int in range(2):
				transforms[i].append(poses[i][bind.bone] * bind.pose)
		var soles: Dictionary = {}
		for index: Variant in mesh.sole_indices:
			if typeof(index) != TYPE_INT or index < 0 or index >= mesh.vertices.size() or soles.has(index):
				return _fail("boundary: invalid fixed sole material index")
			soles[index] = true
		sole_count += soles.size()
		var row: Dictionary = {"raw_points": PackedVector3Array(), "candidate_points": PackedVector3Array(), "max_displacement_m": 0.0,
			"raw_sole_heights_m": [], "candidate_sole_heights_m": [], "weight_sums": PackedFloat64Array()}
		for index: int in range(mesh.vertices.size()):
			var vertex: Variant = mesh.vertices[index]
			if not _dict(vertex) or typeof(vertex.get("position")) != TYPE_VECTOR3 or not vertex.position.is_finite() or typeof(vertex.get("influences")) != TYPE_ARRAY or vertex.influences.is_empty():
				return _fail("boundary: malformed material vertex")
			var points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
			var weight_sum: float = 0.0
			for influence: Variant in vertex.influences:
				if not _dict(influence) or typeof(influence.get("bind")) != TYPE_INT or influence.bind < 0 or influence.bind >= mesh.binds.size() or not _float(influence.get("weight")) or influence.weight < 0.0:
					return _fail("boundary: invalid raw skin influence")
				weight_sum += influence.weight
				for i: int in range(2):
					points[i] += (transforms[i][influence.bind] * vertex.position) * influence.weight
			if weight_sum <= 0.0 or not is_finite(weight_sum) or not points[0].is_finite() or not points[1].is_finite():
				return _fail("boundary: degenerate or overflowing raw LBS")
			for i: int in range(2):
				points[i] = model_from_native * points[i]
				if not points[i].is_finite():
					return _fail("boundary: overflowing model-space LBS")
			row.weight_sums.append(weight_sum)
			row.raw_points.append(points[0])
			row.candidate_points.append(points[1])
			var delta: Vector3 = points[1] - points[0]
			if not delta.is_finite() or not is_finite(delta.length()):
				return _fail("boundary: overflowing displacement metric")
			row.max_displacement_m = maxf(row.max_displacement_m, delta.length())
			out.body_displacement_m = maxf(out.body_displacement_m, delta.length())
			if soles.has(index):
				var normal: float = delta.dot(ground.normal)
				out.sole_displacement_m = maxf(out.sole_displacement_m, delta.length())
				out.sole_normal_displacement_m = maxf(out.sole_normal_displacement_m, absf(normal))
				out.sole_tangent_displacement_m = maxf(out.sole_tangent_displacement_m, (delta - ground.normal * normal).length())
				var raw_height: float = (points[0] - ground.origin).dot(ground.normal)
				var candidate_height: float = (points[1] - ground.origin).dot(ground.normal)
				if not is_finite(raw_height) or not is_finite(candidate_height) or not is_finite(out.sole_normal_displacement_m) or not is_finite(out.sole_tangent_displacement_m):
					return _fail("boundary: overflowing ground metric")
				row.raw_sole_heights_m.append(raw_height)
				row.candidate_sole_heights_m.append(candidate_height)
		out.meshes[mesh_name] = row
	if sole_count == 0:
		return _fail("boundary: explicit fixed sole material points required")
	return out


## Caller supplies E for ONE named displacement norm. Not_excluded is NOT sufficient.
## A common approximation has J <= 2E; preserving raw exactly has J <= E.
static func boundary_condition(jump_m: float, error_m: float, raw_fixed: bool) -> Dictionary:
	if not is_finite(jump_m) or not is_finite(error_m) or jump_m < 0.0 or error_m < 0.0:
		return _fail("boundary: invalid explicit metric error")
	var limit: float = error_m if raw_fixed else 2.0 * error_m
	if not is_finite(limit):
		return _fail("boundary: overflowing necessary limit")
	return {"ok": true, "status": "excluded" if jump_m > limit else "not_excluded", "necessary_limit_m": limit, "sufficient": false}
