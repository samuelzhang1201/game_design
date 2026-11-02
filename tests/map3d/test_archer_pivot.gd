extends GutTest
## Contact errors, flattened split joints and raw-boundary failures, not clip certification.

const PATH: String = "res://scripts/map3d/map3d_archer_pivot.gd"
const PARTS: Array[String] = ["thigh_twist", "thigh_stretch", "leg_stretch", "leg_twist", "foot", "toes_01"]
var solver: Script
var _native_json: Dictionary = {}
var _native_binary: PackedByteArray = PackedByteArray()
var _native_accessors: Dictionary = {}


func before_all() -> void:
	if ResourceLoader.exists(PATH):
		solver = load(PATH)
		print("ARCHER_SOLVER_SHA256=" + solver.get_source_code().sha256_text())
		print("ARCHER_TEST_SHA256=" + (get_script() as Script).get_source_code().sha256_text())


func _sample(f: Dictionary) -> Dictionary:
	assert_not_null(solver, "Missing parameterized archer contact solver")
	if solver == null:
		return {"ok": false, "locals": {}, "diagnostics": ["missing"]}
	return solver.sample(f.rest, f.pose, f.op, f.contacts)


func _globals(locals: Dictionary, parents: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var pending: Array = locals.keys()
	while not pending.is_empty():
		var advanced: bool = false
		for name: String in pending.duplicate():
			var parent: String = parents[name]
			if parent.is_empty() or out.has(parent):
				out[name] = locals[name] if parent.is_empty() else out[parent] * locals[name]
				pending.erase(name)
				advanced = true
		assert_true(advanced, "fixture parent graph must be acyclic")
		if not advanced:
			break
	return out


func _fixture() -> Dictionary:
	# Squat: upper sqrt(.2^2+.3^2), lower sqrt(.2^2+.25^2).
	# Both feet can remain planted over +/-180 without moving the pelvis.
	var global: Dictionary = {"root.x": Transform3D(Basis(Vector3.FORWARD, 0.17), Vector3(0, .8, 0)),
		"bow": Transform3D(Basis.IDENTITY, Vector3(.3, .8, -.2))}
	var parents: Dictionary = {"root.x": "", "bow": "root.x"}
	for side: String in ["l", "r"]:
		var x: float = .1 if side == "l" else -.1
		var hip := Vector3(x, .65, 0)
		var knee := Vector3(x, .35, -.2)
		var ankle := Vector3(x, .1, 0)
		var points: Array[Vector3] = [hip, hip.lerp(knee, .5), knee, knee.lerp(ankle, .5), ankle, ankle + Vector3(0, -.03, -.12)]
		for i: int in range(6):
			var name: String = PARTS[i] + "." + side
			global[name] = Transform3D(Basis(Vector3.UP, .23), points[i])
			parents[name] = "root.x" if i in [0, 4] else ("leg_stretch." + side if i == 3 else ("foot." + side if i == 5 else ""))
	var locals: Dictionary = {}
	for name: String in global:
		var parent: String = parents[name]
		locals[name] = global[name] if parent.is_empty() else global[parent].affine_inverse() * global[name]
	return _from_pose(locals, parents)


func _from_pose(locals: Dictionary, parents: Dictionary) -> Dictionary:
	var legs: Dictionary = {}
	var contacts: Dictionary = {}
	var global: Dictionary = _globals(locals, parents)
	for side: String in ["l", "r"]:
		legs[side] = {"knee_limits": Vector2(0, PI), "sole_in_foot": Transform3D(Basis.IDENTITY, Vector3(0, -.025, -.04)), "toe_in_toes": Transform3D.IDENTITY}
		legs[side].rotation_limits = {}
		for part: String in PARTS:
			legs[side].rotation_limits[part] = PI
		var sole: Transform3D = global["foot." + side] * legs[side].sole_in_foot
		var toe: Transform3D = global["toes_01." + side]
		var hip: Vector3 = global["thigh_twist." + side].origin
		var knee: Vector3 = global["leg_stretch." + side].origin
		var axis: Vector3 = (global["foot." + side].origin - hip).normalized()
		var bend: Vector3 = (knee - hip - axis * (knee - hip).dot(axis)).normalized()
		var knee_frame := Basis(bend, axis, bend.cross(axis))
		contacts[side] = {"track": [{"phase": 0.0, "sole": sole, "toe": toe, "knee_frame": knee_frame}, {"phase": 1.0, "sole": sole, "toe": toe, "knee_frame": knee_frame}],
			"support": [{"start": 0.0, "end": 1.0, "sole": sole, "toe": toe}]}
	return {"rest": {"locals": locals.duplicate(true), "parents": parents, "legs": legs}, "pose": locals.duplicate(true),
		"op": {"yaw_rad": 0.0, "turn_rad": 0.0, "duration_s": 1.3, "phase": .5,
			"march_entry_phase": .37, "march_exit_phase": .81, "entry_pose": locals.duplicate(true), "exit_pose": locals.duplicate(true)}, "contacts": contacts}


func _set_turn(f: Dictionary, turn: float, yaw: float = 0.0) -> void:
	f.op.turn_rad = turn
	f.op.yaw_rad = yaw
	var start := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	var end := Transform3D(Basis(Vector3.UP, yaw - turn), Vector3.ZERO)
	var mid := Transform3D(Basis(Vector3.UP, yaw - turn * .5), Vector3.ZERO)
	for side: String in ["l", "r"]:
		var sole: Transform3D = f.contacts[side].track[0].sole
		var toe: Transform3D = f.contacts[side].track[0].toe
		var knee_frame: Basis = f.contacts[side].track[0].knee_frame
		f.contacts[side].track = [{"phase": 0.0, "sole": start * sole, "toe": start * toe, "knee_frame": start.basis * knee_frame},
			{"phase": .1, "sole": start * sole, "toe": start * toe, "knee_frame": start.basis * knee_frame},
			{"phase": .5, "sole": mid * sole, "toe": mid * toe, "knee_frame": mid.basis * knee_frame},
			{"phase": .9, "sole": end * sole, "toe": end * toe, "knee_frame": end.basis * knee_frame},
			{"phase": 1.0, "sole": end * sole, "toe": end * toe, "knee_frame": end.basis * knee_frame}]
		f.contacts[side].support = [{"start": 0.0, "end": .1, "sole": start * sole, "toe": start * toe},
			{"start": .9, "end": 1.0, "sole": end * sole, "toe": end * toe}]


func _check_pose(f: Dictionary, result: Dictionary) -> void:
	assert_true(result.ok, str(result.diagnostics))
	if not result.ok:
		return
	var g: Dictionary = _globals(result.locals, f.rest.parents)
	var rest: Dictionary = _globals(f.rest.locals, f.rest.parents)
	var world := Transform3D(Basis(Vector3.UP, f.op.yaw_rad - f.op.turn_rad * f.op.phase), Vector3.ZERO)
	for side: String in ["l", "r"]:
		var hip: Vector3 = g["thigh_twist." + side].origin
		var knee: Vector3 = g["leg_stretch." + side].origin
		var ankle: Vector3 = g["foot." + side].origin
		assert_almost_eq(hip.distance_to(knee), rest["thigh_twist." + side].origin.distance_to(rest["leg_stretch." + side].origin), .00001)
		assert_almost_eq(knee.distance_to(ankle), rest["leg_stretch." + side].origin.distance_to(rest["foot." + side].origin), .00001)
		var upper_fraction: float = rest["thigh_twist." + side].origin.distance_to(rest["thigh_stretch." + side].origin) / rest["thigh_twist." + side].origin.distance_to(rest["leg_stretch." + side].origin)
		assert_almost_eq(g["thigh_stretch." + side].origin.distance_to(hip.lerp(knee, upper_fraction)), 0.0, .00001)
		var lower_fraction: float = rest["leg_stretch." + side].origin.distance_to(rest["leg_twist." + side].origin) / rest["leg_stretch." + side].origin.distance_to(rest["foot." + side].origin)
		assert_almost_eq(g["leg_twist." + side].origin.distance_to(knee.lerp(ankle, lower_fraction)), 0.0, .00001)
		var sole: Transform3D = world * g["foot." + side] * f.rest.legs[side].sole_in_foot
		var toe: Transform3D = world * g["toes_01." + side]
		var goal: Dictionary = _goal(f.contacts[side].track, f.op.phase)
		assert_almost_eq(sole.origin.distance_to(goal.sole.origin), 0.0, .00001, "swing or support sole")
		assert_almost_eq(toe.origin.distance_to(goal.toe.origin), 0.0, .00001, "swing or support toe")
		assert_true(sole.basis.is_equal_approx(goal.sole.basis), "full sole target orientation/affine")
		assert_true(toe.basis.is_equal_approx(goal.toe.basis), "full toe target orientation/affine")
		var axis: Vector3 = (ankle - hip).normalized()
		var radial: Vector3 = knee - hip - axis * (knee - hip).dot(axis)
		var hint: Vector3 = world.basis.inverse() * goal.knee_frame.x
		assert_almost_eq(radial.normalized().distance_to((hint - axis * hint.dot(axis)).normalized()), 0.0, .00001, "explicit knee branch")
		for part: String in PARTS:
			var name: String = part + "." + side
			assert_true(_gram(result.locals[name].basis).is_equal_approx(_gram(f.pose[name].basis)), "native local affine " + name)
		for anchor: Dictionary in f.contacts[side].support:
			if f.op.phase < anchor.start or f.op.phase > anchor.end:
				continue
			assert_almost_eq(sole.origin.distance_to(anchor.sole.origin), 0.0, .00001)
			assert_almost_eq(toe.origin.distance_to(anchor.toe.origin), 0.0, .00001)
			assert_true(sole.basis.is_equal_approx(anchor.sole.basis), "sole orientation")
			assert_true(toe.basis.is_equal_approx(anchor.toe.basis), "toe orientation")

	assert_eq(result.locals["root.x"], f.pose["root.x"])
	if f.pose.has("bow"):
		assert_eq(result.locals.bow, f.pose.bow)


func test_both_signs_tiny_wrap_and_half_turn_preserve_planted_frames_and_split_spans() -> void:
	for turn: float in [-PI, -PI / 2, -.034906585, -.0000000174532925, 0.0, .0000000174532925, .034906585, PI / 2, PI]:
		var f: Dictionary = _fixture()
		_set_turn(f, turn, TAU - .0174532925)
		for phase: float in [0.0, .01, .25, .5, .99, 1.0]:
			f.op.phase = phase
			_check_pose(f, _sample(f))


func test_zero_turn_reconstructs_authored_affine_locals_without_erasing_twist() -> void:
	var f: Dictionary = _fixture()
	var result: Dictionary = _sample(f)
	_check_pose(f, result)
	if result.ok:
		for name: String in f.pose:
			assert_true((result.locals[name] as Transform3D).is_equal_approx(f.pose[name]), name)


func test_fps_partitions_and_input_immutability() -> void:
	var f: Dictionary = _fixture()
	_set_turn(f, PI / 2)
	var before: Dictionary = f.duplicate(true)
	var expected: Dictionary = _sample(f)
	for fps: int in [24, 30, 60, 144]:
		for frame: int in range(fps):
			f.op.phase = float(frame) / fps
			_sample(f)
		f.op.phase = .5
		assert_eq(_sample(f), expected)
	assert_eq(f, before)
	if expected.ok:
		expected.locals.clear()
		assert_false(f.pose.is_empty(), "output must not alias inputs")


func test_knee_path_remains_continuous_through_half_turn() -> void:
	var f: Dictionary = _fixture()
	_set_turn(f, PI)
	var previous := Vector3.ZERO
	for frame: int in range(101):
		f.op.phase = frame / 100.0
		var result: Dictionary = _sample(f)
		assert_true(result.ok, str(result.diagnostics))
		if not result.ok:
			return
		var p: Vector3 = _globals(result.locals, f.rest.parents)["leg_stretch.l"].origin
		if frame > 0:
			assert_lt(p.distance_to(previous), .02, "no arbitrary pole flip")
		previous = p


func _reject(f: Dictionary) -> void:
	var result: Dictionary = _sample(f)
	assert_false(result.ok)
	assert_eq(result.locals, {}, "failure must not leak a partial limb solve")
	assert_false(result.diagnostics.is_empty())


func test_rejects_unreachable_joint_limit_transition_and_support_drift() -> void:
	var f: Dictionary = _fixture()
	var unreachable: Dictionary = f.contacts.r.track[0].duplicate(true)
	unreachable.phase = .5
	unreachable.sole.origin += Vector3(30, 0, 0)
	unreachable.toe.origin += Vector3(30, 0, 0)
	f.contacts.r.track.insert(1, unreachable)
	f.contacts.r.support = []
	_reject(f)
	f = _fixture()
	f.rest.legs.r.knee_limits = Vector2(0, .01)
	_reject(f)
	f = _fixture()
	f.op.entry_pose["foot.l"].origin += Vector3(.02, 0, 0)
	_reject(f)
	f = _fixture()
	var drift: Dictionary = f.contacts.l.track[0].duplicate(true)
	drift.phase = .4
	drift.sole.origin += Vector3(.001, 0, 0)
	drift.toe.origin += Vector3(.001, 0, 0)
	f.contacts.l.track.insert(1, drift)
	_reject(f)


func test_rejects_malformed_nonfinite_wrong_raw_types_and_parent_cycles() -> void:
	for value: Variant in [null, [], "rest", 1]:
		var f: Dictionary = _fixture()
		f.rest = value
		_reject(f)
	for field: String in ["phase", "turn_rad", "duration_s", "march_entry_phase"]:
		for value: Variant in ["0.5", true, NAN, INF]:
			var f: Dictionary = _fixture()
			f.op[field] = value
			_reject(f)
	for value: Variant in [-.1, 1.1]:
		var f: Dictionary = _fixture()
		f.op.phase = value
		_reject(f)
	var f: Dictionary = _fixture()
	f.rest.parents["root.x"] = "foot.l"
	_reject(f)
	f = _fixture()
	f.pose["bow"] = Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))
	_reject(f)
	f = _fixture()
	f.rest.parents["thigh_stretch.l"] = "thigh_twist.l"
	_reject(f)
	f = _fixture()
	f.contacts.l.track[1].phase = 0.0
	_reject(f)


