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

func test_parallel_bent_knee_pole_rejects_atomically() -> void:
	var f: Dictionary = _fixture()
	f.rest.legs[0].pole = Vector3.DOWN
	f.pose.l0.basis = Basis(Vector3.RIGHT, PI)
	_set_phase(f, 0.0)
	_reject(f, "ambiguous bent knee plane")

func test_invalid_reference_pole_rejects_entire_reviewer_crossing() -> void:
	var f: Dictionary = _fixture()
	f.op.turn_udeg = 1
	f.rest.legs[0].pole = Vector3.DOWN
	f.contacts.legs.l0.intervals = [_interval("swing", 0.0, 1.0,
		Transform3D(Basis.IDENTITY, Vector3(-0.201, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(-0.199, 0, 0)))]
	for phase: float in [0.49, 0.491, 0.493, 0.5, 0.507, 0.509, 0.51]:
		_set_phase(f, phase)
		_reject(f, "undefined rest reference plane at " + str(phase))

func test_valid_reference_plane_stays_continuous_across_current_pole_alignment() -> void:
	var f: Dictionary = _fixture()
	f.op.turn_udeg = 1
	f.contacts.legs.l0.intervals = [_interval("swing", 0.0, 1.0,
		Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.599, 1.6)),
		Transform3D(Basis.IDENTITY, Vector3(-0.2, 1.601, 1.6)))]
	var previous: Vector3 = Vector3.ZERO
	var had_previous: bool = false
	for phase: float in [0.49, 0.491, 0.493, 0.5, 0.507, 0.509, 0.51]:
		_set_phase(f, phase)
		var before: PackedByteArray = var_to_bytes(f)
		var result: Dictionary = _sample(f)
		assert_true(result.ok, result.reason)
		if not result.ok:
			continue
		var global: Dictionary = _globals(f.rest, result.pose)
		var knee: Vector3 = global.l1.origin
		if had_previous:
			assert_lt(knee.distance_to(previous), 0.001, "continuous foot goals must not flip the knee")
		if phase == 0.5:
			assert_almost_eq(knee, Vector3(-0.2, 2.2, 0.8), Vector3.ONE * 0.00001)
		previous = knee
		had_previous = true
		_check_segment_axes(f.rest, global)
		assert_eq(result.pose.body, f.pose.body)
		assert_eq(var_to_bytes(f), before)

func test_reference_pole_projection_brackets_both_eps_boundaries() -> void:
	for x: float in [-0.00002, -0.000005, 0.0, 0.000005, 0.00002]:
		var f: Dictionary = _fixture()
		f.rest.legs[0].pole = Vector3(x, -1, 0)
		_set_phase(f, 0.0)
		if absf(x) < 0.00001:
			_reject(f, "degenerate reference pole " + str(x))
		else:
			var result: Dictionary = _sample(f)
			assert_true(result.ok, result.reason)
			if result.ok:
				_check_segment_axes(f.rest, _globals(f.rest, result.pose))

func test_bent_knee_antipodal_reference_axis_domain_rejects_atomically() -> void:
	for x: float in [-0.0016, 0.0, 0.0016]:
		var f: Dictionary = _fixture()
		_set_phase(f, 0.0)
		var target: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2 + x, 3.2, 0))
		f.contacts.legs.l0.intervals = [_interval("swing", 0.0, 1.0, target, target)]
		_reject(f, "antipodal rest-axis domain")
	for x: float in [-0.016, 0.016]:
		var f: Dictionary = _fixture()
		_set_phase(f, 0.0)
		var target: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2 + x, 3.2, 0))
		f.contacts.legs.l0.intervals = [_interval("swing", 0.0, 1.0, target, target)]
		var result: Dictionary = _sample(f)
		assert_true(result.ok, result.reason)
		if result.ok:
			_check_segment_axes(f.rest, _globals(f.rest, result.pose))

func test_parallel_pole_is_irrelevant_for_fully_extended_knee() -> void:
	var f: Dictionary = _fixture()
	f.rest.legs[0].pole = Vector3.DOWN
	_set_phase(f, 0.0)
	var target: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.2, -0.4, 0))
	f.contacts.legs.l0.intervals = [_interval("stance", 0.0, 1.0, target, target)]
	var result: Dictionary = _sample(f)
	assert_true(result.ok, result.reason)
	if result.ok:
		var global: Dictionary = _globals(f.rest, result.pose)
		assert_almost_eq(global.l1.origin, Vector3(-0.2, 0.6, 0), Vector3.ONE * 0.00001)
		assert_almost_eq(result.contacts.l0.knee_rad, 0.0, 0.00001)
		_check_segment_axes(f.rest, global)

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

