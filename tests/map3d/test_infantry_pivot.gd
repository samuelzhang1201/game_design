extends GutTest

const Pivot = preload("res://scripts/map3d/map3d_infantry_pivot.gd")

func _interval(kind: String, t0: float, t1: float, a: Transform3D, b: Transform3D) -> Dictionary:
	return {"t0": t0, "t1": t1, "kind": kind, "point_from": a.origin, "point_to": b.origin,
		"sole_from": a.basis, "sole_to": b.basis, "toe_from": a.basis, "toe_to": b.basis}

func _fixture() -> Dictionary:
	var bones: Array = [{"name": "body", "parent": "", "local": Transform3D.IDENTITY}]
	var legs: Array = []
	var pose: Dictionary = {"body": Transform3D.IDENTITY}
	var contacts: Dictionary = {"march_entry_phase": 0.137, "march_exit_phase": 0.823, "legs": {}}
	for side: String in ["l", "r"]:
		var x: float = -0.2 if side == "l" else 0.2
		var parent: String = "body"
		var offsets: Array[Vector3] = [Vector3(x, 1.6, 0), Vector3(0, -0.8, 0.6),
			Vector3(0, -0.8, -0.6), Vector3(0, 0, 0.2)]
		var names: Array[String] = []
		for i: int in range(4):
			var name: String = side + str(i)
			var local: Transform3D = Transform3D(Basis.IDENTITY, offsets[i])
			bones.append({"name": name, "parent": parent, "local": local})
			pose[name] = local
			names.append(name)
			parent = name
		legs.append({"hip": names[0], "knee": names[1], "ankle": names[2], "toe": names[3],
			"pole": Vector3.FORWARD * -1.0, "min_knee_rad": 0.0, "max_knee_rad": PI, "followers": {}})
		var anchor: Transform3D = Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
		contacts.legs[names[0]] = {"sole_bind": Transform3D.IDENTITY, "toe_bind": Transform3D.IDENTITY,
			"intervals": [_interval("stance", 0.0, 1.0, anchor, anchor)]}
	bones.append({"name": "gear", "parent": "body", "local": Transform3D.IDENTITY})
	pose.gear = Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 2, 0.1))
	return {"rest": {"bones": bones, "legs": legs}, "pose": pose, "contacts": contacts,
		"op": {"duration_q": 200000, "phase": 0.5, "yaw0_udeg": 0,
			"turn_udeg": 90000000, "current_yaw_udeg": 45000000.0,
			"march_entry_phase": 0.137, "march_exit_phase": 0.823}}

func _sample(f: Dictionary) -> Dictionary:
	return Pivot.sample(f.rest, f.pose, f.op, f.contacts)

