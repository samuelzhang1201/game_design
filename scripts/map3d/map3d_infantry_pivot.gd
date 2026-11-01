class_name Map3DInfantryPivot
extends RefCounted
## Detached two-leg contact reconstruction; never a motion or contact certificate.
## Locals are absolute parent-relative transforms, NOT Skeleton3D pose deltas.
## Model metres, Y-up. Entry-model anchors turn by inverse committed pack yaw.
## rest: {bones:[{name,parent,local}], legs:[{hip,knee,ankle,toe,pole,
## min_knee_rad,max_knee_rad,followers}]} (two disjoint legs, ordered native parents).
## Dictionary identifiers accept Godot-equivalent String/StringName keys.
## authored_pose maps every bone name to a positive invertible affine local Transform3D.
## Rest joint lengths are measured in model space, not native parent offsets.
## followers maps lower-limb deform/twist bone names to hip|knee|ankle|toe.
## Each follows solved_segment * inverse(authored_segment) * authored_follower.
## Primary segment orientation retains authored twist and the rest stretch factor.
## Hip/knee orientation rejects near-antiparallel authored->solved segment axes
## (1+dot<=EPS); no arbitrary half-turn orientation is returned in that chart.
## operation: {duration_q,phase,yaw0_udeg,turn_udeg,current_yaw_udeg,
## march_entry_phase,march_exit_phase}; ints for duration/yaw0/turn, floats otherwise.
## contacts: {march_entry_phase,march_exit_phase,legs:{hip:{sole_bind,toe_bind,
## intervals:[{t0,t1,kind,point_from,point_to,sole_from,sole_to,toe_from,toe_to}]}}}.
## Points are Vector3; sole/toe orientation endpoints are proper rotation Basis values.
## All are ENTRY-model goals. stance pins the sole point; toe_stance pins the toe
## point; swing interpolates a free sole point. Planted points have equal endpoints.
## Independent sole/toe orientations slerp, allowing heel/toe roll and MARCH flex.
## Binds are affine ankle->sole and toe->toe contact; their composed rest-model
## frames must be rigid. Targets, normals and diagnostics are rigid model frames.
## Binds are ankle->sole and toe->toe contact (+Y normals). The free contact point
## follows fixed rest foot/toe geometry and both supplied orientations. Only limb
## origins move; no body offset repairs a goal. Both physical contact frames must
## continue across interval boundaries within numerical EPS.
## Intervals partition [0,1], shared boundary selects next; phase 1 uses final end.
## Exactly matching MARCH phases bind the supplied contacts to this transition.
## duration_q: 1..1e6; phase: 0..1; yaw0/current yaw: [0,360e6) udeg.
## turn: (-180e6,180e6] excluding zero; MARCH phases: [0,1).
## Current yaw must match wrap(yaw0 + turn*phase) within 1e-6 udeg.
## Adjacent derived sole/toe target frames must match; no gap/overlap/teleport.
## Bend limits are radians (0 straight); no reach clamping or borrowed authored stretch.
## pole defines a REST bend reference, transported by the shortest rest-axis->goal-axis
## rotation. Bent knees reject zero rest hip->ankle axes, reference pole projection
## <=EPS, or near-antipodal axes (1+dot<=EPS). Straight knees need no bend plane.
## These leg-reference domains are distinct from committed body yaw/turn angles.
## Rest lengths are reconstructed even when authored landmark distances differ.
## Success: {ok:true,reason:"",pose,contacts:{hip:{kind,sole,toe,target_sole,
## target_toe,knee_rad,upper_length,lower_length,sole_error,toe_error}}}.
## Contacts are current-model frames. Errors measure numerical reconstruction,
## not ground/skin slip; kind identifies the planted contact (or free swing).
## Failure: {ok:false,reason:nonempty String,pose:{},contacts:{}}.
## Uncontrolled authored locals (including upper body/gear) remain identical.
## No input mutation, scene/state lookup, clocks, accumulated phase, or body transform.

const EPS: float = 0.00001 # Numerical validation, not the arm's certified contact policy.
const REV: int = 360000000
const HALF: int = 180000000

static func sample(rest: Dictionary, authored_pose: Dictionary,
		operation: Dictionary, contacts: Dictionary) -> Dictionary:
	return _solve(rest, authored_pose, operation, contacts, false)