func _accessor(j: Dictionary, bin: PackedByteArray, index: int) -> Array:
	if _native_accessors.has(index):
		return _native_accessors[index]
	var a: Dictionary = j.accessors[index]
	var view: Dictionary = j.bufferViews[a.bufferView]
	var width: int = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a.type]
	var out: Array = []
	for i: int in range(a.count):
		var row: Array[float] = []
		for k: int in range(width):
			row.append(bin.decode_float(int(view.get("byteOffset", 0)) + int(a.get("byteOffset", 0)) + i * int(view.get("byteStride", width * 4)) + k * 4))
		out.append(row)
	_native_accessors[index] = out
	return out


func _native(phase: float) -> Dictionary:
	# Parse only committed GLB data; no scene, imported skeleton, Blender or cache dependency.
	if _native_json.is_empty():
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://assets/3D/units/archers/archers.glb")
		var json_length: int = bytes.decode_u32(12)
		_native_json = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
		_native_binary = bytes.slice(28 + json_length)
	var j: Dictionary = _native_json
	var bin: PackedByteArray = _native_binary
	var nodes: Array = j.nodes.duplicate(true)
	if phase >= 0:
		for animation: Dictionary in j.animations:
			if animation.name != "MARCH":
				continue
			for channel: Dictionary in animation.channels:
				var sampler: Dictionary = animation.samplers[channel.sampler]
				assert_true(sampler.get("interpolation", "LINEAR") in ["LINEAR", "STEP"])
				var times: Array = _accessor(j, bin, sampler.input)
				var values: Array = _accessor(j, bin, sampler.output)
				var t: float = phase * float(times[-1][0])
				var i: int = 0
				while i + 2 < times.size() and t > float(times[i + 1][0]):
					i += 1
				var w: float = (t - float(times[i][0])) / (float(times[i + 1][0]) - float(times[i][0]))
				if sampler.get("interpolation") == "STEP":
					w = 1.0 if t == float(times[i + 1][0]) else 0.0
				var a: Array = values[i]
				var b: Array = values[i + 1]
				if channel.target.path == "rotation":
					var q: Quaternion = Quaternion(a[0], a[1], a[2], a[3]).normalized().slerp(Quaternion(b[0], b[1], b[2], b[3]).normalized(), w)
					nodes[channel.target.node].rotation = [q.x, q.y, q.z, q.w]
				else:
					nodes[channel.target.node][channel.target.path] = [lerpf(a[0], b[0], w), lerpf(a[1], b[1], w), lerpf(a[2], b[2], w)]
	var locals: Dictionary = {}
	var parents: Dictionary = {}
	for index: int in j.skins[0].joints:
		var node: Dictionary = nodes[index]
		var q: Array = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
		var t: Array = node.get("translation", [0.0, 0.0, 0.0])
		var s: Array = node.get("scale", [1.0, 1.0, 1.0])
		locals[node.name] = Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()) * Basis.from_scale(Vector3(s[0], s[1], s[2])), Vector3(t[0], t[1], t[2]))
		parents[node.name] = ""
		for pi: int in j.skins[0].joints:
			for child: int in nodes[pi].get("children", []):
				if child == index:
					parents[node.name] = nodes[pi].name
	return {"locals": locals, "parents": parents}


