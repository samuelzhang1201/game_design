class_name Map3DCavalryPivot
extends RefCounted
## Pure presentation-space limb reconstruction. No animation, clock or state lookup.
## sample accepts raw Variants so malformed callers receive an atomic diagnostic.
## rest = {version:1, turn_axis:unit Vector3, bones:[{name:String,parent:String,
## bind:Transform3D,bind_global:Transform3D,head:Vector3,tail:Vector3}], chains:{hoof:{bones:[String],
## rotation_limits:[float radians],bend_limits:[Vector2 signed radians],
## bend_normals:[unit Vector3 in the first bone's parent frame]}}}.
## Bones are topological; parent="" denotes the single root. Bind and anatomical
## landmarks must come from the immutable source, never a posed replacement.
## bind_global is the independently retained full inverse-bind reference; FK of
## bind must match it, including twist/shear. Never regenerate it from a pose.
## Native full affine locals are distinct: authored_pose={locals,entry,exit},
## each an exact bone-name -> Transform3D dictionary. Native continuity and
## source provenance are caller preconditions, not certificates this seam issues.
## operation={start_heading,end_heading,turn_degrees,duration,phase,entry_phase,
## exit_phase}: floats; degrees [0,360), shortest turn (-180,180] (+180 tie),
## seconds >0, phase [0,1], native phases [0,1). No input is retimed or clamped.
## contacts={each hoof:{offset:Transform3D,segments:[{start,end,mode,from,to,
## from_derivative,to_derivative}]}}. Segments partition [0,1], C1 in full affine
## value and phase derivative. mode is stance (constant) or swing. Transforms
## name the full sole frame in the operation's fixed START ground frame; offset
## names that measured frame relative to the hoof. Swing uses Hermite position
## and polar stretch, and exponential-coordinate SO(3) Hermite rotation. Thus
## 180-degree interiors stay invertible, with the declared endpoint derivatives.
## Output={ok,locals,diagnostics}; failure locals is empty, success copies EVERY
## local. Only the 18 listed limb/hoof bases may rotate; native local origins
## and stretch/shear remain unchanged. Other locals pass through exactly.
## This numerical seam does not certify native-window art, skin/sole or envelopes.

const _Math: GDScript = preload("res://scripts/map3d/map3d_cavalry_pivot_math.gd")
const _BEND_DOMAIN: Vector2 = Vector2(-PI, PI)
# Storage roundoff for a normalized float32 Vector3, not a contact tolerance.
const _UNIT_ROUNDOFF: float = 8.0 * 0.00000011920928955078125
const _HOOVES: Array[String] = ["FrontHoof.L", "FrontHoof.R", "HindHoof.L", "HindHoof.R"]
const _OP_KEYS: Array[String] = ["start_heading", "end_heading", "turn_degrees", "duration", "phase", "entry_phase", "exit_phase"]
const _SEGMENT_KEYS: Array[String] = ["start", "end", "mode", "from", "to", "from_derivative", "to_derivative"]