## Native variable-geometry mode: res://scripts/map3d/guide/infantry_pivot.md.
## transition has exactly {entry_pose,exit_pose}, complete native absolute locals.
## Contact rotations are proper polar frames; actual affine stretch/shear is retained.
static func sample_transition(rest: Dictionary, authored_pose: Dictionary,
		operation: Dictionary, contacts: Dictionary, transition: Dictionary) -> Dictionary:
	if not _keys(transition, ["entry_pose", "exit_pose"]) \
			or not transition.entry_pose is Dictionary or not transition.exit_pose is Dictionary:
		return _failure("invalid transition schema")
	# Solve the actual endpoints too: a phase-zero bypass would hide a C0 jump.
	for endpoint: int in [0, 1]:
		var reference: Dictionary = transition.entry_pose if endpoint == 0 else transition.exit_pose
		var op: Dictionary = operation.duplicate(true)
		if not _keys(op, ["duration_q", "phase", "yaw0_udeg", "turn_udeg", "current_yaw_udeg",
				"march_entry_phase", "march_exit_phase"]) \
				or not op.yaw0_udeg is int or not op.turn_udeg is int:
			return _failure("invalid operation schema/type")
		op.phase = float(endpoint)
		op.current_yaw_udeg = fposmod(float(op.yaw0_udeg) + float(op.turn_udeg) * endpoint, float(REV))
		var result: Dictionary = _solve(rest, reference, op, contacts, true)
		if not result.ok:
			return result
		for name: String in reference:
			if not _near(result.pose[name], reference[name]):
				return _failure("incompatible native endpoint: " + name)
	var result: Dictionary = _solve(rest, authored_pose, operation, contacts, true)
	if not result.ok:
		return result
	if operation.phase == 0.0 or operation.phase == 1.0:
		var reference: Dictionary = transition.entry_pose if operation.phase == 0.0 else transition.exit_pose
		for name: String in reference:
			if not _near(authored_pose[name], reference[name]):
				return _failure("current reference disagrees with native endpoint: " + name)
	return result