func _globals(rest: Dictionary, pose: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for bone: Dictionary in rest.bones:
		result[bone.name] = pose[bone.name] if bone.parent == "" else result[bone.parent] * pose[bone.name]
	return result

func test_hand_computed_knee_and_unchanged_upper_body() -> void:
	var f: Dictionary = _fixture()
	f.op.phase = 0.0
	f.op.current_yaw_udeg = 0.0
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if not result.ok:
		return
	var global: Dictionary = _globals(f.rest, result.pose)
	assert_almost_eq(global.l1.origin, Vector3(-0.2, 0.8, 0.6), Vector3.ONE * 0.00001)
	assert_almost_eq(global.l2.origin, Vector3(-0.2, 0, 0), Vector3.ONE * 0.00001)
	assert_almost_eq(global.l3.origin, Vector3(-0.2, 0, 0.2), Vector3.ONE * 0.00001)
	assert_almost_eq(result.contacts.l0.knee_rad, acos(0.28), 0.00001)
	assert_eq(result.pose.gear, f.pose.gear)
	assert_eq(result.pose.body, f.pose.body)

func _set_phase(f: Dictionary, phase: float) -> void:
	f.op.phase = phase
	f.op.current_yaw_udeg = fposmod(float(f.op.yaw0_udeg) + float(f.op.turn_udeg) * phase, 360000000.0)

func _check_segment_axes(rest: Dictionary, after: Dictionary) -> void:
	var pose: Dictionary = {}
	for bone: Dictionary in rest.bones:
		pose[bone.name] = bone.local
	var bind: Dictionary = _globals(rest, pose)
	for leg: Dictionary in rest.legs:
		for pair: Array in [[leg.hip, leg.knee], [leg.knee, leg.ankle], [leg.ankle, leg.toe]]:
			var skin_endpoint: Vector3 = after[pair[0]] * bind[pair[0]].affine_inverse() * bind[pair[1]].origin
			assert_almost_eq(skin_endpoint, after[pair[1]].origin, Vector3.ONE * 0.00001)

func _check_contact(f: Dictionary, result: Dictionary) -> void:
	assert_true(result.ok, result.reason)
	if not result.ok:
		return
	var global: Dictionary = _globals(f.rest, result.pose)
	_check_segment_axes(f.rest, global)
	var rotation: Basis = Basis(Vector3.UP, -deg_to_rad(float(f.op.turn_udeg) * f.op.phase / 1000000.0))
	for leg: Dictionary in f.rest.legs:
		var d: Dictionary = result.contacts[leg.hip]
		var expected: Transform3D = d.target_sole
		var sole: Transform3D = d.sole
		assert_almost_eq(sole.origin, expected.origin, Vector3.ONE * 0.00001)
		assert_almost_eq(sole.basis.y, expected.basis.y, Vector3.ONE * 0.00001)
		assert_almost_eq(d.toe.basis.y, expected.basis.y, Vector3.ONE * 0.00001)
		assert_almost_eq(global[leg.hip].origin.distance_to(global[leg.knee].origin), 1.0, 0.00001)
		assert_almost_eq(global[leg.knee].origin.distance_to(global[leg.ankle].origin), 1.0, 0.00001)
		assert_almost_eq(global[leg.ankle].origin.distance_to(global[leg.toe].origin), 0.2, 0.00001)
		assert_almost_eq(rotation * sole.origin, Vector3(-0.2 if leg.hip == "l0" else 0.2, 0, 0), Vector3.ONE * 0.00001)
	assert_eq(result.pose.gear, f.pose.gear)
	assert_eq(result.pose.body, f.pose.body)

func test_both_signs_microdegree_tie_wrap_and_march_phases() -> void:
	for turn: int in [1, -1, 2000000, -2000000, 90000000, -90000000, 179999999, -179999999, 180000000]:
		for phase: float in [0.0, 0.001, 0.137, 0.5, 0.823, 0.999, 1.0]:
			var f: Dictionary = _fixture()
			f.op.yaw0_udeg = 359000000
			f.op.turn_udeg = turn
			_set_phase(f, phase)
			_check_contact(f, _sample(f))

func test_bind_offsets_rotated_sole_and_toe_orientation() -> void:
	var f: Dictionary = _fixture()
	f.contacts.legs.l0.sole_bind = Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(0, -0.03, 0.04))
	f.contacts.legs.l0.toe_bind = Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3(0, -0.02, 0.1))
	var anchor: Transform3D = Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(-0.2, -0.03, 0.04))
	f.contacts.legs.l0.intervals[0] = _interval("stance", 0.0, 1.0, anchor, anchor)
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if not result.ok:
		return
	var rotation: Basis = Basis(Vector3.UP, -deg_to_rad(45.0))
	assert_almost_eq(rotation * result.contacts.l0.sole.origin, anchor.origin, Vector3.ONE * 0.00001)
	assert_almost_eq(rotation * result.contacts.l0.sole.basis.y, anchor.basis.y, Vector3.ONE * 0.00001)
	assert_almost_eq(result.contacts.l0.toe.basis.y, result.contacts.l0.sole.basis.y, Vector3.ONE * 0.00001)
	var global: Dictionary = _globals(f.rest, result.pose)
	assert_almost_eq(global.l2.origin.distance_to(global.l3.origin), 0.2, 0.00001)

func test_swing_interpolation_and_next_interval_boundary() -> void:
	var f: Dictionary = _fixture()
	var a: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, 0, 0))
	var b: Transform3D = Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(-0.1, 0.1, 0.1))
	f.contacts.legs.l0.intervals = [
		_interval("stance", 0.0, 0.25, a, a),
		_interval("swing", 0.25, 0.75, a, b),
		_interval("stance", 0.75, 1.0, b, b)]
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if not result.ok:
		return
	var rotation: Basis = Basis(Vector3.UP, deg_to_rad(45.0))
	assert_almost_eq(result.contacts.l0.sole.origin, rotation * Vector3(-0.15, 0.05, 0.05), Vector3.ONE * 0.00001)
	assert_almost_eq(result.contacts.l0.sole.basis.y, rotation * Basis(Vector3.RIGHT, 0.1).y, Vector3.ONE * 0.00001)
	for phase: float in [0.25, 0.75, 1.0]:
		_set_phase(f, phase)
		result = _sample(f)
		assert_true(result.ok, result.reason)
		if result.ok:
			assert_eq(result.contacts.l0.kind, "swing" if phase == 0.25 else "stance")