func test_actual_native_rest_and_arbitrary_march_phases_preserve_all_nonleg_locals() -> void:
	var native_rest: Dictionary = _native(-1.0)
	for phase: float in [0.0, .137, .37, .81, .999]:
		var native: Dictionary = _native(phase)
		var f: Dictionary = _from_pose(native.locals, native.parents)
		f.rest.locals = native_rest.locals
		f.op.march_entry_phase = phase
		f.op.march_exit_phase = phase
		_set_turn(f, .034906585)
		f.op.phase = .05
		var result: Dictionary = _sample(f)
		_check_pose(f, result)
		if not result.ok:
			continue
		for name: String in f.pose:
			if not _is_leg(name):
				assert_eq(result.locals[name], f.pose[name], name)
		var g: Dictionary = _globals(result.locals, native.parents)
		assert_almost_eq(g["thigh_twist.l"].origin.distance_to(g["leg_stretch.l"].origin), .400250, .00001)
		assert_almost_eq(g["leg_stretch.l"].origin.distance_to(g["foot.l"].origin), .365650, .00001)


func test_rotation_frames_are_continuous_as_well_as_knee_positions() -> void:
	var f: Dictionary = _fixture()
	_set_turn(f, PI)
	var previous: Dictionary = {}
	for frame: int in range(201):
		f.op.phase = frame / 200.0
		var result: Dictionary = _sample(f)
		assert_true(result.ok, str(result.diagnostics))
		if not result.ok:
			return
		var g: Dictionary = _globals(result.locals, f.rest.parents)
		if not previous.is_empty():
			for side: String in ["l", "r"]:
				for part: String in PARTS:
					var name: String = part + "." + side
					var a: Quaternion = (previous[name] as Transform3D).basis.get_rotation_quaternion()
					var b: Quaternion = (g[name] as Transform3D).basis.get_rotation_quaternion()
					assert_lt(a.angle_to(b), .12, name + " no hidden half-turn")
		previous = g


func test_actual_march_entry_and_exit_can_have_different_phases() -> void:
	var rest: Dictionary = _native(-1.0)
	var entry: Dictionary = _native(.137)
	var exit: Dictionary = _native(.81)
	var f: Dictionary = _from_pose(entry.locals, entry.parents)
	f.rest.locals = rest.locals
	f.op.march_entry_phase = .137
	f.op.march_exit_phase = .81
	f.op.exit_pose = exit.locals
	var exit_g: Dictionary = _globals(exit.locals, exit.parents)
	for side: String in ["l", "r"]:
		var last: Dictionary = f.contacts[side].track[1]
		last.sole = exit_g["foot." + side] * f.rest.legs[side].sole_in_foot
		last.toe = exit_g["toes_01." + side]
		var exit_hip: Vector3 = exit_g["thigh_twist." + side].origin
		var exit_axis: Vector3 = (exit_g["foot." + side].origin - exit_hip).normalized()
		var exit_knee: Vector3 = exit_g["leg_stretch." + side].origin - exit_hip
		var exit_bend: Vector3 = (exit_knee - exit_axis * exit_knee.dot(exit_axis)).normalized()
		last.knee_frame = Basis(exit_bend, exit_axis, exit_bend.cross(exit_axis))
		f.contacts[side].support = []
	f.op.phase = 0.0
	var result: Dictionary = _sample(f)
	assert_true(result.ok, str(result.diagnostics))
	if result.ok:
		for name: String in entry.locals:
			if not _is_leg(name):
				assert_eq(result.locals[name], entry.locals[name], name)
		_check_pose(f, result)
	f.op.phase = 1.0
	f.pose = exit.locals.duplicate(true)
	result = _sample(f)
	assert_true(result.ok, str(result.diagnostics))
	if result.ok:
		for name: String in exit.locals:
			if not _is_leg(name):
				assert_eq(result.locals[name], exit.locals[name], name)
		_check_pose(f, result)