func test_near_antiparallel_authored_axes_reject_atomically() -> void:
	for bone: String in ["l0", "l1"]:
		for offset: float in [-0.004, -0.00002, 0.0, 0.00002, 0.004]:
			var f: Dictionary = _fixture()
			_set_phase(f, 0.0)
			f.pose[bone].basis = Basis(Vector3.RIGHT, PI + offset)
			_reject(f, "orientation chart " + bone + str(offset))

func test_orientation_chart_outside_both_boundaries_preserves_full_basis() -> void:
	for bone: String in ["l0", "l1"]:
		for sign_value: float in [-1.0, 1.0]:
			var previous: Dictionary = {}
			for offset: float in [0.005, 0.00502]:
				var f: Dictionary = _fixture()
				_set_phase(f, 0.0)
				f.pose[bone].basis = Basis(Vector3.RIGHT, PI + sign_value * offset)
				var before: PackedByteArray = var_to_bytes(f)
				var result: Dictionary = _sample(f)
				assert_true(result.ok, result.reason)
				assert_eq(var_to_bytes(f), before)
				if not result.ok:
					continue
				var after: Dictionary = _globals(f.rest, result.pose)
				_check_segment_axes(f.rest, after)
				assert_eq(result.pose.body, f.pose.body)
				assert_eq(result.pose.gear, f.pose.gear)
				assert_almost_eq(after.l1.origin, Vector3(-0.2, 0.8, 0.6), Vector3.ONE * 0.00001)
				for name: String in ["l0", "l1"]:
					for axis: int in range(3):
						assert_almost_eq(after[name].basis[axis], Basis.IDENTITY[axis], Vector3.ONE * 0.0001)
						if not previous.is_empty():
							assert_almost_eq(after[name].basis[axis], previous[name].basis[axis], Vector3.ONE * 0.0001)
				previous = after

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

func test_transition_changing_authored_lengths_reconstructs_native_endpoint() -> void:
	var solver: RefCounted = Pivot.new()
	assert_true(solver.has_method("sample_transition"), "explicit native geometry API is required")
	if not solver.has_method("sample_transition"):
		return
	var f: Dictionary = _fixture()
	f.pose.l1.origin *= 1.1
	f.pose.l2.origin *= 0.9
	f.pose.l3.origin *= 1.4
	_set_phase(f, 0.0)
	var globals: Dictionary = _globals(f.rest, f.pose)
	for leg: Dictionary in f.rest.legs:
		var anchor: Transform3D = globals[leg.ankle]
		f.contacts.legs[leg.hip].intervals = [_interval("swing", 0.0, 1.0, anchor, anchor)]
		f.contacts.legs[leg.hip].intervals[0].sole_to = Basis(Vector3.UP, deg_to_rad(-90.0))
		f.contacts.legs[leg.hip].intervals[0].toe_to = Basis(Vector3.UP, deg_to_rad(-90.0))
		f.contacts.legs[leg.hip].intervals[0].point_to = Basis(Vector3.UP, deg_to_rad(-90.0)) * anchor.origin
	var transition: Dictionary = {"entry_pose": f.pose.duplicate(true), "exit_pose": f.pose.duplicate(true)}
	var before: PackedByteArray = var_to_bytes([f, transition])
	var result: Dictionary = solver.call("sample_transition", f.rest, f.pose, f.op, f.contacts, transition)
	assert_true(result.ok, result.reason)
	if result.ok:
		for name: String in f.pose:
			assert_true(Pivot._near(result.pose[name], f.pose[name]), name)
		var after: Dictionary = _globals(f.rest, result.pose)
		assert_almost_eq(after.l2.origin.distance_to(after.l3.origin), 0.28, 0.00001)
		assert_almost_eq(after.l0.origin.distance_to(after.l1.origin), 1.1, 0.00001)
	assert_eq(var_to_bytes([f, transition]), before)

# Read the committed GLB directly: no import normalization, AnimationPlayer blend,
# fixture rewrite, or unmerged clip is allowed to replace the native geometry.
var _native_cache: Dictionary = {}