func _reject(f: Dictionary, label: String) -> void:
	var before: PackedByteArray = var_to_bytes(f)
	var result: Dictionary = _sample(f)
	assert_false(result.ok, label)
	assert_ne(result.reason, "", label)
	assert_eq(result.pose, {}, label)
	assert_eq(result.contacts, {}, label)
	assert_eq(var_to_bytes(f), before, label)

func test_unreachable_joint_limits_and_degenerate_bind_reject_without_clamp() -> void:
	var f: Dictionary = _fixture()
	for distance: float in [2.0001, 3.0, 0.0]:
		f = _fixture()
		var target: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.6 - distance, 0))
		f.contacts.legs.l0.intervals[0] = _interval("stance", 0.0, 1.0, target, target)
		_set_phase(f, 0.0)
		_reject(f, "reach " + str(distance))
	f = _fixture()
	f.rest.legs[0].max_knee_rad = 0.2
	_reject(f, "joint limit")
	f = _fixture()
	f.rest.bones[2].local.origin = Vector3.ZERO
	_reject(f, "zero length")

func test_exact_schema_raw_types_nonfinite_and_invalid_ranges() -> void:
	for section: String in ["rest", "pose", "op", "contacts"]:
		var f: Dictionary = _fixture()
		f[section]["unknown"] = 1
		_reject(f, "unknown " + section)
	for key: String in _fixture().op:
		var f: Dictionary = _fixture()
		f.op.erase(key)
		_reject(f, "missing " + key)
	for field: String in ["duration_q", "yaw0_udeg", "turn_udeg"]:
		for value: Variant in [true, null, "1", 1.0, -1, 360000000]:
			if field == "turn_udeg" and value is int and value == -1:
				continue
			var f: Dictionary = _fixture()
			f.op[field] = value
			_reject(f, "raw " + field + str(value))
	for field: String in ["phase", "current_yaw_udeg", "march_entry_phase", "march_exit_phase"]:
		for value: Variant in [true, null, "0.5", 0, -0.1, INF, NAN, 360000000.0]:
			var f: Dictionary = _fixture()
			f.op[field] = value
			_reject(f, "nonfinite" if value is float and is_nan(value) else "range " + field)
	var mutations: Array[Callable] = [
		func(f: Dictionary) -> void: f.op.turn_udeg = -180000000,
		func(f: Dictionary) -> void: f.op.turn_udeg = 0,
		func(f: Dictionary) -> void: f.op.duration_q = 0,
		func(f: Dictionary) -> void: f.op.current_yaw_udeg += 1.0,
		func(f: Dictionary) -> void: f.contacts.march_entry_phase = 0.1,
		func(f: Dictionary) -> void: f.contacts.legs.l0.sole_bind.basis.x *= 2.0,
		func(f: Dictionary) -> void: f.contacts.legs.l0.sole_bind.basis.x *= -1.0,
		func(f: Dictionary) -> void: f.rest.bones[0].parent = "l3",
		func(f: Dictionary) -> void: f.rest.legs[1].hip = "l0",
		func(f: Dictionary) -> void: f.rest.legs[0].pole = Vector3.ZERO,
		func(f: Dictionary) -> void: f.rest.legs[0].min_knee_rad = -0.1,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].t0 = 0.1,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].t1 = 0.9,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].kind = "idle",
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].point_to.x += 0.01,
		func(f: Dictionary) -> void: f.contacts.legs.l0.toe_bind = "bad bind",
		func(f: Dictionary) -> void: f.contacts.legs.l0["extra"] = 0,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0]["extra"] = 0]
	for change: Callable in mutations:
		var f: Dictionary = _fixture()
		change.call(f)
		_reject(f, "bad bind/schema")
	var f: Dictionary = _fixture()
	f.pose.l0.origin = Vector3(NAN, 0, 0)
	_reject(f, "nonfinite")

