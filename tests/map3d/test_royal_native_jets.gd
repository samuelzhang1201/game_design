extends GutTest
## Hand cases + native observations check a separately computed continuous proof.

const Source = preload("res://scripts/map3d/map3d_royal_locomotion_source.gd")
const Jets = preload("res://scripts/map3d/map3d_royal_native_jets.gd")
const TOOL: String = "res://tools/units3d/royal_native_arithmetic/prove.py"
var _arithmetic: Dictionary
var _source: Dictionary
var _authority: RefCounted


func before_all() -> void:
	var base: String = ProjectSettings.globalize_path("res://.godot/royal-jets-math-" + str(ResourceUID.create_id()))
	var output: Array = []
	var result: int = OS.execute("python3", [ProjectSettings.globalize_path(TOOL), "--capture",
		OS.get_executable_path(), "--scratch", base, "--receipt", base + "-receipt.json"], output, true)
	assert_eq(result, 0, str(output))
	if result != 0:
		return
	var canonical: Array = []
	result = OS.execute("python3", ["-c", "import json,sys;print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True,separators=(',',':'),allow_nan=False))", base.path_join("capture.json")], canonical, true)
	assert_eq(result, 0, str(canonical))
	_arithmetic = {"receipt": JSON.parse_string(FileAccess.get_file_as_string(base + "-receipt.json")),
		"capture_canonical": str(canonical[0]).strip_edges()}
	var calibration: Resource = load("res://assets/3D/units/royal/royal_locomotion_source.tres")
	var extracted: Dictionary = calibration.extract()
	assert_true(extracted.ok, str(extracted.get("diagnostics")))
	if not extracted.ok:
		return
	_source = extracted.source
	var prepared: Dictionary = Jets.prepare(_source, _source.identity, _arithmetic)
	assert_true(prepared.ok, str(prepared.get("diagnostics")))
	if prepared.ok:
		_authority = prepared.authority
	print("ROYAL_JETS_INPUT source=", _source.sha256, " arithmetic=", _arithmetic.receipt.sha256)


func _fixture() -> Dictionary:
	var animation: Animation = Animation.new()
	animation.length = 0.5
	animation.loop_mode = Animation.LOOP_LINEAR
	var track: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Skeleton3D:Root"))
	animation.position_track_insert_key(track, 0.0, Vector3.ZERO)
	animation.position_track_insert_key(track, 0.25, Vector3.RIGHT)
	animation.position_track_insert_key(track, 0.5, Vector3(4, 0, 0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(2, 0, 0)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 1, 0, 1])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([0.25, 0.5, 0, 0])
	var source: Dictionary = {"animation": animation,
		"tracks": [{"bone": 0, "type": Animation.TYPE_POSITION_3D, "enabled": true}],
		"bones": [{"name": "Root", "parent": -1, "rest": Transform3D.IDENTITY, "position": Vector3.ZERO, "rotation": Quaternion.IDENTITY, "scale": Vector3(2, 2, 2)},
			{"name": "Child", "parent": 0, "rest": Transform3D.IDENTITY, "position": Vector3.RIGHT, "rotation": Quaternion.IDENTITY, "scale": Vector3(3, 1, 1)}],
		"binds": [{"bone": 0, "inverse_bind": Transform3D(Basis.IDENTITY, Vector3(-0.5, 0, 0))},
			{"bone": 1, "inverse_bind": Transform3D(Basis.IDENTITY, Vector3(-1, 0, 0))}],
		"surfaces": [{"arrays": arrays}],
		"model_from_skeleton": Transform3D(Basis.from_scale(Vector3(3, 4, 5)), Vector3(7, 8, 9)),
		"calibration": {"sole_patches": {"Child": {"bone_from_sole": Transform3D(Basis.IDENTITY, Vector3(0.5, 0, 0))}}}}
	return _seal(source)


func _seal(source: Dictionary) -> Dictionary:
	source.identity = {"godot": Engine.get_version_info(), "fixture": "literal hand data"}
	source.sha256 = Source._source_digest(source)
	source.identity.source_sha256 = source.sha256
	return source


func _prepare(source: Dictionary) -> RefCounted:
	var result: Dictionary = Jets.prepare(source, source.identity, _arithmetic)
	assert_true(result.ok, str(result.get("diagnostics")))
	return result.get("authority")