func test_contact_schema_rejects_bad_support_missing_frames_and_degenerate_affine() -> void:
	for kind: int in range(7):
		var f: Dictionary = _fixture()
		match kind:
			0: f.contacts.l.support[0].start = -.01
			1: f.contacts.l.support[0].end = "1"
			2: f.contacts.l.track[0].erase("toe")
			3: f.contacts.r.track[0].sole = Transform3D(Basis.from_scale(Vector3(0, 1, 1)), Vector3.ZERO)
			4: f.rest.locals["leg_stretch.r"] = false
			5: f.rest.legs.r.knee_limits = Vector2(NAN, PI)
			6: f.op.duration_s = 0.0
		_reject(f)


func test_local_joint_rotation_limit_is_enforced_on_flattened_bones() -> void:
	var f: Dictionary = _fixture()
	_set_turn(f, PI / 2)
	f.op.phase = .05
	f.rest.legs.l.rotation_limits.foot = .001
	_reject(f)


func test_native_affine_residual_is_preserved_in_split_bone_not_orthonormalized_away() -> void:
	var f: Dictionary = _fixture()
	var affine := Basis(Vector3(1.1, .02, 0), Vector3(0, .9, .03), Vector3(.01, 0, 1.2))
	f.rest.locals["thigh_stretch.l"].basis = affine
	f.pose["thigh_stretch.l"].basis = affine
	f.op.entry_pose = f.pose.duplicate(true)
	f.op.exit_pose = f.pose.duplicate(true)
	var result: Dictionary = _sample(f)
	assert_true(result.ok, str(result.diagnostics))
	if result.ok:
		assert_true((result.locals["thigh_stretch.l"] as Transform3D).basis.is_equal_approx(affine))


func test_antiparallel_segment_alignment_has_no_hidden_half_turn_twist() -> void:
	var f: Dictionary = _fixture()
	var g: Dictionary = _globals(f.pose, f.rest.parents)
	for side: String in ["l", "r"]:
		var hip: Vector3 = g["thigh_twist." + side].origin
		var original: Dictionary = f.contacts[side].track[0]
		var track: Array = []
		for i: int in range(5):
			var rotation := Basis(Vector3.RIGHT, TAU * i / 4.0)
			var about_hip := Transform3D(rotation, hip - rotation * hip)
			track.append({"phase": i / 4.0, "sole": about_hip * original.sole,
				"toe": about_hip * original.toe, "knee_frame": rotation * original.knee_frame})
		f.contacts[side].track = track
		f.contacts[side].support = []
	var previous: Dictionary = {}
	for frame: int in range(201):
		f.op.phase = frame / 200.0
		var result: Dictionary = _sample(f)
		assert_true(result.ok, str(result.diagnostics))
		if not result.ok:
			return
		var solved: Dictionary = _globals(result.locals, f.rest.parents)
		if not previous.is_empty():
			for part: String in PARTS:
				var name: String = part + ".l"
				var a: Quaternion = (previous[name] as Transform3D).basis.get_rotation_quaternion()
				var b: Quaternion = (solved[name] as Transform3D).basis.get_rotation_quaternion()
				assert_lt(a.angle_to(b), .12, "antiparallel " + name)
		previous = solved


func test_undefined_knee_plane_is_rejected_atomically() -> void:
	var f: Dictionary = _fixture()
	for knot: Dictionary in f.contacts.l.track:
		knot.knee_frame = Basis(Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT)
	_reject(f)


func test_finite_but_numerically_unsafe_contact_affine_is_rejected_without_engine_errors() -> void:
	var f: Dictionary = _fixture()
	var foot: Transform3D = _globals(f.pose, f.rest.parents)["foot.l"]
	for knot: Dictionary in f.contacts.l.track:
		knot.sole.basis = Basis.from_scale(Vector3(1e20, 1e-20, 1.0))
		knot.sole.origin = foot.origin + knot.sole.basis * f.rest.legs.l.sole_in_foot.origin
	f.contacts.l.support = []
	var result: Dictionary = _sample(f)
	assert_false(result.ok)
	assert_eq(result.locals, {})
	assert_true(str(result.diagnostics[0]).begins_with("contact:"), "reject unsafe affine before quaternion decomposition")


func test_unknown_leg_prefix_bone_is_not_a_controlled_joint() -> void:
	var f: Dictionary = _fixture()
	var extra := Transform3D(Basis(Vector3.UP, .4), Vector3(.2, 1.0, -.3))
	for locals: Dictionary in [f.rest.locals, f.pose, f.op.entry_pose, f.op.exit_pose]:
		locals["foot.extra"] = extra
	f.rest.parents["foot.extra"] = ""
	var result: Dictionary = _sample(f)
	assert_true(result.ok, str(result.diagnostics))
	if result.ok:
		assert_eq(result.locals["foot.extra"], extra)


func test_contact_targets_cannot_rescale_a_foot_or_toe() -> void:
	for part: String in ["foot", "toes_01"]:
		var f: Dictionary = _fixture()
		var mid: Dictionary = f.contacts.l.track[0].duplicate(true)
		mid.phase = .5
		var source: Dictionary = _globals(f.pose, f.rest.parents)
		var scaled: Transform3D = source[part + ".l"]
		scaled.basis *= 2.0
		if part == "foot":
			mid.sole = scaled * f.rest.legs.l.sole_in_foot
		else:
			mid.toe = scaled * f.rest.legs.l.toe_in_toes
		f.contacts.l.track.insert(1, mid)
		f.contacts.l.support = []
		_reject(f)


func _gram(basis: Basis) -> Basis:
	return basis.transposed() * basis


func test_nonzero_solve_keeps_every_controlled_native_local_affine_residual() -> void:
	var f: Dictionary = _fixture()
	var native := Basis(Vector3(1.1, .02, 0), Vector3(0, .9, .03), Vector3(.01, 0, 1.2))
	f.pose["thigh_stretch.l"].basis = native
	f.rest.locals["thigh_stretch.l"].basis = native
	f.op.entry_pose = f.pose.duplicate(true)
	f.op.exit_pose = f.pose.duplicate(true)
	_set_turn(f, PI / 2)
	f.op.phase = .05
	var result: Dictionary = _sample(f)
	_check_pose(f, result)
	if result.ok:
		for side: String in ["l", "r"]:
			for part: String in PARTS:
				var name: String = part + "." + side
				assert_true(_gram(result.locals[name].basis).is_equal_approx(_gram(f.pose[name].basis)), name)


func _is_leg(name: String) -> bool:
	for part: String in PARTS:
		if name in [part + ".l", part + ".r"]:
			return true
	return false