func test_parallel_pole_selects_deterministic_knee_plane() -> void:
	var f: Dictionary = _fixture()
	f.rest.legs[0].pole = Vector3.DOWN
	f.pose.l0.basis = Basis(Vector3.RIGHT, PI)
	_set_phase(f, 0.0)
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if result.ok:
		assert_eq(_sample(f), result)
		var global: Dictionary = _globals(f.rest, result.pose)
		assert_almost_eq(global.l1.origin, Vector3(0.4, 0.8, 0), Vector3.ONE * 0.00001)

func test_stateless_detached_result_and_fps_delta_partition_invariance() -> void:
	var f: Dictionary = _fixture()
	var before: Dictionary = f.duplicate(true)
	var reference: Dictionary = _sample(f)
	assert_true(reference.ok, reference.reason)
	if not reference.ok:
		return
	for partitions: int in [1, 2, 30, 60, 144]:
		for i: int in range(partitions + 1):
			_set_phase(f, 0.5 * float(i) / partitions)
			_sample(f)
		assert_eq(_sample(f), reference)
	assert_eq(f, before)
	var result: Dictionary = _sample(f)
	result.pose.body.origin.x = 99.0
	result.contacts.l0.sole.origin.x = 99.0
	assert_eq(f, before)
	assert_eq(_sample(f), reference)

func test_nonidentity_parent_preserves_locals_and_solves_model_contacts() -> void:
	var f: Dictionary = _fixture()
	f.pose.body = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 0.1, 0))
	f.pose.l0.basis = Basis(Vector3.DOWN, 0.3)
	f.pose.r1.basis = Basis(Vector3(0, -0.8, -0.6).normalized(), 0.7)
	_check_contact(f, _sample(f))

func test_unequal_lengths_full_extension_and_inner_unreachable_boundary() -> void:
	var f: Dictionary = _fixture()
	_set_phase(f, 0.0)
	var target: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, -0.4, 0))
	f.contacts.legs.l0.intervals[0] = _interval("stance", 0.0, 1.0, target, target)
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if result.ok:
		assert_almost_eq(result.contacts.l0.knee_rad, 0.0, 0.00001)
	f = _fixture()
	f.rest.bones[2].local.origin *= 0.5
	f.pose.l1.origin *= 0.5
	_set_phase(f, 0.0)
	for distance: float in [0.49, 1.51]:
		target = Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.6 - distance, 0))
		f.contacts.legs.l0.intervals[0] = _interval("stance", 0.0, 1.0, target, target)
		_reject(f, "unequal reach")
	target = Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.4, 0))
	f.contacts.legs.l0.intervals[0] = _interval("stance", 0.0, 1.0, target, target)
	result = _sample(f)
	assert_true(result.ok, result.reason)
	if result.ok:
		var global: Dictionary = _globals(f.rest, result.pose)
		assert_almost_eq(global.l0.origin.distance_to(global.l1.origin), 0.5, 0.00001)
		assert_almost_eq(global.l1.origin.distance_to(global.l2.origin), 1.0, 0.00001)

func test_nested_malformed_inputs_are_atomic() -> void:
	var mutations: Array[Callable] = [
		func(f: Dictionary) -> void: f.rest.bones = {},
		func(f: Dictionary) -> void: f.rest.legs = [],
		func(f: Dictionary) -> void: f.rest.bones[0] = null,
		func(f: Dictionary) -> void: f.rest.bones[0].local = null,
		func(f: Dictionary) -> void: f.rest.bones[0].name = 1,
		func(f: Dictionary) -> void: f.rest.legs[0] = null,
		func(f: Dictionary) -> void: f.rest.legs[0].pole = "bad",
		func(f: Dictionary) -> void: f.rest.legs[0].min_knee_rad = 0,
		func(f: Dictionary) -> void: f.contacts.legs = [],
		func(f: Dictionary) -> void: f.contacts.legs.l0 = null,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals = {},
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals = [],
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0] = null,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].t0 = 0,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].t1 = INF,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].point_from = null,
		func(f: Dictionary) -> void: f.pose.erase("r3"),
		func(f: Dictionary) -> void: f.contacts.legs.l0.erase("toe_bind"),
		func(f: Dictionary) -> void: f.rest.bones[2].erase("local"),
		func(f: Dictionary) -> void: f.rest.legs[0].erase("pole"),
		func(f: Dictionary) -> void: f.rest.legs[0].min_knee_rad = 1.5,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].toe_from = null,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].toe_to = Transform3D.IDENTITY,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].sole_from = Basis.from_scale(Vector3(2, 1, 1)),
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].point_from = Vector3i.ZERO]
	for change: Callable in mutations:
		var f: Dictionary = _fixture()
		change.call(f)
		_reject(f, "nested malformed")
	for location: String in ["rest", "contact"]:
		var f: Dictionary = _fixture()
		if location == "rest":
			f.rest.bones[0].local.origin.y = INF
		else:
			f.contacts.legs.l0.sole_bind.origin.y = INF
		_reject(f, "nonfinite")