func _native_asset() -> Dictionary:
	if not _native_cache.is_empty():
		return _native_cache
	var path: String = "res://assets/3D/units/infantry/infantry.glb"
	assert_eq(FileAccess.get_sha256(path), "bb1d80b916be406f91390883034e07d0cf2d7690666951c3216b202393548085")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var size: int = bytes.decode_u32(12)
	var document: Dictionary = JSON.parse_string(bytes.slice(20, 20 + size).get_string_from_utf8())
	_native_cache = {"doc": document, "bin": bytes.slice(28 + size), "bones": [], "ids": {}, "keys": []}
	var root: int = -1
	for i: int in range(document.nodes.size()):
		if document.nodes[i].get("name", "") == "inf_rig":
			root = i
	_native_order(root, "")
	for animation: Dictionary in document.animations:
		if animation.name != "MARCH":
			continue
		_native_cache.animation = animation
		for sampler: Dictionary in animation.samplers:
			var times: Array = _accessor(int(sampler.input))
			for time: Array in times:
				var phase: float = float(time[0]) / float(times[-1][0])
				if phase < 1.0 and not _native_cache.keys.has(phase):
					_native_cache.keys.append(phase)
	_native_cache.keys.sort()
	return _native_cache

func _native_order(index: int, parent: String) -> void:
	var node: Dictionary = _native_cache.doc.nodes[index]
	var name: String = node.name
	_native_cache.ids[name] = index
	_native_cache.bones.append({"name": name, "parent": parent, "local": _node_transform(node)})
	for child: Variant in node.get("children", []):
		_native_order(int(child), name)

func _vec(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _node_transform(node: Dictionary) -> Transform3D:
	if node.has("matrix"):
		return _matrix(node.matrix)
	var q: Array = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
	var rotation: Basis = Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized())
	var scale: Vector3 = _vec(node.get("scale", [1.0, 1.0, 1.0]))
	return Transform3D(rotation * Basis.from_scale(scale), _vec(node.get("translation", [0.0, 0.0, 0.0])))

func _matrix(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]),
		Vector3(values[4], values[5], values[6]), Vector3(values[8], values[9], values[10])),
		Vector3(values[12], values[13], values[14]))

func _accessor(index: int) -> Array:
	var data: Dictionary = _native_cache.doc
	var accessor: Dictionary = data.accessors[index]
	var view: Dictionary = data.bufferViews[int(accessor.bufferView)]
	var sizes: Dictionary = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
	var components: int = sizes[accessor.type]
	var width: int = {5126: 4, 5125: 4, 5123: 2, 5121: 1}[int(accessor.componentType)]
	var start: int = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
	var stride: int = int(view.get("byteStride", width * components))
	var bytes: PackedByteArray = _native_cache.bin
	var result: Array = []
	for row: int in range(int(accessor.count)):
		var values: Array = []
		for column: int in range(components):
			var offset: int = start + row * stride + column * width
			match int(accessor.componentType):
				5126: values.append(bytes.decode_float(offset))
				5125: values.append(bytes.decode_u32(offset))
				5123: values.append(bytes.decode_u16(offset))
				5121: values.append(bytes[offset])
		result.append(values)
	return result

func _native_pose(phase: float) -> Dictionary:
	var asset: Dictionary = _native_asset()
	var nodes: Array = asset.doc.nodes.duplicate(true)
	for channel: Dictionary in asset.animation.channels:
		var sampler: Dictionary = asset.animation.samplers[int(channel.sampler)]
		assert_eq(sampler.get("interpolation", "LINEAR"), "LINEAR")
		var times: Array = _accessor(int(sampler.input))
		var values: Array = _accessor(int(sampler.output))
		var time: float = phase * float(times[-1][0])
		var key: int = 0
		while key + 2 < times.size() and time >= float(times[key + 1][0]):
			key += 1
		var share: float = (time - float(times[key][0])) / (float(times[key + 1][0]) - float(times[key][0]))
		var a: Array = values[key]
		var b: Array = values[key + 1]
		var value: Array = []
		if channel.target.path == "rotation":
			var q: Quaternion = Quaternion(a[0], a[1], a[2], a[3]).normalized().slerp(
				Quaternion(b[0], b[1], b[2], b[3]).normalized(), share)
			value = [q.x, q.y, q.z, q.w]
		else:
			for i: int in range(a.size()):
				value.append(lerpf(float(a[i]), float(b[i]), share))
		nodes[int(channel.target.node)][channel.target.path] = value
	var result: Dictionary = {}
	for name: String in asset.ids:
		result[name] = _node_transform(nodes[asset.ids[name]])
	return result