func test_affine_chain_time_units_and_raw_weights_hand_case() -> void:
	var source: Dictionary = _fixture()
	var authority: RefCounted = _prepare(source)
	if authority == null:
		return
	var result: Dictionary = authority.sample(0.25)
	assert_true(result.ok, str(result.get("diagnostics")))
	if not result.ok:
		return
	assert_eq(result.globals[1].origin.x, 2.5)
	assert_eq(result.positions[0][0], Vector3(22.375, 8, 9), "raw sum=.75; F translation once")
	assert_almost_eq(result.local_jets[0].time_derivative[3], 4.0, 1e-12)
	assert_almost_eq(result.local_jets[0].phase_derivative[3], 2.0, 1e-12)
	assert_almost_eq(result.global_jets[1].time_derivative[3], 4.0, 1e-12)
	assert_eq(result.sole_jets.Child.native_value.origin.x, 23.5)
	assert_almost_eq(result.sole_jets.Child.time_derivative[3], 12.0, 1e-10)
	assert_almost_eq(result.material_jets[0].time_derivative[0], 9.0, 1e-10)
	assert_lte(result.material_jets[0].phase_derivative_lower[0], 4.5)
	assert_gte(result.material_jets[0].phase_derivative_upper[0], 4.5)
	assert_false(result.activation_pass)
	_check_native_bounds(result)
	var original: PackedVector3Array = result.positions[0].duplicate()
	source.bones[0].position = Vector3(999, 999, 999)
	source.animation.position_track_insert_key(0, 0.125, Vector3(999, 0, 0))
	assert_eq(authority.sample(0.25).positions[0], original, "retains detached private source")


func test_actual_approximate_search_key_sides_step_and_seam() -> void:
	var source: Dictionary = _fixture()
	var authority: RefCounted = _prepare(source)
	if authority == null:
		return
	var cut: float = Jets._early_cut(0.25)
	assert_lt(cut, 0.25)
	assert_eq(Jets._find([0.0, 0.25, 0.5], Jets._down(cut)), 0)
	assert_eq(Jets._find([0.0, 0.25, 0.5], cut), 1)
	var left: Dictionary = authority.sample(cut * 2.0, "left")
	var right: Dictionary = authority.sample(cut * 2.0, "right")
	assert_almost_eq(left.local_jets[0].time_derivative[3], 4.0, 1e-12)
	assert_almost_eq(right.local_jets[0].time_derivative[3], 12.0, 1e-12)
	assert_ne(left.locals.Root.origin.x, right.locals.Root.origin.x, "native early switch is not C0")
	assert_almost_eq(authority.sample(0.5, "left").local_jets[0].time_derivative[3], 12.0, 1e-12, "authored-key left limit already uses next native cell")
	assert_almost_eq(authority.sample(1.0, "left").local_jets[0].time_derivative[3], 0.0, 1e-12)
	assert_eq(authority.sample(0.0, "left").locals, authority.sample(1.0, "left").locals)
	assert_ne(authority.sample(0.0, "left").locals, authority.sample(0.0, "right").locals)
	source.animation.track_set_interpolation_type(0, Animation.INTERPOLATION_NEAREST)
	_seal(source)
	authority = _prepare(source)
	if authority == null:
		return
	left = authority.sample(cut * 2.0, "left")
	right = authority.sample(cut * 2.0, "right")
	assert_eq(left.locals.Root.origin.x, 0.0)
	assert_eq(right.locals.Root.origin.x, 1.0)
	assert_almost_eq(left.local_jets[0].time_derivative[3], 0.0, 1e-12)
	assert_almost_eq(right.local_jets[0].time_derivative[3], 0.0, 1e-12)