func test_antiparallel_authored_axis_uses_deterministic_half_turn() -> void:
	var f: Dictionary = _fixture()
	f.pose.l0.basis = Basis(Vector3.RIGHT, PI)
	_set_phase(f, 0.0)
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if result.ok:
		var global: Dictionary = _globals(f.rest, result.pose)
		assert_almost_eq(global.l1.origin, Vector3(-0.2, 0.8, 0.6), Vector3.ONE * 0.00001)
		assert_eq(_sample(f), result)

func test_contact_phase_binding_accepts_arbitrary_entry_exit_and_duration() -> void:
	for phases: Vector2 in [Vector2(0, 0), Vector2(0.9999, 0.137), Vector2(0.21, 0.9999)]:
		for duration: int in [1, 1000000]:
			var f: Dictionary = _fixture()
			f.op.march_entry_phase = float(phases.x)
			f.op.march_exit_phase = float(phases.y)
			f.contacts.march_entry_phase = f.op.march_entry_phase
			f.contacts.march_exit_phase = f.op.march_exit_phase
			f.op.duration_q = duration
			_check_contact(f, _sample(f))

func test_contact_intervals_reject_gaps_overlap_and_discontinuous_targets() -> void:
	for mode: String in ["gap", "overlap", "teleport"]:
		var f: Dictionary = _fixture()
		var a: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, 0, 0))
		var b: Transform3D = a
		if mode == "teleport":
			b.origin.x += 0.01
		f.contacts.legs.l0.intervals = [
			_interval("stance", 0.0, 0.5, a, a),
			_interval("stance", 0.6 if mode == "gap" else (0.4 if mode == "overlap" else 0.5), 1.0, b, b)]
		_reject(f, mode)

func _native_fixture() -> Dictionary:
	var f: Dictionary = _fixture()
	var original: Dictionary = _globals(f.rest, f.pose)
	var rig: Transform3D = Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.1, 0, 0.1))
	f.rest.bones.insert(1, {"name": "rig", "parent": "", "local": rig})
	f.pose.rig = rig
	for leg: Dictionary in f.rest.legs:
		leg.followers = {}
		for bone: Dictionary in f.rest.bones:
			if bone.name in [leg.hip, leg.knee]:
				bone.parent = "rig"
				bone.local = rig.affine_inverse() * original[bone.name]
				f.pose[bone.name] = bone.local
			elif bone.name == leg.ankle:
				bone.parent = "body"
				bone.local = original[bone.name]
				f.pose[bone.name] = bone.local
		var follower: String = leg.hip + "_twist"
		var local: Transform3D = Transform3D(Basis(Vector3.UP, 0.37),
			original[leg.hip].origin.lerp(original[leg.knee].origin, 0.5))
		f.rest.bones.append({"name": follower, "parent": "body", "local": local})
		f.pose[follower] = local
		leg.followers[StringName(follower)] = "hip"
		follower = leg.knee + "_twist"
		local = Transform3D(Basis(Vector3.RIGHT, 0.13), Vector3(0, -0.4, -0.3))
		f.rest.bones.append({"name": follower, "parent": leg.knee, "local": local})
		f.pose[follower] = local
		leg.followers[StringName(follower)] = "knee"
	return f