func _goal(track: Array, phase: float) -> Dictionary:
	# Independent platform interpolation oracle; no production helper calls.
	for i: int in range(1, track.size()):
		var a: Dictionary = track[i - 1]
		var b: Dictionary = track[i]
		if phase <= b.phase:
			var w: float = (phase - a.phase) / (b.phase - a.phase)
			var sole: Transform3D = a.sole if a.sole == b.sole else (a.sole as Transform3D).interpolate_with(b.sole, w)
			var ar: Transform3D = a.sole.affine_inverse() * a.toe
			var br: Transform3D = b.sole.affine_inverse() * b.toe
			var toe: Transform3D = sole * (ar if ar.is_equal_approx(br) else ar.interpolate_with(br, w))
			var frame := Basis((a.knee_frame as Basis).get_rotation_quaternion().slerp((b.knee_frame as Basis).get_rotation_quaternion(), w))
			return {"sole": sole, "toe": toe, "knee_frame": frame}
	return {}


func test_raw_native_counterexample_is_preserved_and_not_repaired_in_the_fixture() -> void:
	var raw: Dictionary = _native(.81)
	var rest: Dictionary = _native(-1.0)
	var g: Dictionary = _globals(raw.locals, raw.parents)
	var r: Dictionary = _globals(rest.locals, rest.parents)
	assert_almost_eq(g["leg_stretch.l"].origin.distance_to(g["foot.l"].origin), .365093371, .000001)
	assert_almost_eq(r["leg_stretch.l"].origin.distance_to(r["foot.l"].origin), .365650014, .000001)
	assert_gt(absf(g["leg_stretch.l"].origin.distance_to(g["foot.l"].origin) - r["leg_stretch.l"].origin.distance_to(r["foot.l"].origin)), .0005)


func _native_case(phase: float) -> Dictionary:
	var raw: Dictionary = _native(phase)
	var f: Dictionary = _from_pose(raw.locals, raw.parents)
	f.rest.locals = _native(-1.0).locals
	f.op.march_entry_phase = phase
	f.op.march_exit_phase = phase
	return f


func test_dense_raw_native_phases_solve_rest_spans_split_fractions_and_full_targets() -> void:
	for i: int in range(127):
		var phase: float = (i + .37) / 127.0
		var f: Dictionary = _native_case(phase)
		var unchanged: Dictionary = f.duplicate(true)
		var result: Dictionary = _sample(f)
		_check_pose(f, result)
		assert_eq(f, unchanged, "raw native input must not be repaired/mutated")
		if result.ok:
			for name: String in f.pose:
				if not _is_leg(name):
					assert_eq(result.locals[name], f.pose[name], name)


func _compare_full_leg_pose(a: Dictionary, b: Dictionary, parents: Dictionary, bound: float) -> void:
	var ag: Dictionary = _globals(a, parents)
	var bg: Dictionary = _globals(b, parents)
	for side: String in ["l", "r"]:
		for part: String in PARTS:
			var name: String = part + "." + side
			assert_lt(ag[name].origin.distance_to(bg[name].origin), bound, "origin " + name)
			for axis: int in range(3):
				assert_lt((ag[name].basis as Basis)[axis].distance_to((bg[name].basis as Basis)[axis]), bound, "full rotation " + name)


func test_native_keyframe_and_loop_neighbors_have_no_fixed_position_or_rotation_jump() -> void:
	for keyframe: int in range(35):
		for epsilon: float in [.0001, .000001]:
			var phase: float = keyframe / 35.0
			var left: Dictionary = _native_case(fposmod(phase - epsilon, 1.0))
			var right: Dictionary = _native_case(fposmod(phase + epsilon, 1.0))
			var a: Dictionary = _sample(left)
			var b: Dictionary = _sample(right)
			assert_true(a.ok, str(a.diagnostics))
			assert_true(b.ok, str(b.diagnostics))
			if a.ok and b.ok:
				_compare_full_leg_pose(a.locals, b.locals, left.rest.parents, epsilon * 200.0 + .00002)


func test_moving_near_straight_raw_knee_reference_has_continuous_full_bone_frames() -> void:
	var f: Dictionary = _fixture()
	var global: Dictionary = _globals(f.pose, f.rest.parents)
	var previous: Dictionary = {}
	for frame: int in range(101):
		var phase: float = frame / 100.0
		var raw: Dictionary = global.duplicate(true)
		for side: String in ["l", "r"]:
			var hip: Vector3 = raw["thigh_twist." + side].origin
			var ankle: Vector3 = raw["foot." + side].origin
			var knee: Vector3 = hip.lerp(ankle, .5) + Vector3(0, 0, lerpf(-.01, .01, phase))
			raw["leg_stretch." + side].origin = knee
			raw["thigh_stretch." + side].origin = hip.lerp(knee, .5)
			raw["leg_twist." + side].origin = knee.lerp(ankle, .5)
		var locals: Dictionary = {}
		for name: String in raw:
			var parent: String = f.rest.parents[name]
			locals[name] = raw[name] if parent.is_empty() else raw[parent].affine_inverse() * raw[name]
		f.pose = locals
		f.op.entry_pose = locals.duplicate(true)
		f.op.exit_pose = locals.duplicate(true)
		f.op.phase = phase
		var result: Dictionary = _sample(f)
		_check_pose(f, result)
		if result.ok:
			if not previous.is_empty():
				_compare_full_leg_pose(previous, result.locals, f.rest.parents, .01)
			previous = result.locals


func _transition_case(entry: float, exit: float, turn: float) -> Dictionary:
	var f: Dictionary = _native_case(entry)
	var end: Dictionary = _native_case(exit)
	f.op.yaw_rad = TAU - .0174532925
	f.op.turn_rad = turn
	f.op.exit_pose = end.pose
	f.op.march_exit_phase = exit
	var first := Transform3D(Basis(Vector3.UP, f.op.yaw_rad), Vector3.ZERO)
	var last := Transform3D(Basis(Vector3.UP, f.op.yaw_rad - turn), Vector3.ZERO)
	for side: String in ["l", "r"]:
		var a: Dictionary = f.contacts[side].track[0]
		var b: Dictionary = end.contacts[side].track[0]
		f.contacts[side].track = [{"phase": 0.0, "sole": first * a.sole, "toe": first * a.toe, "knee_frame": first.basis * a.knee_frame},
			{"phase": 1.0, "sole": last * b.sole, "toe": last * b.toe, "knee_frame": last.basis * b.knee_frame}]
		# Explicit swing trajectory: native grounded-contact certification is separate.
		f.contacts[side].support = []
	return f