func test_small_angle_quaternion_basis_normalization_derivative_hand_case() -> void:
	var source: Dictionary = _fixture()
	var animation: Animation = source.animation
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("Skeleton3D:Root"))
	animation.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	animation.rotation_track_insert_key(track, 0.25, Quaternion(0.0, 1.0 / 1024.0, 0.0, 1.0))
	animation.rotation_track_insert_key(track, 0.5, Quaternion.IDENTITY)
	source.tracks.append({"bone": 0, "type": Animation.TYPE_ROTATION_3D, "enabled": true})
	_seal(source)
	var authority: RefCounted = _prepare(source)
	if authority == null:
		return
	var result: Dictionary = authority.sample(0.25)
	var y: float = 1.0 / 2048.0
	var d: float = 1.0 + y * y
	var expected_xz: float = (4.0 / 256.0) * (1.0 - y * y) / (d * d)
	var expected_xx: float = -(8.0 / 256.0) * y / (d * d)
	assert_false(result.branches[1].spherical)
	assert_almost_eq(result.local_jets[0].time_derivative[2], expected_xz, 1e-14)
	assert_almost_eq(result.local_jets[0].time_derivative[0], expected_xx, 1e-14)
	_check_native_bounds(result)


func test_shortest_sign_spherical_and_disabled_baseline() -> void:
	var source: Dictionary = _fixture()
	var animation: Animation = source.animation
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("Skeleton3D:Root"))
	animation.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	animation.rotation_track_insert_key(track, 0.25, -Quaternion(Vector3.UP, 0.2))
	animation.rotation_track_insert_key(track, 0.5, Quaternion.IDENTITY)
	source.tracks.append({"bone": 0, "type": Animation.TYPE_ROTATION_3D, "enabled": true})
	track = animation.add_track(Animation.TYPE_SCALE_3D)
	animation.track_set_path(track, NodePath("Skeleton3D:Child"))
	animation.scale_track_insert_key(track, 0.0, Vector3(9, 9, 9))
	animation.scale_track_insert_key(track, 0.25, Vector3(11, 11, 11))
	animation.track_set_enabled(track, false)
	source.tracks.append({"bone": 1, "type": Animation.TYPE_SCALE_3D, "enabled": false})
	_seal(source)
	var authority: RefCounted = _prepare(source)
	if authority == null:
		return
	var result: Dictionary = authority.sample(0.25)
	assert_true(result.branches[1].negative_dot)
	assert_true(result.branches[1].spherical)
	assert_gt(result.branches[1].sinom[0], 0.0)
	assert_gte(result.branches[1].sinom[1] - result.branches[1].sinom[0], 2.0 * Jets.SINF_ERROR)
	assert_eq(result.locals.Child.basis, Basis.from_scale(Vector3(3, 1, 1)))
	assert_almost_eq(result.local_jets[0].time_derivative[2], 1.6 * cos(0.1), 0.000002)
	assert_almost_eq(result.global_jets[1].time_derivative[3], 4.0 - 1.6 * sin(0.1), 0.000002)
	assert_almost_eq(result.global_jets[1].time_derivative[11], -1.6 * cos(0.1), 0.000002)
	_check_native_bounds(result)


func test_zero_delta_wrap_keeps_native_spherical_arithmetic() -> void:
	var source: Dictionary = _fixture()
	var animation: Animation = source.animation
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("Skeleton3D:Root"))
	animation.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	animation.rotation_track_insert_key(track, 0.25, Quaternion(Vector3.UP, 0.1))
	animation.rotation_track_insert_key(track, 0.5, Quaternion(Vector3.UP, 0.2))
	source.tracks.append({"bone": 0, "type": Animation.TYPE_ROTATION_3D, "enabled": true})
	_seal(source)
	var authority: RefCounted = _prepare(source)
	if authority == null:
		return
	var result: Dictionary = authority.sample(1.0, "left")
	assert_true(result.ok)
	assert_true(result.branches[1].constant)
	assert_true(result.branches[1].zero_delta)
	assert_false(result.branches[1].direct)
	assert_true(result.branches[1].spherical)
	assert_almost_eq(result.local_jets[0].time_derivative[2], 0.0, 1e-12)
	_check_native_bounds(result)


func test_no_wrap_edges_freeze_native_coefficient_and_transition_zero() -> void:
	var source: Dictionary = _fixture()
	source.animation.loop_mode = Animation.LOOP_NONE
	source.animation.track_set_key_time(0, 0, 0.1)
	_seal(source)
	var authority: RefCounted = _prepare(source)
	if authority == null:
		return
	var before: Dictionary = authority.sample(0.0)
	assert_eq(before.locals.Root.origin.x, 0.0)
	assert_almost_eq(before.local_jets[0].time_derivative[3], 0.0, 1e-12)
	source.animation.track_set_key_transition(0, 0, 0.0)
	_seal(source)
	authority = _prepare(source)
	if authority == null:
		return
	var frozen: Dictionary = authority.sample(0.4)
	assert_eq(frozen.locals.Root.origin.x, 0.0)
	assert_almost_eq(frozen.local_jets[0].time_derivative[3], 0.0, 1e-12)
	_check_native_bounds(frozen)