func test_native_independent_leg_roots_and_explicit_twist_followers() -> void:
	for turn: int in [-90000000, 180000000]:
		var f: Dictionary = _native_fixture()
		f.op.turn_udeg = turn
		_set_phase(f, 0.5)
		var result: Dictionary = _sample(f)
		assert_true(result.ok, result.reason)
		if not result.ok:
			continue
		var before: Dictionary = _globals(f.rest, f.pose)
		var after: Dictionary = _globals(f.rest, result.pose)
		_check_segment_axes(f.rest, after)
		for leg: Dictionary in f.rest.legs:
			assert_almost_eq(after[leg.hip].origin.distance_to(after[leg.knee].origin), 1.0, 0.00001)
			assert_almost_eq(after[leg.knee].origin.distance_to(after[leg.ankle].origin), 1.0, 0.00001)
			for follower: String in leg.followers:
				var primary: String = leg[leg.followers[follower]]
				var expected: Transform3D = after[primary] * before[primary].affine_inverse() * before[follower]
				assert_almost_eq(after[follower].origin, expected.origin, Vector3.ONE * 0.00001)
				assert_almost_eq(after[follower].basis.y, expected.basis.y, Vector3.ONE * 0.00001)
		assert_eq(result.pose.body, f.pose.body)
		assert_eq(result.pose.rig, f.pose.rig)
		assert_eq(result.pose.gear, f.pose.gear)

func test_nonunit_authored_parent_keeps_body_scale_and_rest_lengths() -> void:
	var f: Dictionary = _fixture()
	f.pose.body.basis = Basis.from_scale(Vector3(1.1, 0.9, 1.2))
	f.pose.l1.origin *= 0.9
	_check_contact(f, _sample(f))

func test_native_affine_rest_binds_retain_rigid_sole_and_toe_frames() -> void:
	var f: Dictionary = _native_fixture()
	# Native scale roundoff is represented explicitly in the bind, not a larger epsilon.
	for bone: Dictionary in f.rest.bones:
		if bone.name in ["l2", "l3"]:
			bone.local.basis = Basis.from_scale(Vector3(1.00002, 0.99998, 1.00003))
			f.pose[bone.name] = bone.local
	var rest_pose: Dictionary = {}
	for bone: Dictionary in f.rest.bones:
		rest_pose[bone.name] = bone.local
	var globals: Dictionary = _globals(f.rest, rest_pose)
	var sole_frame: Transform3D = Transform3D(Basis.IDENTITY, globals.l2.origin)
	var toe_frame: Transform3D = Transform3D(Basis.IDENTITY, globals.l3.origin)
	f.contacts.legs.l0.sole_bind = globals.l2.affine_inverse() * sole_frame
	f.contacts.legs.l0.toe_bind = globals.l3.affine_inverse() * toe_frame
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if not result.ok:
		return
	var after: Dictionary = _globals(f.rest, result.pose)
	_check_segment_axes(f.rest, after)
	assert_almost_eq(after.l2.origin.distance_to(after.l3.origin),
		globals.l2.origin.distance_to(globals.l3.origin), 0.00001)
	assert_almost_eq(result.contacts.l0.sole.basis.y, result.contacts.l0.target_sole.basis.y, Vector3.ONE * 0.00001)
	assert_almost_eq(result.contacts.l0.toe.basis.y, result.contacts.l0.target_sole.basis.y, Vector3.ONE * 0.00001)
	assert_eq(result.pose.body, f.pose.body)

func test_follower_binds_and_composed_nonfinite_transforms_reject_atomically() -> void:
	var mutations: Array[Callable] = [
		func(f: Dictionary) -> void: f.rest.bones[5].parent = "l3",
		func(f: Dictionary) -> void: f.rest.legs[0].followers = [],
		func(f: Dictionary) -> void: f.rest.legs[0].followers["absent"] = "hip",
		func(f: Dictionary) -> void: f.rest.legs[0].followers["l0"] = "hip",
		func(f: Dictionary) -> void: f.rest.legs[0].followers["gear"] = "unknown",
		func(f: Dictionary) -> void: f.rest.legs[0].followers["gear"] = 0,
		func(f: Dictionary) -> void: f.rest.legs[0].followers["gear"] = "hip"; f.rest.legs[1].followers["gear"] = "knee",
		func(f: Dictionary) -> void: f.pose.body.basis = Basis.from_scale(Vector3.ZERO),
		func(f: Dictionary) -> void: f.rest.bones[0].local.basis = Basis.from_scale(Vector3(0, 1, 1))]
	for change: Callable in mutations:
		var f: Dictionary = _fixture()
		change.call(f)
		_reject(f, "bad follower/affine bind")
	var f: Dictionary = _fixture()
	f.pose.body.origin.x = 3.0e38
	f.pose.l0.origin.x = 3.0e38
	_reject(f, "nonfinite composed pose")