func test_all_turn_signs_and_distinct_native_phases_share_canonical_full_endpoints_and_neighbors() -> void:
	for phases: Vector2 in [Vector2(.137, .81), Vector2(.999, .37)]:
		for turn: float in [-PI, -PI / 2, -.034906585, -.0000000174532925, 0.0, .0000000174532925, .034906585, PI / 2, PI]:
			var f: Dictionary = _transition_case(phases.x, phases.y, turn)
			for endpoint: int in range(2):
				var native_phase: float = phases.x if endpoint == 0 else phases.y
				f.pose = f.op.entry_pose if endpoint == 0 else f.op.exit_pose
				f.op.phase = float(endpoint)
				var result: Dictionary = _sample(f)
				_check_pose(f, result)
				var canonical: Dictionary = _native_case(native_phase)
				_set_turn(canonical, 0.0, f.op.yaw_rad - turn * endpoint)
				canonical.op.phase = float(endpoint)
				var reference: Dictionary = _sample(canonical)
				_check_pose(canonical, reference)
				if result.ok and reference.ok:
					_compare_full_leg_pose(result.locals, reference.locals, f.rest.parents, .00001)
				for epsilon: float in [.0001, .000001]:
					var neighbor_phase: float = fposmod(native_phase + (-epsilon if endpoint == 0 else epsilon), 1.0)
					var march: Dictionary = _native_case(neighbor_phase)
					_set_turn(march, 0.0, f.op.yaw_rad - turn * endpoint)
					var outside: Dictionary = _sample(march)
					f.op.phase = epsilon if endpoint == 0 else 1.0 - epsilon
					var moving: float = fposmod(phases.x + fposmod(phases.y - phases.x, 1.0) * f.op.phase, 1.0)
					f.pose = _native(moving).locals
					var inside: Dictionary = _sample(f)
					assert_true(outside.ok, str(outside.diagnostics))
					assert_true(inside.ok, str(inside.diagnostics))
					if outside.ok and inside.ok:
						_check_pose(f, inside)
						_compare_full_leg_pose(outside.locals, inside.locals, f.rest.parents, epsilon * 200.0 + .00002)


func test_nonzero_contact_solve_retains_nonuniform_foot_and_toe_affine_without_compensation() -> void:
	var f: Dictionary = _fixture()
	f.pose["foot.l"].basis *= Basis(Vector3(1.1, .02, 0), Vector3(0, .9, .03), Vector3(.01, 0, 1.2))
	f = _from_pose(f.pose, f.rest.parents)
	_set_turn(f, PI / 2)
	f.op.phase = .05
	var result: Dictionary = _sample(f)
	_check_pose(f, result)
	if result.ok:
		assert_true(_gram(result.locals["foot.l"].basis).is_equal_approx(_gram(f.pose["foot.l"].basis)))
		assert_true(_gram(result.locals["toes_01.l"].basis).is_equal_approx(_gram(f.pose["toes_01.l"].basis)))


func test_authored_axial_twist_survives_nonzero_solve_in_material_coordinates() -> void:
	var f: Dictionary = _fixture()
	var raw: Dictionary = _globals(f.pose, f.rest.parents)
	for side: String in ["l", "r"]:
		var upper: Vector3 = (raw["leg_stretch." + side].origin - raw["thigh_twist." + side].origin).normalized()
		var lower: Vector3 = (raw["foot." + side].origin - raw["leg_stretch." + side].origin).normalized()
		for part: String in ["thigh_twist", "thigh_stretch"]:
			raw[part + "." + side].basis = Basis(upper, .7) * raw[part + "." + side].basis
		for part: String in ["leg_stretch", "leg_twist"]:
			raw[part + "." + side].basis = Basis(lower, -.4) * raw[part + "." + side].basis
	for name: String in raw:
		var parent: String = f.rest.parents[name]
		f.pose[name] = raw[name] if parent.is_empty() else raw[parent].affine_inverse() * raw[name]
	f.op.entry_pose = f.pose.duplicate(true)
	f.op.exit_pose = f.pose.duplicate(true)
	_set_turn(f, PI / 2)
	f.op.phase = .05
	var result: Dictionary = _sample(f)
	_check_pose(f, result)
	if not result.ok:
		return
	var solved: Dictionary = _globals(result.locals, f.rest.parents)
	var rest: Dictionary = _globals(f.rest.locals, f.rest.parents)
	for side: String in ["l", "r"]:
		var rest_upper: Vector3 = rest["leg_stretch." + side].origin - rest["thigh_twist." + side].origin
		var rest_lower: Vector3 = rest["foot." + side].origin - rest["leg_stretch." + side].origin
		var source_normal: Vector3 = rest_upper.cross(rest_lower).normalized()
		var target_upper: Vector3 = solved["leg_stretch." + side].origin - solved["thigh_twist." + side].origin
		var target_lower: Vector3 = solved["foot." + side].origin - solved["leg_stretch." + side].origin
		var target_normal: Vector3 = target_upper.cross(target_lower).normalized()
		for pair: Array in [["thigh_twist", "thigh_stretch", "thigh_twist", "leg_stretch"], ["leg_stretch", "leg_twist", "leg_stretch", "foot"]]:
			var old_direction: Vector3 = (raw[pair[3] + "." + side].origin - raw[pair[2] + "." + side].origin).normalized()
			var new_direction: Vector3 = (solved[pair[3] + "." + side].origin - solved[pair[2] + "." + side].origin).normalized()
			for part: String in [pair[0], pair[1]]:
				var old_basis: Basis = raw[part + "." + side].basis
				var new_basis: Basis = solved[part + "." + side].basis
				assert_almost_eq((old_basis.inverse() * old_direction).distance_to(new_basis.inverse() * new_direction), 0.0, .00001, "material segment axis " + part)
				assert_almost_eq((old_basis.inverse() * source_normal).distance_to(new_basis.inverse() * target_normal), 0.0, .00001, "authored axial twist " + part)


func test_invalid_rest_split_and_degenerate_raw_joint_directions_reject_atomically() -> void:
	var f: Dictionary = _fixture()
	f.rest.locals["thigh_stretch.l"].origin += Vector3(.01, 0, 0)
	_reject(f)
	f = _fixture()
	var raw: Dictionary = _globals(f.pose, f.rest.parents)
	f.pose["leg_stretch.r"].origin = raw["thigh_twist.r"].origin
	_reject(f)


func _boundary_fixture() -> Dictionary:
	var rest: Dictionary = {"locals": {"a": Transform3D.IDENTITY, "b": Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))}, "parents": {"a": "", "b": ""}, "segments": [{"a": "a", "b": "b"}]}
	var raw: Dictionary = {"a": Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), "b": Transform3D(Basis.IDENTITY, Vector3(4, 0, 0))}
	var meshes: Dictionary = {"body": {"binds": [{"bone": "a", "pose": Transform3D.IDENTITY}, {"bone": "b", "pose": Transform3D.IDENTITY}],
		"vertices": [{"position": Vector3(1, 0, 0), "influences": [{"bind": 0, "weight": .25}, {"bind": 1, "weight": .5}]}], "sole_indices": [0]}}
	return {"rest": rest, "raw": raw, "candidate": raw.duplicate(true), "meshes": meshes, "ground": {"origin": Vector3.ZERO, "normal": Vector3.UP}, "model_from_native": Transform3D.IDENTITY}