func _march_fixture(entry: float, exit: float, turn: int = 2000000) -> Dictionary:
	var asset: Dictionary = _native_asset()
	var f: Dictionary = {"rest": {"bones": asset.bones.duplicate(true), "legs": []},
		"pose": _native_pose(entry), "op": {"duration_q": 200000, "phase": 0.0,
		"yaw0_udeg": 359000000, "turn_udeg": turn, "current_yaw_udeg": 359000000.0,
		"march_entry_phase": entry, "march_exit_phase": exit},
		"contacts": {"march_entry_phase": entry, "march_exit_phase": exit, "legs": {}}}
	f.transition = {"entry_pose": f.pose.duplicate(true), "exit_pose": _native_pose(exit)}
	var poses: Array[Dictionary] = []
	for pose: Dictionary in [f.transition.entry_pose, f.transition.exit_pose]:
		poses.append(_globals(f.rest, pose))
	var bind_pose: Dictionary = {}
	for bone: Dictionary in f.rest.bones:
		bind_pose[bone.name] = bone.local
	var bind: Dictionary = _globals(f.rest, bind_pose)
	var exit_yaw: Basis = Basis(Vector3.UP, -deg_to_rad(float(turn) / 1000000.0))
	for side: String in [".l", ".r"]:
		var hip: String = "thigh_twist" + side
		var ankle: String = "foot" + side
		var toe: String = "toes_01" + side
		var leg: Dictionary = {"hip": hip, "knee": "leg_stretch" + side, "ankle": ankle, "toe": toe,
			"pole": Vector3(-0.150626324, 0.442476592, -0.884039692) if side == ".l" else
				Vector3(0.088675654, -0.441207958, -0.893012971),
			"min_knee_rad": 0.0, "max_knee_rad": PI,
			"followers": {"thigh_stretch" + side: "hip", "leg_twist" + side: "knee"}}
		f.rest.legs.append(leg)
		var sole_bind: Transform3D = bind[ankle].affine_inverse() * Transform3D(Basis.IDENTITY, bind[ankle].origin)
		var toe_bind: Transform3D = bind[toe].affine_inverse() * Transform3D(Basis.IDENTITY, bind[toe].origin)
		var a: Transform3D = poses[0][ankle] * sole_bind
		var b: Transform3D = poses[1][ankle] * sole_bind
		f.contacts.legs[hip] = {"sole_bind": sole_bind, "toe_bind": toe_bind, "intervals": [{
			"t0": 0.0, "t1": 1.0, "kind": "swing", "point_from": a.origin,
			"point_to": exit_yaw * b.origin, "sole_from": _proper(a.basis),
			"sole_to": exit_yaw * _proper(b.basis),
			"toe_from": _proper((poses[0][toe] * toe_bind).basis),
			"toe_to": exit_yaw * _proper((poses[1][toe] * toe_bind).basis)}]}
	return f

# Independent test-side polar iteration; endpoint checks compare full matrices/skin,
# not merely these orientation goals or the helper's contact diagnostics.
func _proper(basis: Basis) -> Basis:
	var b: Basis = basis
	for i: int in range(12):
		var inverse: Basis = b.inverse().transposed()
		b = Basis((b.x + inverse.x) * 0.5, (b.y + inverse.y) * 0.5, (b.z + inverse.z) * 0.5)
	return b.orthonormalized()

func _transition(f: Dictionary) -> Dictionary:
	return Pivot.sample_transition(f.rest, f.pose, f.op, f.contacts, f.transition)

func _assert_native_pose(f: Dictionary, result: Dictionary, reference: Dictionary) -> void:
	assert_true(result.ok, result.reason)
	if not result.ok:
		return
	for name: String in reference:
		assert_true(Pivot._near(result.pose[name], reference[name]), "native local: " + name)

func test_transition_native_optimized_failure_and_all_skin_vertices_at_both_endpoints() -> void:
	# Original native-helper-input sha256 e1bf40ccbe4dcd2d14c8e5ca44acf9b5fbba3accb8b28d80f01fb2e95fdca18d.
	var phase: float = 0.8928571428571428
	var f: Dictionary = _march_fixture(phase, phase)
	# Recreate original phase-zero stance inputs exactly from the installed asset.
	for leg: Dictionary in f.rest.legs:
		var interval: Dictionary = f.contacts.legs[leg.hip].intervals[0]
		interval.kind = "stance"
		interval.point_to = interval.point_from
		interval.sole_to = interval.sole_from
		interval.toe_to = interval.toe_from
	var legacy: Dictionary = _sample(f)
	assert_true(legacy.ok, legacy.reason)
	if legacy.ok:
		var original: Dictionary = _globals(f.rest, f.pose)
		var old: Dictionary = _globals(f.rest, legacy.pose)
		assert_almost_eq(old["toes_01.l"].origin.distance_to(original["toes_01.l"].origin), 0.00759866275, 0.000002)
	# Exit contacts must account for committed yaw to remain compatible native endpoints.
	f = _march_fixture(phase, phase)
	var mesh: Dictionary = _native_mesh()
	for endpoint: float in [0.0, 1.0]:
		_set_phase(f, endpoint)
		var result: Dictionary = _transition(f)
		_assert_native_pose(f, result, f.pose)
		if result.ok:
			var before: Dictionary = _globals(f.rest, f.pose)
			var after: Dictionary = _globals(f.rest, result.pose)
			var maximum: float = 0.0
			for i: int in range(mesh.positions.size()):
				maximum = maxf(maximum, _skin(mesh, i, before).distance_to(_skin(mesh, i, after)))
			assert_lt(maximum, 0.00001, "all 20880 actual rigid/mixed-weight vertices; old max 0.0179955408m")