static func _solve(rest: Dictionary, authored_pose: Dictionary, operation: Dictionary,
		contacts: Dictionary, native: bool) -> Dictionary:
	var error: String = _validate(rest, authored_pose, operation, contacts, native)
	if not error.is_empty():
		return _failure(error)
	var rest_pose: Dictionary = {}
	for bone: Dictionary in rest.bones:
		rest_pose[bone.name] = bone.local
	var bind_globals: Dictionary = _globals(rest.bones, rest_pose)
	var authored: Dictionary = _globals(rest.bones, authored_pose)
	var geometry: Dictionary = authored if native else bind_globals
	var desired: Dictionary = {}
	var diagnostics: Dictionary = {}
	var inverse_yaw: Transform3D = Transform3D(Basis(Vector3.UP,
		deg_to_rad(float(operation.turn_udeg) * operation.phase / 1000000.0)), Vector3.ZERO)
	for leg: Dictionary in rest.legs:
		var bind: Dictionary = contacts.legs[leg.hip]
		var interval: Dictionary = bind.intervals[-1]
		for candidate: Dictionary in bind.intervals:
			if operation.phase < candidate.t1:
				interval = candidate
				break
		var share: float = (operation.phase - interval.t0) / (interval.t1 - interval.t0)
		var feet: Dictionary = _native_feet(geometry[leg.ankle], geometry[leg.toe], bind,
			interval, share, inverse_yaw) if native else _feet(bind_globals[leg.ankle], bind_globals[leg.toe], bind,
			interval, share, inverse_yaw)
		if not _affine(feet.ankle) or not _affine(feet.toe) \
				or not _affine(feet.sole_target) or not _affine(feet.toe_target):
			return _failure("invalid contact targets: " + leg.hip)
		var ankle: Transform3D = feet.ankle
		var hip: Transform3D = authored[leg.hip]
		var upper: float = geometry[leg.hip].origin.distance_to(geometry[leg.knee].origin)
		var lower: float = geometry[leg.knee].origin.distance_to(geometry[leg.ankle].origin)
		if native:
			upper = _length64(geometry[leg.knee].origin - geometry[leg.hip].origin)
			lower = _length64(geometry[leg.ankle].origin - geometry[leg.knee].origin)
		var delta: Vector3 = ankle.origin - hip.origin
		var distance: float = _length64(delta) if native else delta.length()
		if not is_finite(distance) or distance <= 0.0 or distance > upper + lower \
				or distance < absf(upper - lower):
			return _failure("unreachable target: " + leg.hip)
		var cosine: float = (distance * distance - upper * upper - lower * lower) / (2.0 * upper * lower)
		# A rounding overflow is failure too, never an unreachable-target clamp.
		if not is_finite(cosine) or cosine < -1.0 or cosine > 1.0:
			return _failure("invalid joint geometry: " + leg.hip)
		var bend: float = acos(cosine)
		if bend < leg.min_knee_rad or bend > leg.max_knee_rad:
			return _failure("joint limit: " + leg.hip)
		var direction: Vector3 = delta / distance
		var along: float = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
		var height_squared: float = upper * upper - along * along
		if not is_finite(height_squared) or height_squared < 0.0:
			return _failure("invalid knee geometry: " + leg.hip)
		var plane: Vector3 = Vector3.ZERO
		if height_squared > 0.0:
			if native:
				var axis: Vector3 = geometry[leg.ankle].origin - geometry[leg.hip].origin
				if axis.length_squared() == 0.0:
					return _failure("undefined authored knee axis: " + leg.hip)
				var source_bend: Vector3 = geometry[leg.knee].origin - geometry[leg.hip].origin
				source_bend -= axis * source_bend.dot(axis) / axis.length_squared()
				plane = _knee_plane(axis, direction, source_bend)
			else:
				plane = _knee_plane(bind_globals[leg.ankle].origin - bind_globals[leg.hip].origin,
					direction, leg.pole)
			if plane == Vector3.ZERO:
				return _failure("undefined knee reference plane: " + leg.hip)
		var knee_point: Vector3 = hip.origin + direction * along + plane * sqrt(height_squared)
		desired[leg.hip] = Transform3D(_orient_native(authored[leg.hip],
			geometry[leg.knee].origin - geometry[leg.hip].origin, knee_point - hip.origin) if native else
			_orient(bind_globals[leg.hip], authored[leg.hip],
			bind_globals[leg.knee].origin - bind_globals[leg.hip].origin,
			knee_point - hip.origin), hip.origin)
		desired[leg.knee] = Transform3D(_orient_native(authored[leg.knee],
			geometry[leg.ankle].origin - geometry[leg.knee].origin, ankle.origin - knee_point) if native else
			_orient(bind_globals[leg.knee], authored[leg.knee],
			bind_globals[leg.ankle].origin - bind_globals[leg.knee].origin,
			ankle.origin - knee_point), knee_point)
		if desired[leg.hip].basis.determinant() <= 0.0 or desired[leg.knee].basis.determinant() <= 0.0:
			return _failure("undefined segment orientation: " + leg.hip)
		desired[leg.ankle] = ankle
		desired[leg.toe] = feet.toe
		for follower: String in leg.followers:
			var primary: String = leg[leg.followers[follower]]
			desired[follower] = desired[primary] * authored[primary].affine_inverse() * authored[follower]
		diagnostics[leg.hip] = {"kind": interval.kind, "target_sole": feet.sole_target,
			"target_toe": feet.toe_target, "knee_rad": bend, "upper_length": upper, "lower_length": lower}
	# Native ARP deform joints can be siblings. Convert model targets in parent order.
	var pose: Dictionary = authored_pose.duplicate(true)
	var globals: Dictionary = {}
	for bone: Dictionary in rest.bones:
		var parent: Transform3D = Transform3D.IDENTITY if bone.parent.is_empty() else globals[bone.parent]
		if desired.has(bone.name):
			pose[bone.name] = parent.affine_inverse() * desired[bone.name]
		globals[bone.name] = parent * pose[bone.name]
		if not _affine(pose[bone.name]) or not _affine(globals[bone.name]):
			return _failure("invalid solved transform: " + bone.name)
	for leg: Dictionary in rest.legs:
		var bind: Dictionary = contacts.legs[leg.hip]
		var d: Dictionary = diagnostics[leg.hip]
		var sole: Transform3D = globals[leg.ankle] * bind.sole_bind
		var toe: Transform3D = globals[leg.toe] * bind.toe_bind
		var sole_error: float = sole.origin.distance_to(d.target_sole.origin)
		var toe_error: float = toe.origin.distance_to(d.target_toe.origin)
		var upper: float = globals[leg.hip].origin.distance_to(globals[leg.knee].origin)
		var lower: float = globals[leg.knee].origin.distance_to(globals[leg.ankle].origin)
		var toe_length: float = geometry[leg.ankle].origin.distance_to(geometry[leg.toe].origin)
		if (not native and (not _rigid(sole) or not _rigid(toe))) or not _near(sole, d.target_sole) \
				or not _near(toe, d.target_toe) or not is_finite(sole_error) or not is_finite(toe_error) \
				or absf(upper - d.upper_length) > EPS or absf(lower - d.lower_length) > EPS \
				or absf(globals[leg.ankle].origin.distance_to(globals[leg.toe].origin) - toe_length) > EPS:
			return _failure("contact reconstruction failed: " + leg.hip)
		d.sole = sole
		d.toe = toe
		d.sole_error = sole_error
		d.toe_error = toe_error
		d.upper_length = upper
		d.lower_length = lower
	return {"ok": true, "reason": "", "pose": pose, "contacts": diagnostics}