static func sample(rest: Variant, authored_pose: Variant, operation: Variant, contacts: Variant) -> Dictionary:
	if not _Math._finite(rest) or not _Math._finite(authored_pose) or not _Math._finite(operation) or not _Math._finite(contacts):
		return _reject("nonfinite_or_raw_type")
	if not _keys(rest, ["version", "turn_axis", "bones", "chains"]) or not _keys(authored_pose, ["locals", "entry", "exit"]) or not _keys(operation, _OP_KEYS) or not _keys(contacts, _HOOVES):
		return _reject("schema")
	var reason: String = _validate_rest(rest)
	if reason != "":
		return _reject(reason)
	reason = _validate_operation(operation)
	if reason != "":
		return _reject(reason)
	for key: String in ["locals", "entry", "exit"]:
		reason = _validate_pose(rest, authored_pose[key])
		if reason != "":
			return _reject(key + ":" + reason)
	if operation.phase == 0.0 and authored_pose.locals != authored_pose.entry:
		return _reject("entry_pose_mismatch")
	if operation.phase == 1.0 and authored_pose.locals != authored_pose.exit:
		return _reject("exit_pose_mismatch")
	var entry: Dictionary = _Math._fk(rest.bones, authored_pose.entry)
	var exit: Dictionary = _Math._fk(rest.bones, authored_pose.exit)
	var turn_end: Transform3D = Transform3D(Basis(rest.turn_axis, deg_to_rad(operation.turn_degrees)), Vector3.ZERO)
	for hoof: String in _HOOVES:
		reason = _validate_contact(contacts[hoof])
		if reason != "":
			return _reject(hoof + ":" + reason)
		var segments: Array = contacts[hoof].segments
		if not _Math._close(segments[0].from, entry[hoof] * contacts[hoof].offset) or not _Math._close(segments[-1].to, turn_end * exit[hoof] * contacts[hoof].offset):
			return _reject(hoof + ":incompatible_native_endpoint")
	var locals: Dictionary = authored_pose.locals.duplicate(true)
	var globals: Dictionary = _Math._fk(rest.bones, locals)
	var turn: Transform3D = Transform3D(Basis(rest.turn_axis, deg_to_rad(operation.turn_degrees * operation.phase)), Vector3.ZERO)
	var iterations: int = 0
	for hoof: String in _HOOVES:
		var contact: Dictionary = contacts[hoof]
		var curve: Dictionary = _Math._contact_at(contact, operation.phase, rest.turn_axis)
		if not curve.ok:
			return _reject(hoof + ":" + curve.reason)
		var chain: Dictionary = rest.chains[hoof]
		var first: Dictionary = _Math._bone(rest.bones, chain.bones[0])
		var attachment: Vector3 = globals[first.name] * first.head
		var parent: String = first.parent
		var solved: Dictionary = _Math._solve(rest, chain, locals, curve.value, globals[parent], turn, contact.offset)
		if not solved.ok:
			return _reject(hoof + ":" + solved.reason, {"iterations": iterations + solved.iterations})
		iterations += solved.iterations
		for name: String in chain.bones:
			locals[name] = solved.locals[name]
		globals = _Math._fk(rest.bones, locals)
		if (globals[first.name] * first.head).distance_to(attachment) > _Math.EPS:
			return _reject(hoof + ":attachment_residual", {"iterations": iterations})
		if not _Math._close(turn * globals[hoof] * contact.offset, curve.value):
			return _reject(hoof + ":contact_residual", {"iterations": iterations})
	reason = _validate_pose(rest, locals)
	if reason != "":
		return _reject("solved:" + reason, {"iterations": iterations})
	# Compatible endpoints must keep every bit of their native skin matrices.
	if operation.phase == 0.0 or operation.phase == 1.0:
		if locals != authored_pose.locals:
			return _reject("native_endpoint_requires_correction")
	return {"ok": true, "locals": locals, "diagnostics": {"reason": "", "iterations": iterations}}


static func _reject(reason: String, diagnostics: Dictionary = {}) -> Dictionary:
	var out: Dictionary = diagnostics.duplicate(true)
	out["reason"] = reason
	return {"ok": false, "locals": {}, "diagnostics": out}


static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: Variant in value:
		if not key is String or not key in keys:
			return false
	return true


static func _unit(value: Vector3) -> bool:
	return absf(value.length_squared() - 1.0) <= _UNIT_ROUNDOFF


static func _validate_rest(rest: Dictionary) -> String:
	if typeof(rest.version) != TYPE_INT or rest.version != 1 or not rest.turn_axis is Vector3 or not _unit(rest.turn_axis) or not rest.bones is Array or not _keys(rest.chains, _HOOVES):
		return "rest_schema"
	var seen: Dictionary = {}
	var roots: int = 0
	for bone: Variant in rest.bones:
		if not _keys(bone, ["name", "parent", "bind", "bind_global", "head", "tail"]):
			return "bone_schema"
		if not bone.name is String or bone.name == "" or seen.has(bone.name) or not bone.parent is String or not _Math._affine(bone.bind) or not _Math._affine(bone.bind_global) or not bone.head is Vector3 or not bone.tail is Vector3 or bone.head == bone.tail:
			return "bone_data"
		if bone.parent == "":
			roots += 1
		elif not seen.has(bone.parent):
			return "hierarchy"
		seen[bone.name] = bone
	if roots != 1:
		return "hierarchy_root"
	var bind_locals: Dictionary = {}
	for bone: Dictionary in rest.bones:
		bind_locals[bone.name] = bone.bind
	var bind_globals: Dictionary = _Math._fk(rest.bones, bind_locals)
	for bone: Dictionary in rest.bones:
		var global: Transform3D = bind_globals[bone.name]
		if not _Math._finite(global) or not _Math._affine(global):
			return "bind_global_affine"
		if not _Math._close(global, bone.bind_global):
			return "bind_global_mismatch"
	for hoof: String in _HOOVES:
		var chain: Variant = rest.chains[hoof]
		if not _keys(chain, ["bones", "rotation_limits", "bend_limits", "bend_normals"]):
			return "chain_schema"
		var expected: Array[String] = _names(hoof)
		if not chain.bones is Array or chain.bones != expected or not chain.rotation_limits is Array or chain.rotation_limits.size() != expected.size() or not chain.bend_limits is Array or chain.bend_limits.size() != expected.size() - 2 or not chain.bend_normals is Array or chain.bend_normals.size() != expected.size() - 2:
			return "chain_data"
		for i: int in expected.size():
			var name: String = expected[i]
			if not seen.has(name) or typeof(chain.rotation_limits[i]) != TYPE_FLOAT or chain.rotation_limits[i] < 0.0 or chain.rotation_limits[i] > PI:
				return "rotation_limit"
			if i == 0 and not seen.has(seen[name].parent):
				return "chain_parent"
			if i > 0:
				if seen[name].parent != expected[i - 1] or (seen[name].bind * seen[name].head).distance_to(seen[expected[i - 1]].tail) > _Math.EPS:
					return "bind_anatomical_connectivity"
		for i: int in chain.bend_limits.size():
			var limit: Variant = chain.bend_limits[i]
			var normal: Variant = chain.bend_normals[i]
			if not limit is Vector2 or limit.x < _BEND_DOMAIN.x or limit.y > _BEND_DOMAIN.y or limit.x > limit.y or not normal is Vector3 or not _unit(normal):
				return "bend_limit"
	return ""