func _native_mesh() -> Dictionary:
	var asset: Dictionary = _native_asset()
	var skin: Dictionary = asset.doc.skins[0]
	var attributes: Dictionary = asset.doc.meshes[0].primitives[0].attributes
	var matrices: Array = _accessor(int(skin.inverseBindMatrices))
	var names: Array[String] = []
	var inverse: Array[Transform3D] = []
	for i: int in range(skin.joints.size()):
		names.append(asset.doc.nodes[int(skin.joints[i])].name)
		inverse.append(_matrix(matrices[i]))
	return {"positions": _accessor(int(attributes.POSITION)), "joints": _accessor(int(attributes.JOINTS_0)),
		"weights": _accessor(int(attributes.WEIGHTS_0)), "names": names, "inverse": inverse}

func _skin(mesh: Dictionary, index: int, globals: Dictionary) -> Vector3:
	var result: Vector3 = Vector3.ZERO
	for influence: int in range(4):
		var joint: int = int(mesh.joints[index][influence])
		result += (globals[mesh.names[joint]] * mesh.inverse[joint] * _vec(mesh.positions[index])) * float(mesh.weights[index][influence])
	return result

func test_transition_all_original_march_keys_and_adversarial_interpolation_endpoints() -> void:
	var phases: Array = _native_asset().keys.duplicate()
	phases.append_array([0.000001, 0.137, 0.37, 0.499999, 0.500001, 0.81, 0.8928571428571428, 0.999999])
	for phase: float in phases:
		var f: Dictionary = _march_fixture(phase, fposmod(phase + 0.137, 1.0))
		for endpoint: float in [0.0, 1.0]:
			_set_phase(f, endpoint)
			f.pose = f.transition.entry_pose if endpoint == 0.0 else f.transition.exit_pose
			_assert_native_pose(f, _transition(f), f.pose)

func _connect_endpoints(f: Dictionary, exit_pose: Dictionary) -> void:
	f.transition = {"entry_pose": f.pose.duplicate(true), "exit_pose": exit_pose.duplicate(true)}
	var a: Dictionary = _globals(f.rest, f.pose)
	var b: Dictionary = _globals(f.rest, exit_pose)
	var yaw: Basis = Basis(Vector3.UP, -deg_to_rad(float(f.op.turn_udeg) / 1000000.0))
	for leg: Dictionary in f.rest.legs:
		var bind: Dictionary = f.contacts.legs[leg.hip]
		var sole0: Transform3D = a[leg.ankle] * bind.sole_bind
		var sole1: Transform3D = b[leg.ankle] * bind.sole_bind
		bind.intervals = [{"t0": 0.0, "t1": 1.0, "kind": "swing", "point_from": sole0.origin,
			"point_to": yaw * sole1.origin, "sole_from": _proper(sole0.basis),
			"sole_to": yaw * _proper(sole1.basis),
			"toe_from": _proper((a[leg.toe] * bind.toe_bind).basis),
			"toe_to": yaw * _proper((b[leg.toe] * bind.toe_bind).basis)}]

func _reference_at(f: Dictionary, phase: float) -> void:
	_set_phase(f, phase)
	f.pose = {}
	for name: String in f.transition.entry_pose:
		var a: Transform3D = f.transition.entry_pose[name]
		var b: Transform3D = f.transition.exit_pose[name]
		var ra: Basis = _proper(a.basis)
		var rb: Basis = _proper(b.basis)
		var ca: Basis = ra.transposed() * a.basis
		var cb: Basis = rb.transposed() * b.basis
		var residual: Basis = Basis(ca.x.lerp(cb.x, phase), ca.y.lerp(cb.y, phase), ca.z.lerp(cb.z, phase))
		f.pose[name] = Transform3D(ra.slerp(rb, phase) * residual, a.origin.lerp(b.origin, phase))