func test_interval_endpoints_enclose_tiny_and_transcendental_hand_controls() -> void:
	assert_gt(Jets._up(0.0), 0.0, "normal outward FTZ allowance, not lost subnormal")
	assert_lt(Jets._down(0.0), 0.0)
	var sine: Array[float] = Jets._trig_point(0.5, false)
	assert_lte(sine[0], 0.479425538604203)
	assert_gte(sine[1], 0.479425538604203)
	assert_lt(sine[1] - sine[0], 1e-13)
	var cosine: Array[float] = Jets._trig_point(0.0, true)
	assert_lte(cosine[0], 1.0)
	assert_gte(cosine[1], 1.0)


func test_real_native_domain_is_complete_and_preserves_all_geometry() -> void:
	assert_not_null(_authority)
	if _authority == null:
		return
	var domain: Dictionary = _authority.domain()
	assert_true(domain.complete_phase_domain)
	assert_eq(domain.bone_count, 59)
	assert_eq(domain.vertex_count, 23774)
	assert_eq(domain.track_count, 65)
	var end: float = 0.0
	var negative: bool = false
	var spherical: bool = false
	var small_angle: bool = false
	for cell: Dictionary in domain.cells:
		assert_eq(cell.native_time[0], end, "no uncovered phase gap")
		end = cell.native_time[1]
		for error: float in cell.material_native_error:
			assert_true(is_finite(error) and error >= 0.0)
		for branch: Dictionary in cell.branches:
			negative = negative or branch.negative_dot
			if branch.type == Animation.TYPE_ROTATION_3D and not branch.constant:
				spherical = spherical or branch.spherical
				small_angle = small_angle or not branch.spherical
	assert_eq(end, _source.animation.length)
	assert_true(negative)
	assert_true(spherical)
	assert_true(small_angle)
	var enabled: int = 0
	var step: int = 0
	var linear: int = 0
	for i: int in _source.animation.get_track_count():
		enabled += int(_source.animation.track_is_enabled(i))
		step += int(_source.animation.track_get_interpolation_type(i) == Animation.INTERPOLATION_NEAREST)
		linear += int(_source.animation.track_get_interpolation_type(i) == Animation.INTERPOLATION_LINEAR)
		assert_false(_source.animation.track_is_compressed(i))
	assert_eq([enabled, linear, step], [65, 55, 10])


func test_real_native_values_keys_off_keys_and_every_material_vertex() -> void:
	if _authority == null:
		return
	var animation: Animation = _source.animation
	var phases: Array[float] = [0.0, 0.73, 0.999999]
	for track: int in animation.get_track_count():
		for key: int in animation.track_get_key_count(track):
			var t: float = animation.track_get_key_time(track, key)
			if t < animation.length and not phases.has(t / animation.length):
				phases.append(t / animation.length)
			if key > 0:
				var mid: float = (t + animation.track_get_key_time(track, key - 1)) * 0.5 / animation.length
				if not phases.has(mid):
					phases.append(mid)
	for phase: float in phases + [0.73, 0.0]:
		var result: Dictionary = _authority.sample(phase)
		assert_true(result.ok, str(result.get("diagnostics")))
		if not result.ok:
			return
		var native: Dictionary = Source.sample(_source, _source.identity, phase)
		assert_true(native.ok)
		assert_eq(result.locals, native.locals)
		assert_eq(result.globals, native.globals)
		assert_eq(result.positions, native.positions, "all original packed weights, binds and model translation")
		_check_native_bounds(result)
	assert_true(Source.validate(_source, _source.identity).ok)
	print("ROYAL_JETS_NATIVE phases=", phases.size(), " bones=59 vertices=23774 complete_phase_proof_cells=", _authority.domain().cells.size())