static func _validate(rest: Dictionary, pose: Dictionary, op: Dictionary, contacts: Dictionary,
		native: bool = false) -> String:
	if not _keys(rest, ["bones", "legs"]) or not rest.bones is Array or not rest.legs is Array \
			or rest.legs.size() != 2 or rest.bones.is_empty():
		return "invalid rest schema"
	var bones: Dictionary = {}
	for raw: Variant in rest.bones:
		if not _keys(raw, ["name", "parent", "local"]):
			return "invalid bone schema"
		var bone: Dictionary = raw
		if not bone.name is String or bone.name.is_empty() or bones.has(bone.name) \
				or not bone.parent is String or (not bone.parent.is_empty() and not bones.has(bone.parent)) \
				or not _affine(bone.local):
			return "invalid bone bind/order"
		bones[bone.name] = bone
	if not _keys(pose, bones.keys()):
		return "incomplete authored pose"
	for value: Variant in pose.values():
		if not _affine(value):
			return "invalid authored transform"
	var rest_pose: Dictionary = {}
	for name: String in bones:
		rest_pose[name] = bones[name].local
	var bind_globals: Dictionary = _globals(rest.bones, rest_pose)
	var authored_globals: Dictionary = _globals(rest.bones, pose)
	for name: String in bones:
		if not _affine(bind_globals[name]) or not _affine(authored_globals[name]):
			return "nonfinite or singular composed transform"
	var used: Dictionary = {}
	var hips: Array = []
	for raw: Variant in rest.legs:
		if not _keys(raw, ["hip", "knee", "ankle", "toe", "pole", "min_knee_rad", "max_knee_rad", "followers"]):
			return "invalid leg schema"
		var leg: Dictionary = raw
		if not leg.pole is Vector3 or not leg.pole.is_finite() or not is_finite(leg.pole.length()) \
				or leg.pole.length() <= 0.0 or not _float_range(leg.min_knee_rad, 0.0, PI) \
				or not _float_range(leg.max_knee_rad, leg.min_knee_rad, PI):
			return "invalid knee pole/limits"
		for role: String in ["hip", "knee", "ankle", "toe"]:
			var name: Variant = leg[role]
			if not name is String or not bones.has(name) or used.has(name):
				return "missing or duplicate leg bone"
			used[name] = leg.hip
		for pair: Array in [[leg.hip, leg.knee], [leg.knee, leg.ankle], [leg.ankle, leg.toe]]:
			var length: float = bind_globals[pair[0]].origin.distance_to(bind_globals[pair[1]].origin)
			if not is_finite(length) or length <= 0.0:
				return "invalid rest joint length"
			if native:
				length = authored_globals[pair[0]].origin.distance_to(authored_globals[pair[1]].origin)
				if not is_finite(length) or length <= 0.0:
					return "invalid authored joint length"
		if not leg.followers is Dictionary:
			return "invalid follower schema"
		for name: Variant in leg.followers:
			var role: Variant = leg.followers[name]
			if typeof(name) not in [TYPE_STRING, TYPE_STRING_NAME] or not bones.has(name) or used.has(name) \
					or not role is String or role not in ["hip", "knee", "ankle", "toe"]:
				return "invalid or duplicate follower binding"
			used[name] = leg.hip
		hips.append(leg.hip)
	for name: String in used:
		var parent: String = bones[name].parent
		while not parent.is_empty():
			if used.has(parent) and used[parent] != used[name]:
				return "overlapping leg ancestors"
			parent = bones[parent].parent
	if not _keys(op, ["duration_q", "phase", "yaw0_udeg", "turn_udeg", "current_yaw_udeg",
			"march_entry_phase", "march_exit_phase"]):
		return "invalid operation schema"
	if not op.duration_q is int or op.duration_q < 1 or op.duration_q > 1000000 \
			or not op.yaw0_udeg is int or op.yaw0_udeg < 0 or op.yaw0_udeg >= REV \
			or not op.turn_udeg is int or op.turn_udeg <= -HALF or op.turn_udeg > HALF or op.turn_udeg == 0 \
			or not _float_range(op.phase, 0.0, 1.0) \
			or not _float_range(op.current_yaw_udeg, 0.0, float(REV)) or op.current_yaw_udeg >= REV \
			or not _phase(op.march_entry_phase) or not _phase(op.march_exit_phase):
		return "invalid operation range/type"
	var expected: float = fposmod(float(op.yaw0_udeg) + float(op.turn_udeg) * op.phase, float(REV))
	var yaw_error: float = absf(fposmod(op.current_yaw_udeg - expected + HALF, float(REV)) - HALF)
	if yaw_error > 0.000001:
		return "current yaw disagrees with committed phase"
	if not _keys(contacts, ["march_entry_phase", "march_exit_phase", "legs"]) \
			or not _phase(contacts.march_entry_phase) or not _phase(contacts.march_exit_phase) \
			or contacts.march_entry_phase != op.march_entry_phase or contacts.march_exit_phase != op.march_exit_phase \
			or not _keys(contacts.legs, hips):
		return "invalid contact phase/binding schema"
	for hip: String in hips:
		var raw: Variant = contacts.legs[hip]
		if not _keys(raw, ["sole_bind", "toe_bind", "intervals"]) \
				or not _affine(raw.sole_bind) or not _affine(raw.toe_bind) \
				or not raw.intervals is Array or raw.intervals.is_empty():
			return "invalid contact bind"
		var leg: Dictionary = rest.legs[hips.find(hip)]
		if not _rigid(bind_globals[leg.ankle] * raw.sole_bind) \
				or not _rigid(bind_globals[leg.toe] * raw.toe_bind):
			return "contact bind is not a rigid model frame"
		var end: float = 0.0
		var previous: Dictionary = {}
		for item: Variant in raw.intervals:
			if not _keys(item, ["t0", "t1", "kind", "point_from", "point_to",
					"sole_from", "sole_to", "toe_from", "toe_to"]):
				return "invalid contact interval schema"
			if not _float_range(item.t0, 0.0, 1.0) or not _float_range(item.t1, 0.0, 1.0) \
					or item.t0 != end or item.t1 <= item.t0 or not item.kind is String \
					or item.kind not in ["stance", "toe_stance", "swing"] \
					or not item.point_from is Vector3 or not item.point_to is Vector3 \
					or not item.point_from.is_finite() or not item.point_to.is_finite() \
					or not _rotation(item.sole_from) or not _rotation(item.sole_to) \
					or not _rotation(item.toe_from) or not _rotation(item.toe_to):
				return "invalid contact interval"
			if item.kind != "swing" and item.point_from != item.point_to:
				return "moving stance anchor"
			var first: Dictionary = _native_feet(authored_globals[leg.ankle], authored_globals[leg.toe],
				raw, item, 0.0, Transform3D.IDENTITY) if native else _feet(bind_globals[leg.ankle], bind_globals[leg.toe],
				raw, item, 0.0, Transform3D.IDENTITY)
			var last: Dictionary = _native_feet(authored_globals[leg.ankle], authored_globals[leg.toe],
				raw, item, 1.0, Transform3D.IDENTITY) if native else _feet(bind_globals[leg.ankle], bind_globals[leg.toe],
				raw, item, 1.0, Transform3D.IDENTITY)
			for targets: Dictionary in [first, last]:
				if not _affine(targets.ankle) or not _affine(targets.toe) \
						or not _affine(targets.sole_target) or not _affine(targets.toe_target) \
						or (not native and (not _rigid(targets.sole_target) or not _rigid(targets.toe_target))):
					return "invalid endpoint contact targets"
			if not previous.is_empty() and (not _near(previous.sole_target, first.sole_target) \
					or not _near(previous.toe_target, first.toe_target)):
				return "discontinuous contact intervals"
			end = item.t1
			previous = last
		if end != 1.0:
			return "incomplete contact intervals"
	return ""