func test_transition_affine_sibling_geometry_followers_and_changing_native_locals() -> void:
	var f: Dictionary = _fixture()
	var bind: Dictionary = _globals(f.rest, f.pose)
	for bone: Dictionary in f.rest.bones:
		if bone.name not in ["body", "gear"]:
			bone.parent = "body"
			bone.local = bind[bone.name]
			f.pose[bone.name] = bone.local
	# Real native parenting has sibling deform joints; complete affine factors vary.
	f.pose.body = Transform3D(Basis(Vector3(1.1, 0, 0), Vector3(0.12, 0.9, 0), Vector3(0, 0.08, 1.2)), Vector3(0, 0.1, 0))
	f.pose.l1.origin += Vector3(0, 0.08, 0.12)
	f.pose.l3.origin += Vector3(0, 0.03, 0.09)
	f.pose.l0.basis = Basis(Vector3(1.02, 0, 0), Vector3(0.04, 0.97, 0), Vector3(0, 0.03, 1.01))
	f.rest.bones.append({"name": "twist", "parent": "body", "local": Transform3D(Basis.IDENTITY, Vector3(-0.2, 1, 0.3))})
	f.pose.twist = Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.2, 1, 0.3))
	f.rest.legs[0].followers.twist = "knee"
	var exit_pose: Dictionary = f.pose.duplicate(true)
	exit_pose.l1.origin += Vector3(0, 0.03, 0.04)
	exit_pose.l3.origin.z += 0.06
	exit_pose.gear.origin.x += 0.2
	_connect_endpoints(f, exit_pose)
	for phase: float in [0.0, 0.000001, 0.137, 0.5, 0.823, 0.999999, 1.0]:
		_reference_at(f, phase)
		var before: PackedByteArray = var_to_bytes(f)
		var result: Dictionary = _transition(f)
		assert_true(result.ok, result.reason)
		if not result.ok:
			continue
		var source: Dictionary = _globals(f.rest, f.pose)
		var after: Dictionary = _globals(f.rest, result.pose)
		for leg: Dictionary in f.rest.legs:
			for pair: Array in [[leg.hip, leg.knee], [leg.knee, leg.ankle], [leg.ankle, leg.toe]]:
				assert_almost_eq(after[pair[0]].origin.distance_to(after[pair[1]].origin),
					source[pair[0]].origin.distance_to(source[pair[1]].origin), 0.00001)
			for name: String in [leg.hip, leg.knee, leg.ankle, leg.toe]:
				var gram_before: Basis = source[name].basis.transposed() * source[name].basis
				var gram_after: Basis = after[name].basis.transposed() * after[name].basis
				assert_true(Pivot._near(Transform3D(gram_before, Vector3.ZERO), Transform3D(gram_after, Vector3.ZERO)), "preserved affine stretch/shear " + name)
		assert_true(Pivot._near(after.twist, after.l1 * source.l1.affine_inverse() * source.twist))
		assert_eq(result.pose.body, f.pose.body)
		assert_eq(result.pose.gear, f.pose.gear)
		assert_eq(var_to_bytes(f), before)
		if phase == 0.0 or phase == 1.0:
			_assert_native_pose(f, result, f.pose)

func _reject_transition(f: Dictionary, label: String) -> void:
	var before: PackedByteArray = var_to_bytes(f)
	var result: Dictionary = _transition(f)
	assert_false(result.ok, label)
	assert_ne(result.reason, "", label)
	assert_eq(result.pose, {}, label)
	assert_eq(result.contacts, {}, label)
	assert_eq(var_to_bytes(f), before, label)

func test_transition_malformed_unknown_nonfinite_and_incompatible_endpoints_reject_atomically() -> void:
	var mutations: Array[Callable] = [
		func(f: Dictionary) -> void: f.transition.extra = 1,
		func(f: Dictionary) -> void: f.transition.erase("exit_pose"),
		func(f: Dictionary) -> void: f.transition.entry_pose = null,
		func(f: Dictionary) -> void: f.transition.exit_pose = [],
		func(f: Dictionary) -> void: f.transition.entry_pose.unknown_bone = Transform3D.IDENTITY,
		func(f: Dictionary) -> void: f.transition.exit_pose.erase("l2"),
		func(f: Dictionary) -> void: f.transition.exit_pose.l3 = Vector3.ZERO,
		func(f: Dictionary) -> void: f.transition.exit_pose.l2.origin.y = NAN,
		func(f: Dictionary) -> void: f.transition.exit_pose.l2.basis = Basis.from_scale(Vector3(1, 0, 1)),
		func(f: Dictionary) -> void: f.pose.l2.basis.x *= -1.0,
		func(f: Dictionary) -> void: f.pose.l1.origin = Vector3.ZERO,
		func(f: Dictionary) -> void: f.pose.l3.origin = Vector3.ZERO,
		func(f: Dictionary) -> void: f.pose.l2.origin = -f.pose.l1.origin,
		func(f: Dictionary) -> void: f.op.phase = 0,
		func(f: Dictionary) -> void: f.op.turn_udeg = 0,
		func(f: Dictionary) -> void: f.op.yaw0_udeg = null,
		func(f: Dictionary) -> void: f.op.current_yaw_udeg += 1.0,
		func(f: Dictionary) -> void: f.contacts.march_entry_phase = 0.1,
		func(f: Dictionary) -> void: f.contacts.legs.l0.sole_bind.basis.x *= 2.0,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].point_to.y -= 10.0,
		func(f: Dictionary) -> void: f.contacts.legs.l0.intervals[0].toe_to = Basis(Vector3.UP, 0.7),
		func(f: Dictionary) -> void: f.transition.exit_pose.l2.origin.x += 0.1,
		func(f: Dictionary) -> void: f.rest.legs[0].max_knee_rad = 0.01]
	for i: int in range(mutations.size()):
		var f: Dictionary = _fixture()
		_connect_endpoints(f, f.pose)
		mutations[i].call(f)
		_reject_transition(f, "native boundary mutation " + str(i))
	var f: Dictionary = _fixture()
	_connect_endpoints(f, f.pose)
	_set_phase(f, 0.0)
	f.pose.gear.origin.x += 0.1
	_reject_transition(f, "current endpoint reference mismatch")