func _measure_boundary(f: Dictionary) -> Dictionary:
	if not solver.has_method("measure_boundary"):
		assert_true(false, "missing pure native-boundary measurement")
		return {"ok": false}
	return solver.measure_boundary(f.rest, f.raw, f.candidate, f.meshes, f.model_from_native, f.ground)


func test_boundary_lbs_preserves_raw_weights_and_separate_ground_components() -> void:
	var f: Dictionary = _boundary_fixture()
	f.candidate.a.origin += Vector3(0, 4, 3)
	f.candidate.b.origin += Vector3(0, 4, 3)
	var unchanged: Dictionary = f.duplicate(true)
	var result: Dictionary = _measure_boundary(f)
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(f, unchanged)
	# (1+2)*.25 + (1+4)*.5 = 3.25, never divide by the .75 weight sum.
	assert_eq(result.meshes.body.raw_points[0], Vector3(3.25, 0, 0))
	assert_almost_eq(result.body_displacement_m, 3.75, 0.000001)
	assert_almost_eq(result.sole_displacement_m, 3.75, 0.000001)
	assert_almost_eq(result.sole_normal_displacement_m, 3.0, 0.000001)
	assert_almost_eq(result.sole_tangent_displacement_m, 2.25, 0.000001)
	assert_eq(result.physical_error_status, "unknown")
	assert_false(result.has("certified"))


func test_boundary_error_conditions_are_necessary_only_and_metric_specific() -> void:
	if not solver.has_method("boundary_condition"):
		assert_true(false, "missing finite-error necessary condition")
		return
	var j: float = Vector3(3e-6, 4e-6, 0).length()
	assert_eq(solver.boundary_condition(j, 2e-6, false).status, "excluded")
	assert_eq(solver.boundary_condition(j, 3e-6, false).status, "not_excluded")
	assert_eq(solver.boundary_condition(j, 3e-6, true).status, "excluded")
	assert_eq(solver.boundary_condition(j, 6e-6, true).status, "not_excluded")
	assert_false(solver.boundary_condition(j, -1.0, false).ok)


func test_boundary_full_affine_model_frame_is_applied_after_raw_lbs() -> void:
	var f: Dictionary = _boundary_fixture()
	f.model_from_native = Transform3D(Basis(Vector3(2, 0, 0), Vector3(.3, 1, 0), Vector3(0, .2, 1)), Vector3(10, 20, 30))
	var result: Dictionary = _measure_boundary(f)
	assert_true(result.ok)
	if result.ok:
		assert_eq(result.meshes.body.raw_points[0], Vector3(16.5, 20, 30))
		assert_almost_eq(result.body_displacement_m, 0.0, 1e-8)


func test_boundary_malformed_input_rejects_atomically_without_metrics() -> void:
	for kind: int in range(14):
		var f: Dictionary = _boundary_fixture()
		match kind:
			0: f.rest.parents.a = "b"; f.rest.parents.b = "a"
			1: f.raw.erase("b")
			2: f.candidate.a.origin.x = NAN
			3: f.meshes.body.binds[0].bone = "missing"
			4: f.meshes.body.vertices[0].influences[0].weight = -.25
			5: f.meshes.body.vertices[0].influences[0].weight = INF
			6: f.meshes.body.vertices[0].influences[0].bind = 2
			7: f.meshes.body.sole_indices = [1]
			8: f.meshes.body.binds[0].pose.basis.x = Vector3.ZERO
			9: f.ground.normal = Vector3(0, 2, 0)
			10: f.rest.segments[0].b = "missing"
			11: f.model_from_native.origin.y = INF
			12: f.meshes.body.vertices[0].position = Vector3(NAN, 0, 0)
			13:
				f.model_from_native.origin.x = 1e38
				f.ground.origin.x = -3e38
				f.ground.normal = Vector3.RIGHT
		# var_to_bytes also compares NaN without NaN != NaN ambiguity.
		var before: PackedByteArray = var_to_bytes(f)
		var result: Dictionary = _measure_boundary(f)
		assert_false(result.ok, str(kind))
		assert_false(result.has("body_displacement_m"), "no partial metrics " + str(kind))
		assert_eq(var_to_bytes(f), before, "no repaired inputs " + str(kind))


func _boundary_encode(value: Variant) -> Variant:
	if value is Transform3D:
		var t: Transform3D = value
		return {"$t": [[t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x], [t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y], [t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z], [0.0, 0.0, 0.0, 1.0]]}
	if value is Vector3:
		return {"$v3": [value.x, value.y, value.z]}
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value:
			out[key] = _boundary_encode(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_boundary_encode(item))
		return out
	return value


func _played_boundary_pose(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, phase: float) -> Dictionary:
	player.stop()
	skeleton.reset_bone_poses()
	player.play(clip)
	player.seek(player.get_animation(clip).length * phase, true)
	skeleton.force_update_all_bone_transforms()
	var locals: Dictionary = {}
	var globals: Dictionary = {}
	for i: int in range(skeleton.get_bone_count()):
		var name: String = skeleton.get_bone_name(i)
		locals[name] = skeleton.get_bone_pose(i)
		globals[name] = skeleton.get_bone_global_pose(i)
	return {"clip": clip, "phase": phase, "time_s": player.get_animation(clip).length * phase, "kind": "raw_animation_player", "locals": locals, "globals": globals}