func _check_native_bounds(result: Dictionary) -> void:
	if not result.ok:
		return
	var valid: bool = true
	for i: int in result.globals.size():
		var matrix: Transform3D = result.globals[i]
		var packet: Dictionary = result.global_jets[i]
		for row: int in 3:
			for col: int in 4:
				var value: float = matrix.basis[col][row] if col < 3 else matrix.origin[row]
				var index: int = row * 4 + col
				valid = valid and value >= packet.extension_lower[index] - packet.native_error[index] and value <= packet.extension_upper[index] + packet.native_error[index]
	for surface: int in result.positions.size():
		var vertices: PackedVector3Array = result.positions[surface]
		var packet: Dictionary = result.material_jets[surface]
		assert_eq(packet.time_derivative.size(), vertices.size() * 3)
		for v: int in vertices.size():
			for axis: int in 3:
				var index: int = v * 3 + axis
				valid = valid and vertices[v][axis] >= packet.extension_lower[index] - packet.native_error_uniform[axis] and vertices[v][axis] <= packet.extension_upper[index] + packet.native_error_uniform[axis]
	assert_true(valid, "native comparison is enclosed without a fitted epsilon")


func test_corrupt_identity_schema_indices_proof_and_unsupported_branches_are_atomic() -> void:
	if _arithmetic.is_empty():
		return
	for kind: String in ["stale", "bone", "bind", "weight", "type", "ease", "cubic", "key", "nonfinite"]:
		var source: Dictionary = _fixture()
		match kind:
			"stale": source.identity.source_sha256 = "stale"
			"bone": source.bones[1].parent = 2
			"bind": source.binds[0].bone = 999
			"weight": source.surfaces[0].arrays[Mesh.ARRAY_WEIGHTS][0] = -1.0
			"type": source.tracks[0].bone = "Root"
			"ease": source.animation.track_set_key_transition(0, 0, 2.0)
			"cubic": source.animation.track_set_interpolation_type(0, Animation.INTERPOLATION_CUBIC)
			"key": source.animation.track_set_key_time(0, 1, 0.000001)
			"nonfinite": source.bones[0].position.x = NAN
		var result: Dictionary = Jets.prepare(source, source.identity, _arithmetic)
		assert_false(result.ok, kind)
		assert_null(result.authority, kind)
		assert_true(result.locals.is_empty(), kind)
	for kind: String in ["receipt", "code", "pid", "pid_type", "address", "engine", "theorem", "assumptions"]:
		var arithmetic: Dictionary = _arithmetic.duplicate(true)
		var capture: Dictionary = JSON.parse_string(arithmetic.capture_canonical)
		match kind:
			"receipt": arithmetic.receipt.sha256 = "stale"
			"code": capture.native.imports[0][0].code = "00000000"
			"pid": capture.native.pid += 1.0
			"pid_type": capture.native.pid = "bad"
			"address": capture.native.imports[0][0].target = "0xbadZZ"
			"assumptions": arithmetic.receipt.assumptions = "unproved"
			"engine": capture.engine.version.hash = "stale"
			"theorem": arithmetic.receipt.theorems.sinf.outward_absolute_error = "0"
		if kind != "receipt":
			arithmetic.capture_canonical = Jets._json(capture)
			arithmetic.receipt.capture_sha256 = arithmetic.capture_canonical.sha256_text()
			var receipt: Dictionary = arithmetic.receipt.duplicate(true)
			receipt.erase("sha256")
			arithmetic.receipt.sha256 = Jets._json(receipt).sha256_text()
		var source: Dictionary = _fixture()
		assert_false(Jets.prepare(source, source.identity, arithmetic).ok, "resealed " + kind)
	var authority: RefCounted = _prepare(_fixture())
	if authority != null:
		for phase: Variant in [-0.1, 1.1, 1, NAN, INF, "0.5"]:
			assert_false(authority.sample(phase).ok)
		assert_false(authority.sample(1.0).ok)
		assert_false(authority.sample(0.5, "middle").ok)
		assert_false(authority.sample(0.5, 1).ok)
		var tiny: PackedByteArray = PackedByteArray()
		tiny.resize(8)
		tiny.encode_s64(0, -9223372036854775807)
		assert_false(authority.sample(tiny.decode_double(0)).ok, "negative subnormal cannot enter phase domain through FTZ")