func test_explicit_march_toe_flex_matches_arbitrary_entry_and_exit_poses() -> void:
	for turn: int in [1, -1, 90000000, -90000000, 180000000]:
		for phase: float in [0.0, 1.0]:
			var f: Dictionary = _fixture()
			f.op.yaw0_udeg = 359000000
			f.op.turn_udeg = turn
			_set_phase(f, phase)
			var end_yaw: Basis = Basis(Vector3.UP, -deg_to_rad(float(turn) / 1000000.0))
			for leg: Dictionary in f.rest.legs:
				var entry: Basis = Basis(Vector3.RIGHT, -0.6 if leg.hip == "l0" else -0.3)
				var exit: Basis = Basis(Vector3.RIGHT, -0.2 if leg.hip == "l0" else -0.7)
				f.pose[leg.toe].basis = entry if phase == 0.0 else exit
				var start: Transform3D = Transform3D(Basis.IDENTITY,
					Vector3(-0.2 if leg.hip == "l0" else 0.2, 0, 0))
				var finish: Transform3D = Transform3D(end_yaw, Vector3.ZERO) * start
				var interval: Dictionary = _interval("swing", 0.0, 1.0, start, finish)
				interval.toe_from = entry
				interval.toe_to = end_yaw * exit
				f.contacts.legs[leg.hip].intervals = [interval]
			var result: Dictionary = _sample(f)
			assert_true(result.ok, result.reason)
			if not result.ok:
				continue
			var after: Dictionary = _globals(f.rest, result.pose)
			var authored: Dictionary = _globals(f.rest, f.pose)
			for leg: Dictionary in f.rest.legs:
				assert_almost_eq(after[leg.toe].basis.y, authored[leg.toe].basis.y, Vector3.ONE * 0.00001)
				assert_almost_eq(after[leg.ankle].origin, authored[leg.ankle].origin, Vector3.ONE * 0.00001)
			_check_segment_axes(f.rest, after)
			assert_eq(result.pose.body, f.pose.body)
			assert_eq(result.pose.gear, f.pose.gear)

func test_toe_support_keeps_world_anchor_through_heel_roll_and_both_turn_signs() -> void:
	for turn: int in [-90000000, 180000000]:
		for phase: float in [0.0, 0.5, 1.0]:
			var f: Dictionary = _fixture()
			f.op.turn_udeg = turn
			_set_phase(f, phase)
			f.contacts.legs.l0.intervals = [{"t0": 0.0, "t1": 1.0, "kind": "toe_stance",
				"point_from": Vector3(-0.2, 0, 0.2), "point_to": Vector3(-0.2, 0, 0.2),
				"sole_from": Basis(Vector3.RIGHT, 0.2), "sole_to": Basis(Vector3.RIGHT, 0.6),
				"toe_from": Basis.IDENTITY, "toe_to": Basis.IDENTITY}]
			var result: Dictionary = _sample(f)
			assert_true(result.ok, result.reason)
			if not result.ok:
				continue
			var world: Basis = Basis(Vector3.UP, -deg_to_rad(float(turn) * phase / 1000000.0))
			var pitch: float = 0.2 + 0.4 * phase
			assert_almost_eq(world * result.contacts.l0.toe.origin, Vector3(-0.2, 0, 0.2), Vector3.ONE * 0.00001)
			assert_almost_eq(world * result.contacts.l0.toe.basis.y, Vector3.UP, Vector3.ONE * 0.00001)
			assert_almost_eq(world * result.contacts.l0.sole.origin,
				Vector3(-0.2, 0.2 * sin(pitch), 0.2 * (1.0 - cos(pitch))), Vector3.ONE * 0.00001)
			_check_segment_axes(f.rest, _globals(f.rest, result.pose))
			assert_eq(result.pose.body, f.pose.body)
			assert_eq(result.pose.gear, f.pose.gear)