func _imported_boundary_meshes(scene: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var meshes: Dictionary = {}
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		assert_not_null(mesh.skin, str(mesh.name) + " actual Skin")
		if mesh.skin == null:
			continue
		assert_eq(mesh.get_node(mesh.skeleton), skeleton)
		var binds: Array = []
		for i: int in range(mesh.skin.get_bind_count()):
			var name: String = mesh.skin.get_bind_name(i)
			if name.is_empty():
				name = skeleton.get_bone_name(mesh.skin.get_bind_bone(i))
			binds.append({"bone": name, "pose": mesh.skin.get_bind_pose(i)})
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var palette: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var width: int = palette.size() / positions.size()
			assert_true(width == 4 or width == 8)
			var vertices: Array = []
			var soles: Array = []
			for v: int in range(positions.size()):
				var influences: Array = []
				var footwear: float = 0.0
				for j: int in range(width):
					var bind: int = palette[v * width + j]
					var weight: float = weights[v * width + j]
					influences.append({"bind": bind, "weight": weight})
					if binds[bind].bone in ["foot.l", "foot.r", "toes_01.l", "toes_01.r"]:
						footwear += weight
				vertices.append({"position": positions[v], "influences": influences})
				# Frozen native sole triangles (body surface 0), all raw influences retained.
				if str(mesh.name) == "archers" and surface == 0 and v in [25967, 49673, 25970, 17151, 31276, 17148]:
					assert_gt(footwear, .8, "fixed shoe material membership")
					soles.append(v)
			meshes[str(mesh.name) + "/" + str(surface)] = {"binds": binds, "vertices": vertices, "sole_indices": soles}
	return meshes


func test_real_imported_native_boundary_and_capture_provenance() -> void:
	var scene: Node3D = (load("res://scenes/models/units/archers.tscn") as PackedScene).instantiate()
	add_child(scene)
	var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var rest: Dictionary = {"locals": {}, "parents": {}, "segments": []}
	for i: int in range(skeleton.get_bone_count()):
		var name: String = skeleton.get_bone_name(i)
		rest.locals[name] = skeleton.get_bone_rest(i)
		var parent: int = skeleton.get_bone_parent(i)
		rest.parents[name] = "" if parent == -1 else str(skeleton.get_bone_name(parent))
	for side: String in ["l", "r"]:
		rest.segments.append({"a": "thigh_twist." + side, "b": "leg_stretch." + side, "split": "thigh_stretch." + side})
		rest.segments.append({"a": "leg_stretch." + side, "b": "foot." + side, "split": "leg_twist." + side})
	var model_from_native: Transform3D = scene.global_transform.affine_inverse() * skeleton.global_transform
	var meshes: Dictionary = _imported_boundary_meshes(scene, skeleton)
	assert_gte(meshes.size(), 4, "body and every equipped Skin")
	var phases: Array[float] = [0.0, .137, .81, .000001, .999999]
	var march: Animation = player.get_animation("MARCH")
	for track: int in range(march.get_track_count()):
		if march.track_get_key_count(track) > 2:
			var key_phase: float = march.track_get_key_time(track, 1) / march.length
			phases.append(key_phase - 0.000001)
			phases.append(key_phase)
			phases.append(key_phase + 0.000001)
			break
	var samples: Array = []
	for phase: float in phases:
		var raw: Dictionary = _played_boundary_pose(player, skeleton, "MARCH", phase)
		var rebuilt: Dictionary = _globals(raw.locals, rest.parents)
		for name: String in rebuilt:
			_matrix_boundary(rebuilt[name], raw.globals[name], "native global " + name)
		samples.append(raw)
	var raw: Dictionary = samples[0].locals
	var f: Dictionary = {"rest": rest, "raw": raw, "candidate": raw, "meshes": meshes, "model_from_native": model_from_native, "ground": {"origin": Vector3.ZERO, "normal": Vector3.UP}}
	var identity: Dictionary = _measure_boundary(f)
	assert_true(identity.ok, str(identity.get("diagnostics")))
	if identity.ok:
		assert_eq(identity.body_displacement_m, 0.0)
	var boundary_measurements: Array = []
	var pivot_samples: Array = []
	for clip: String in ["PIVOT_LEFT", "PIVOT_RIGHT"]:
		for endpoint: float in [0.0, 1.0]:
			var candidate: Dictionary = _played_boundary_pose(player, skeleton, clip, endpoint)
			pivot_samples.append(candidate)
			# Clips contain local poses; heading belongs to the external actor, not these bones.
			f.candidate = candidate.locals
			var result: Dictionary = _measure_boundary(f)
			assert_true(result.ok, str(result.get("diagnostics")))
			if result.ok:
				assert_gt(result.body_displacement_m, 0.0001, "installed raw-to-pivot seam still exists")
				assert_gt(result.sole_displacement_m, 0.00001, "fixed material seam still exists")
				for mesh_name: String in result.meshes:
					var measured: Dictionary = result.meshes[mesh_name]
					boundary_measurements.append({"clip": clip, "phase": endpoint, "mesh": mesh_name, "max_displacement_m": measured.max_displacement_m,
						"raw_sole_heights_m": measured.raw_sole_heights_m, "candidate_sole_heights_m": measured.candidate_sole_heights_m})
				print("NATIVE_BOUNDARY ", clip, " ", endpoint, " body_m=", result.body_displacement_m, " sole_m=", result.sole_displacement_m, " normal_m=", result.sole_normal_displacement_m, " tangent_m=", result.sole_tangent_displacement_m)
	assert_eq(boundary_measurements.size(), 16, "both endpoints, both clips, all four body/gear meshes retained")
	var output: String = OS.get_environment("ARCHER_BOUNDARY_CAPTURE")
	if not output.is_empty():
		var digests: Dictionary = {}
		for name: String in DirAccess.get_files_at("res://assets/3D/units/archers"):
			var path: String = "assets/3D/units/archers/" + name
			digests[path] = FileAccess.get_sha256("res://" + path)
		for path: String in ["scenes/models/units/archers.tscn", "tools/units3d/archer_arp/pivot_import.gd"]:
			digests[path] = FileAccess.get_sha256("res://" + path)
		var source_rest: Dictionary = _native(-1.0)
		var source_from_native: Transform3D = source_rest.locals["root.x"] * rest.locals["root.x"].affine_inverse()
		var capture: Dictionary = {"schema": "archer-native-boundary-v1", "kind": "raw_animation_player", "godot": Engine.get_version_info(), "resource_sha256": digests, "capture_script_sha256": FileAccess.get_sha256("res://tests/map3d/test_archer_pivot.gd"),
			"rest": rest, "model_from_native": model_from_native, "source_from_native": source_from_native, "native_from_source": source_from_native.affine_inverse(),
			"clip": "MARCH", "clip_length_s": march.length, "samples": samples, "meshes": meshes, "pivot_samples": pivot_samples, "boundary_measurements": boundary_measurements}
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		assert_not_null(file)
		if file != null:
			file.store_string(JSON.stringify(_boundary_encode(capture)))
			file.close()
			print("NATIVE_CAPTURE_SHA256=", FileAccess.get_sha256(output))
	remove_child(scene)
	scene.free()


func _matrix_boundary(a: Transform3D, b: Transform3D, label: String) -> void:
	assert_lt(a.origin.distance_to(b.origin), .00001, label)
	for axis: int in range(3):
		assert_lt(a.basis[axis].distance_to(b.basis[axis]), .00001, label + " affine")


func test_boundary_reports_native_bone_segment_split_and_affine_residuals() -> void:
	var f: Dictionary = _boundary_fixture()
	f.rest.locals["split"] = Transform3D(Basis.IDENTITY, Vector3(0, .5, 0))
	f.rest.parents["split"] = "a"
	f.rest.segments[0].split = "split"
	f.raw = f.rest.locals.duplicate(true)
	f.candidate = f.raw.duplicate(true)
	f.candidate.b.origin.y = 2.0
	f.candidate.split.origin.x = 3.0
	f.candidate.a.basis.x *= 2.0
	var result: Dictionary = _measure_boundary(f)
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.bones.a.local_gram_residual, 3.0)
	assert_eq(result.bones.a.raw_rest_gram_residual, 0.0)
	assert_eq(result.bones.a.candidate_rest_gram_residual, 3.0)
	assert_almost_eq(result.segments[0].candidate_length_residual_native_m, 1.0, .000001)
	assert_almost_eq(result.segments[0].raw_length_residual_native_m, 0.0, .000001)
	assert_almost_eq(result.segments[0].raw_split_residual_native_m, 0.0, .000001)
	# Scaled parent puts the split at (6,.5,0), target fraction at (0,1,0).
	assert_almost_eq(result.segments[0].candidate_split_residual_native_m, sqrt(36.25), .000001)