static func _names(hoof: String) -> Array[String]:
	var suffix: String = hoof.right(2)
	if hoof.begins_with("Front"):
		return ["FrontScapula" + suffix, "FrontUpperArm" + suffix, "FrontForearm" + suffix, "FrontCannon" + suffix, "FrontHoof" + suffix]
	return ["HindThigh" + suffix, "HindShin" + suffix, "HindCannon" + suffix, "HindHoof" + suffix]


static func _validate_operation(op: Dictionary) -> String:
	for key: String in _OP_KEYS:
		if typeof(op[key]) != TYPE_FLOAT:
			return "operation_type"
	if op.start_heading < 0.0 or op.start_heading >= 360.0 or op.end_heading < 0.0 or op.end_heading >= 360.0 or op.turn_degrees <= -180.0 or op.turn_degrees > 180.0 or op.duration <= 0.0 or op.phase < 0.0 or op.phase > 1.0 or op.entry_phase < 0.0 or op.entry_phase >= 1.0 or op.exit_phase < 0.0 or op.exit_phase >= 1.0:
		return "operation_domain"
	var expected: float = fposmod(op.end_heading - op.start_heading, 360.0)
	if expected > 180.0:
		expected -= 360.0
	var roundoff: float = 8.0 * 2.220446049250313e-16 * maxf(1.0, maxf(op.start_heading, op.end_heading))
	if signf(expected) != signf(op.turn_degrees) or absf(expected - op.turn_degrees) > roundoff:
		return "signed_shortest_turn"
	return ""


static func _validate_pose(rest: Dictionary, pose: Variant) -> String:
	if not pose is Dictionary or pose.size() != rest.bones.size():
		return "pose_schema"
	for bone: Dictionary in rest.bones:
		if not pose.has(bone.name) or not _Math._affine(pose[bone.name]):
			return "pose_affine"
	var globals: Dictionary = _Math._fk(rest.bones, pose)
	for global: Transform3D in globals.values():
		if not _Math._finite(global) or not _Math._affine(global):
			return "pose_global_affine"
	for hoof: String in _HOOVES:
		var chain: Dictionary = rest.chains[hoof]
		for i: int in range(1, chain.bones.size()):
			var bone: Dictionary = _Math._bone(rest.bones, chain.bones[i])
			var parent: Dictionary = _Math._bone(rest.bones, chain.bones[i - 1])
			var head: Vector3 = globals[bone.name] * bone.head
			var tail: Vector3 = globals[parent.name] * parent.tail
			if not head.is_finite() or not tail.is_finite() or (pose[bone.name] * bone.head).distance_to(parent.tail) > _Math.EPS or head.distance_to(tail) > _Math.EPS:
				return "native_anatomical_connectivity"
	return ""


static func _validate_contact(contact: Variant) -> String:
	if not _keys(contact, ["offset", "segments"]) or not _Math._affine(contact.offset) or not contact.segments is Array or contact.segments.is_empty():
		return "contact_schema"
	var previous: Dictionary = {}
	for segment: Variant in contact.segments:
		if not _keys(segment, _SEGMENT_KEYS):
			return "segment_schema"
		if typeof(segment.start) != TYPE_FLOAT or typeof(segment.end) != TYPE_FLOAT or segment.start < 0.0 or segment.end > 1.0 or segment.start >= segment.end or not segment.mode is String or not segment.mode in ["stance", "swing"] or not _Math._affine(segment.from) or not _Math._affine(segment.to) or not segment.from_derivative is Transform3D or not segment.to_derivative is Transform3D:
			return "segment_data"
		if signf(segment.from.basis.determinant()) != signf(segment.to.basis.determinant()):
			return "affine_parity_change"
		if previous.is_empty():
			if segment.start != 0.0:
				return "contact_partition"
		elif segment.start != previous.end or not _Math._close(segment.from, previous.to) or not _Math._close(segment.from_derivative, previous.to_derivative):
			return "contact_C1_boundary"
		if segment.mode == "stance" and (segment.from != segment.to or not _Math._zero(segment.from_derivative) or not _Math._zero(segment.to_derivative)):
			return "stance_not_constant"
		previous = segment
	if previous.end != 1.0:
		return "contact_partition"
	return ""