func test_sole_support_roll_keeps_anchor_with_independent_toe_orientation() -> void:
	for phase: float in [0.0, 0.5, 1.0]:
		var f: Dictionary = _fixture()
		_set_phase(f, phase)
		f.contacts.legs.l0.toe_bind.origin.z = 0.05
		var interval: Dictionary = _interval("stance", 0.0, 1.0,
			Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(-0.2, 0, 0)),
			Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(-0.2, 0, 0)))
		interval.toe_from = Basis(Vector3.RIGHT, -0.4)
		interval.toe_to = Basis(Vector3.RIGHT, -0.8)
		f.contacts.legs.l0.intervals = [interval]
		var result: Dictionary = _sample(f)
		assert_true(result.ok, result.reason)
		if not result.ok:
			continue
		var world: Basis = Basis(Vector3.UP, -deg_to_rad(90.0 * phase))
		assert_almost_eq(world * result.contacts.l0.sole.origin, Vector3(-0.2, 0, 0), Vector3.ONE * 0.00001)
		assert_almost_eq(world * result.contacts.l0.sole.basis.y,
			Basis(Vector3.RIGHT, -0.2 - 0.4 * phase).y, Vector3.ONE * 0.00001)
		assert_almost_eq(world * result.contacts.l0.toe.basis.y,
			Basis(Vector3.RIGHT, -0.4 - 0.4 * phase).y, Vector3.ONE * 0.00001)
		_check_segment_axes(f.rest, _globals(f.rest, result.pose))
		assert_eq(result.pose.body, f.pose.body)

func test_support_switches_are_continuous_and_orientation_teleports_reject() -> void:
	var f: Dictionary = _fixture()
	var sole: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, 0, 0))
	var toe: Vector3 = Vector3(-0.2, 0, 0.2)
	var pitch: Basis = Basis(Vector3.RIGHT, 0.4)
	var raised: Transform3D = Transform3D(pitch, toe - pitch * Vector3(0, 0, 0.2))
	var support: Dictionary = _interval("toe_stance", 0.25, 0.75,
		Transform3D(Basis.IDENTITY, toe), Transform3D(pitch, toe))
	support.toe_from = Basis.IDENTITY
	support.toe_to = Basis.IDENTITY
	var swing: Dictionary = _interval("swing", 0.75, 1.0, raised,
		Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.1, 0.1)))
	swing.toe_from = Basis.IDENTITY
	swing.toe_to = Basis(Vector3.RIGHT, -0.2)
	f.contacts.legs.l0.intervals = [_interval("stance", 0.0, 0.25, sole, sole), support, swing]
	for phase: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		_set_phase(f, phase)
		var result: Dictionary = _sample(f)
		assert_true(result.ok, result.reason)
		if result.ok:
			assert_eq(result.contacts.l0.kind, "stance" if phase < 0.25 else ("toe_stance" if phase < 0.75 else "swing"))
			_check_segment_axes(f.rest, _globals(f.rest, result.pose))
	f.contacts.legs.l0.intervals[2].toe_from = Basis(Vector3.RIGHT, 0.3)
	_reject(f, "toe orientation teleport")

func test_new_goal_types_and_impossible_toe_support_are_atomic() -> void:
	for field: String in ["point_from", "point_to", "sole_from", "sole_to", "toe_from", "toe_to"]:
		for value: Variant in [null, true, 0.0, "goal"]:
			var f: Dictionary = _fixture()
			f.contacts.legs.l0.intervals[0][field] = value
			_reject(f, "goal raw type " + field)
		var f: Dictionary = _fixture()
		f.contacts.legs.l0.intervals[0].erase(field)
		_reject(f, "goal missing " + field)
	var f: Dictionary = _fixture()
	f.contacts.legs.l0.intervals[0].toe_from = Basis(Vector3.ZERO, Vector3.UP, Vector3.BACK)
	_reject(f, "nonrotation toe goal")
	f = _fixture()
	f.contacts.legs.l0.intervals[0].point_from.x = NAN
	_reject(f, "nonfinite point")
	f = _fixture()
	f.contacts.legs.l0.intervals[0].kind = "toe_stance"
	f.contacts.legs.l0.intervals[0].point_to.x += 0.01
	_reject(f, "moving toe anchor")
	f = _fixture()
	f.contacts.legs.l0.intervals[0] = _interval("toe_stance", 0.0, 1.0,
		Transform3D(Basis.IDENTITY, Vector3(100, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(100, 0, 0)))
	_reject(f, "unreachable toe anchor")