static func _feet(ankle_rest: Transform3D, toe_rest: Transform3D, bind: Dictionary,
		interval: Dictionary, share: float, inverse_yaw: Transform3D) -> Dictionary:
	var point: Vector3 = inverse_yaw * interval.point_from.lerp(interval.point_to, share)
	var sole_basis: Basis = inverse_yaw.basis * interval.sole_from.slerp(interval.sole_to, share)
	var toe_basis: Basis = inverse_yaw.basis * interval.toe_from.slerp(interval.toe_to, share)
	var ankle: Transform3D = Transform3D(sole_basis * bind.sole_bind.basis.inverse(), Vector3.ZERO)
	var toe: Transform3D = Transform3D(toe_basis * bind.toe_bind.basis.inverse(), Vector3.ZERO)
	var offset: Vector3 = ankle.basis * ankle_rest.basis.inverse() * (toe_rest.origin - ankle_rest.origin)
	if interval.kind == "toe_stance":
		toe.origin = point - toe.basis * bind.toe_bind.origin
		ankle.origin = toe.origin - offset
	else:
		ankle.origin = point - ankle.basis * bind.sole_bind.origin
		toe.origin = ankle.origin + offset
	return {"ankle": ankle, "toe": toe, "sole_target": ankle * bind.sole_bind,
		"toe_target": toe * bind.toe_bind}