func test_transition_near_straight_native_bend_and_singular_source_chart() -> void:
	for bend: float in [0.001, -0.001, 0.00001, -0.00001]:
		var f: Dictionary = _fixture()
		f.pose.l1.origin = Vector3(0, -0.8, bend)
		f.pose.l2.origin = Vector3(0, -0.8, -bend)
		f.op.turn_udeg = 1
		_connect_endpoints(f, f.pose)
		_set_phase(f, 0.0)
		_assert_native_pose(f, _transition(f), f.pose)
	# A fully folded source hip/ankle axis cannot define a transported bend chart.
	var f: Dictionary = _fixture()
	f.pose.l2.origin = -f.pose.l1.origin
	_connect_endpoints(f, f.pose)
	_reject_transition(f, "zero native hip-ankle reference axis")

func test_transition_native_dense_skin_orientation_continuity_and_partition_invariance() -> void:
	var mesh: Dictionary = _native_mesh()
	var vertices: Array[int] = []
	var found: Dictionary = {}
	for i: int in range(mesh.positions.size()):
		for slot: int in range(4):
			var name: String = mesh.names[int(mesh.joints[i][slot])]
			var weight: float = float(mesh.weights[i][slot])
			if weight <= 0.0 or not (name.begins_with("foot") or name.begins_with("toes") or name.begins_with("leg")):
				continue
			var key: String = name + ("rigid" if weight == 1.0 else "mixed")
			if not found.has(key):
				vertices.append(i)
				found[key] = true
	assert_gt(vertices.size(), 10, "representative actual rigid and mixed weights")
	for turn: int in [2000000, -2000000]:
		var f: Dictionary = _march_fixture(0.8928571428571428, 0.81, turn)
		var previous: Dictionary = {}
		for i: int in range(101):
			_reference_at(f, float(i) / 100.0)
			var before: PackedByteArray = var_to_bytes(f)
			var result: Dictionary = _transition(f)
			assert_true(result.ok, result.reason + " phase " + str(f.op.phase))
			if not result.ok:
				continue
			var globals: Dictionary = _globals(f.rest, result.pose)
			if not previous.is_empty():
				for index: int in vertices:
					assert_lt(_skin(mesh, index, globals).distance_to(_skin(mesh, index, previous)), 0.005, "dense actual skin continuity")
				for leg: Dictionary in f.rest.legs:
					for name: String in [leg.hip, leg.knee, leg.ankle, leg.toe]:
						assert_lt(_proper(globals[name].basis).get_rotation_quaternion().angle_to(_proper(previous[name].basis).get_rotation_quaternion()), 0.05, "dense orientation continuity")
			previous = globals
			assert_eq(var_to_bytes(f), before)
		for endpoint: float in [0.0, 1.0]:
			_reference_at(f, endpoint)
			var exact: Dictionary = _transition(f)
			_reference_at(f, 0.000001 if endpoint == 0.0 else 0.999999)
			var near: Dictionary = _transition(f)
			assert_true(near.ok, near.reason)
			if exact.ok and near.ok:
				var a: Dictionary = _globals(f.rest, exact.pose)
				var b: Dictionary = _globals(f.rest, near.pose)
				for index: int in vertices:
					assert_lt(_skin(mesh, index, a).distance_to(_skin(mesh, index, b)), 0.00001, "native boundary skin C0")
		_reference_at(f, 0.5)
		var reference: Dictionary = _transition(f)
		for fps: int in [1, 30, 60, 144]:
			for i: int in range(fps + 1):
				_reference_at(f, float(i) * 0.5 / fps)
				_transition(f)
			assert_eq(_transition(f), reference)
		var snapshot: PackedByteArray = var_to_bytes(f)
		var detached: Dictionary = _transition(f)
		if detached.ok:
			detached.pose["inf_rig"].origin.x += 99.0
		assert_eq(var_to_bytes(f), snapshot)
		assert_eq(_transition(f), reference, "pause unchanged")