# Vector3.length rounds to real_t before the near-straight triangle subtraction.
static func _length64(vector: Vector3) -> float:
	var x: float = vector.x
	var y: float = vector.y
	var z: float = vector.z
	return sqrt(x * x + y * y + z * z)

# Newton polar decomposition retains shear separately from the proper contact rotation.
static func _polar(basis: Basis) -> Basis:
	var value: Basis = basis
	for i: int in range(24):
		if not value.is_finite() or value.determinant() <= 0.0:
			break
		var inverse: Basis = value.inverse().transposed()
		value = Basis((value.x + inverse.x) * 0.5, (value.y + inverse.y) * 0.5, (value.z + inverse.z) * 0.5)
		if _rotation(value):
			return value
	return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

static func _native_feet(ankle_source: Transform3D, toe_source: Transform3D, bind: Dictionary,
		interval: Dictionary, share: float, inverse_yaw: Transform3D) -> Dictionary:
	var sole_rotation: Basis = _polar((ankle_source * bind.sole_bind).basis)
	var toe_rotation: Basis = _polar((toe_source * bind.toe_bind).basis)
	var sole_delta: Basis = inverse_yaw.basis * interval.sole_from.slerp(interval.sole_to, share) * sole_rotation.transposed()
	var toe_delta: Basis = inverse_yaw.basis * interval.toe_from.slerp(interval.toe_to, share) * toe_rotation.transposed()
	var ankle: Transform3D = Transform3D(sole_delta * ankle_source.basis, Vector3.ZERO)
	var toe: Transform3D = Transform3D(toe_delta * toe_source.basis, Vector3.ZERO)
	var point: Vector3 = inverse_yaw * interval.point_from.lerp(interval.point_to, share)
	var offset: Vector3 = sole_delta * (toe_source.origin - ankle_source.origin)
	if interval.kind == "toe_stance":
		toe.origin = point - toe.basis * bind.toe_bind.origin
		ankle.origin = toe.origin - offset
	else:
		ankle.origin = point - ankle.basis * bind.sole_bind.origin
		toe.origin = ankle.origin + offset
	return {"ankle": ankle, "toe": toe, "sole_target": ankle * bind.sole_bind,
		"toe_target": toe * bind.toe_bind}