func test_transition_signs_nearzero_wrap_and_180_tie() -> void:
	for turn: int in [1, -1, 2000000, -2000000, 90000000, -90000000, 179999999, -179999999, 180000000]:
		var f: Dictionary = _fixture()
		f.op.yaw0_udeg = 359000000
		f.op.turn_udeg = turn
		_connect_endpoints(f, f.pose)
		for phase: float in [0.0, 0.000001, 0.137, 0.5, 0.823, 0.999999, 1.0]:
			_set_phase(f, phase)
			var result: Dictionary = _transition(f)
			assert_true(result.ok, result.reason)
			if phase == 0.0 or phase == 1.0:
				_assert_native_pose(f, result, f.pose)

func test_transition_stance_toe_stance_and_interval_boundary_preserve_physical_frames() -> void:
	for kind: String in ["stance", "toe_stance"]:
		var f: Dictionary = _fixture()
		f.op.turn_udeg = 2000000
		var source: Dictionary = _globals(f.rest, f.pose)
		var globals: Dictionary = {}
		var yaw: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(2.0)), Vector3.ZERO)
		var exit_pose: Dictionary = f.pose.duplicate(true)
		for bone: Dictionary in f.rest.bones:
			var parent: Transform3D = Transform3D.IDENTITY if bone.parent.is_empty() else globals[bone.parent]
			if bone.name not in ["body", "gear"]:
				exit_pose[bone.name] = parent.affine_inverse() * yaw * source[bone.name]
			globals[bone.name] = parent * exit_pose[bone.name]
		_connect_endpoints(f, exit_pose)
		for leg: Dictionary in f.rest.legs:
			var interval: Dictionary = f.contacts.legs[leg.hip].intervals[0]
			interval.kind = kind
			if kind == "toe_stance":
				interval.point_from = (source[leg.toe] * f.contacts.legs[leg.hip].toe_bind).origin
			interval.point_to = interval.point_from
			interval.sole_to = interval.sole_from
			interval.toe_to = interval.toe_from
			var first: Dictionary = interval.duplicate(true)
			var second: Dictionary = interval.duplicate(true)
			first.t1 = 0.4
			second.t0 = 0.4
			f.contacts.legs[leg.hip].intervals = [first, second]
		var previous: Dictionary = {}
		for phase: float in [0.0, 0.1, 0.399999, 0.4, 0.400001, 0.8, 1.0]:
			_reference_at(f, phase)
			var result: Dictionary = _transition(f)
			assert_true(result.ok, result.reason)
			if not result.ok:
				continue
			var undo: Transform3D = Transform3D(Basis(Vector3.UP, -deg_to_rad(2.0 * phase)), Vector3.ZERO)
			for leg: Dictionary in f.rest.legs:
				var frame: Transform3D = result.contacts[leg.hip].sole if kind == "stance" else result.contacts[leg.hip].toe
				var expected: Vector3 = f.contacts.legs[leg.hip].intervals[0].point_from
				assert_almost_eq(undo * frame.origin, expected, Vector3.ONE * 0.00001)
				assert_true(Pivot._near(Transform3D((undo * frame).basis, Vector3.ZERO), Transform3D.IDENTITY))
			if phase > 0.399999 and phase <= 0.400001 and not previous.is_empty():
				for name: String in result.pose:
					assert_true(Pivot._near(result.pose[name], previous[name]), "interval C0 local " + name)
			previous = result.pose
		f.contacts.legs.l0.intervals[1].point_from.x += 0.01
		f.contacts.legs.l0.intervals[1].point_to.x += 0.01
		_reject_transition(f, "discontinuous physical contact interval")

func test_transition_native_exit_toe_translation_is_geometry_not_an_incompatible_goal() -> void:
	var f: Dictionary = _fixture()
	var exit_pose: Dictionary = f.pose.duplicate(true)
	exit_pose.l3.origin.z += 0.1
	_connect_endpoints(f, exit_pose)
	_set_phase(f, 1.0)
	f.pose = exit_pose
	_assert_native_pose(f, _transition(f), exit_pose)