static func _orient_native(authored: Transform3D, source_segment: Vector3, target_segment: Vector3) -> Basis:
	var source: Vector3 = source_segment.normalized()
	var target: Vector3 = target_segment.normalized()
	var cosine: float = source.dot(target)
	if 1.0 + cosine <= EPS:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var cross: Vector3 = source.cross(target)
	var aim: Basis = Basis.IDENTITY if cross.length_squared() == 0.0 else \
		Basis(cross.normalized(), atan2(cross.length(), cosine))
	return aim * authored.basis

static func _rotation(value: Variant) -> bool:
	return value is Basis and _rigid(Transform3D(value, Vector3.ZERO))

static func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= EPS and a.basis.x.distance_to(b.basis.x) <= EPS \
		and a.basis.y.distance_to(b.basis.y) <= EPS and a.basis.z.distance_to(b.basis.z) <= EPS

static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: Variant in keys:
		if not value.has(key):
			return false
	return true

static func _float_range(value: Variant, low: float, high: float) -> bool:
	return value is float and is_finite(value) and value >= low and value <= high

static func _phase(value: Variant) -> bool:
	return _float_range(value, 0.0, 1.0) and value < 1.0

static func _affine(value: Variant) -> bool:
	return value is Transform3D and value.is_finite() and is_finite(value.basis.determinant()) \
		and value.basis.determinant() > 0.0 and value.affine_inverse().is_finite()

static func _rigid(value: Variant) -> bool:
	if not value is Transform3D or not value.is_finite():
		return false
	var b: Basis = value.basis
	return absf(b.x.length_squared() - 1.0) <= EPS and absf(b.y.length_squared() - 1.0) <= EPS \
		and absf(b.z.length_squared() - 1.0) <= EPS and absf(b.x.dot(b.y)) <= EPS \
		and absf(b.y.dot(b.z)) <= EPS and absf(b.z.dot(b.x)) <= EPS and absf(b.determinant() - 1.0) <= EPS

static func _globals(bones: Array, pose: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for bone: Dictionary in bones:
		result[bone.name] = pose[bone.name] if bone.parent.is_empty() else result[bone.parent] * pose[bone.name]
	return result

static func _knee_plane(rest_axis: Vector3, direction: Vector3, pole: Vector3) -> Vector3:
	var rest_length: float = rest_axis.length()
	if not is_finite(rest_length) or rest_length <= 0.0:
		return Vector3.ZERO
	var reference: Vector3 = rest_axis / rest_length
	var pole_unit: Vector3 = pole.normalized()
	var bend: Vector3 = pole_unit - reference * pole_unit.dot(reference)
	var cosine: float = reference.dot(direction)
	if bend.length_squared() <= EPS * EPS or 1.0 + cosine <= EPS:
		return Vector3.ZERO
	# Transport the bind bend; projecting against the moving axis would flip its sign.
	var cross: Vector3 = reference.cross(direction)
	var rotation: Basis = Basis(Quaternion(cross.x, cross.y, cross.z, 1.0 + cosine).normalized())
	var plane: Vector3 = rotation * bend.normalized()
	plane -= direction * plane.dot(direction)
	if not plane.is_finite() or plane.length_squared() <= EPS * EPS:
		return Vector3.ZERO
	return plane.normalized()

static func _orient(rest: Transform3D, authored: Transform3D, rest_segment: Vector3,
		target_segment: Vector3) -> Basis:
	var rotation: Basis = authored.basis.orthonormalized() * rest.basis.orthonormalized().transposed()
	var source: Vector3 = (rotation * rest_segment).normalized()
	var target: Vector3 = target_segment.normalized()
	var cosine: float = source.dot(target)
	if 1.0 + cosine <= EPS:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var cross: Vector3 = source.cross(target)
	var aim: Basis = Basis.IDENTITY if cross.length_squared() == 0.0 else \
		Basis(cross.normalized(), atan2(cross.length(), cosine))
	return aim * rotation * rest.basis

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "pose": {}, "contacts": {}}
