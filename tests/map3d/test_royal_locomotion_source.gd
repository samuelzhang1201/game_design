extends GutTest
## R1 is an input component. No test here grants contact-policy/activation PASS.

const Source = preload("res://scripts/map3d/map3d_royal_locomotion_source.gd")
const CALIBRATION: String = "res://assets/3D/units/royal/royal_locomotion_source.tres"
var _source: Dictionary = {}
var _calibration: Resource


func before_all() -> void:
	_calibration = load(CALIBRATION)
	if _calibration == null:
		return
	var result: Dictionary = _calibration.extract()
	assert_true(result.ok, str(result.get("diagnostics")))
	_source = result.source


func test_physical_hand_case_and_all_mode_penetration() -> void:
	var p: Dictionary = Source.point_error(Vector3(.001, -.002, 0), Vector3.ZERO,
		Vector3.UP, Vector3.ZERO, 1.0, "stance")
	assert_true(p.ok)
	assert_almost_eq(p.slip_m, .001, 0.000000001)
	assert_almost_eq(p.penetration_m, .002, 0.000000001)
	assert_almost_eq(p.error_m, .002, 0.000000001)
	var swing: Dictionary = Source.point_error(Vector3(.001, -.002, 0), Vector3.ZERO,
		Vector3.UP, Vector3.ZERO, 1.0, "swing")
	assert_eq(swing.penetration_m, p.penetration_m, "swing never exempts penetration")
	assert_eq(swing.error_m, p.penetration_m)
	var raised: Dictionary = Source.point_error(Vector3(.001, .002, 0), Vector3.ZERO,
		Vector3.UP, Vector3.ZERO, 1.0, "swing")
	assert_eq(raised.error_m, 0.0, "swing is not a planted stance")
	assert_false(Source.point_error(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, "stance").ok)
	assert_false(Source.point_error(Vector3.ZERO, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 0.0, "stance").ok)
	assert_false(Source.point_error(Vector3(NAN, 0, 0), Vector3.ZERO, Vector3.UP, Vector3.ZERO, 1.0, "stance").ok)


func test_units_and_independent_ground() -> void:
	var p := Vector3(.001, -.002, 0)
	var at := Transform3D(Basis(Vector3.FORWARD, .7), Vector3(3, 4, 5))
	var original: Dictionary = Source.point_error(p, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 1.0, "stance")
	var moved: Dictionary = Source.point_error(at * p, at.origin, at.basis * Vector3.UP, at.origin, 1.0, "stance")
	assert_almost_eq(moved.error_m, original.error_m, .0000003)
	var doubled: Dictionary = Source.point_error(p * 2.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 2.0, "stance")
	assert_eq(doubled.error_m, original.error_m)
	assert_eq(doubled.error_world, 2.0 * original.error_world)
	var actor_only: Dictionary = Source.point_error(p + Vector3(0, -.01, 0), Vector3.ZERO, Vector3.UP, Vector3.ZERO, 1.0, "stance")
	assert_gt(actor_only.error_m, original.error_m)


func test_finite_error_decision_does_not_invent_policy_or_prove_domain() -> void:
	assert_eq(Source.decide(2000.0, 2000.0, 1999).disposition, "FAIL")
	assert_eq(Source.decide(2000.0, 2000.0, 2000).disposition, "WITHIN_BOUND")
	assert_eq(Source.decide(2000.0, 2000.0, null).disposition, "UNRESOLVED")
	assert_eq(Source.decide(null, null, 2000).disposition, "UNRESOLVED")
	assert_eq(Source.decide(1000.0, 3000.0, 2500).disposition, "UNRESOLVED")
	assert_false(Source.decide(2.0, 1.0, 3).ok)
	assert_false(Source.decide(0.0, INF, 3).ok)
	assert_false(Source.decide(0.0, 0.0, -1).ok)
	assert_false(Source.decide(0.0, 0.0, 0).activation_pass)
	assert_eq(Source.decide(2000.000000000001, null, 2000).disposition, "FAIL")
	assert_eq(Source.decide(1999.999999999999, 2000.000000000001, 2000).disposition, "UNRESOLVED")
	assert_eq(Source.decide(null, 1999.999999999999, 2000).disposition, "WITHIN_BOUND")
	# Bounds/units in this hand case are exact; no guessed arithmetic allowance.
	assert_eq(Source.decide(23272.216320037897, 23272.216320037897, 20000).disposition, "FAIL")
	assert_eq(Source.decide(23272.216320037897, null, 30000).disposition, "UNRESOLVED")


func test_resource_preserves_adverse_channels_and_missing_authority() -> void:
	var calibration = load(CALIBRATION)
	assert_not_null(calibration)
	if calibration == null:
		return
	assert_eq(calibration.observations.size(), 3)
	var raw: Dictionary = calibration.observations["raw_flat"]
	var native: Dictionary = calibration.observations["native_flat"]
	var terrain: Dictionary = calibration.observations["native_terrain"]
	assert_eq(raw.phase, .73)
	assert_eq(raw.vertex, 21308)
	assert_almost_eq(raw.model_y + raw.seat_m, -.023272148064053248, 1e-16)
	assert_almost_eq(native.model_y + native.seat_m, -.023272216320037897, 1e-16)
	assert_eq(terrain.separation_world, -.504600524902344)
	assert_eq(terrain.separation_m, -.0248103348948813)
	for witness: Dictionary in calibration.observations.values():
		assert_null(witness.uncertainty_um)
		assert_eq(witness.contact_disposition, "UNRESOLVED")
	assert_eq(calibration.contact_authority, "UNRESOLVED")
	assert_true(calibration.support_intervals.is_empty())
	assert_true(calibration.airborne_intervals.is_empty())
	assert_eq(ceili(-raw.separation_m * 1000000.0), 23273)
	assert_eq(ceili(-native.separation_m * 1000000.0), 23273)
	assert_eq(ceili(-terrain.separation_m * 1000000.0), 24811)
	assert_almost_eq(terrain.separation_world / terrain.reported_conversion_divisor, terrain.separation_m, 1e-16)
	assert_ne(terrain.reported_conversion_divisor, terrain.uniform_scale_display, "legacy vertical divisor is not actual uniform scale")
	assert_almost_eq(terrain.separation_world / terrain.uniform_scale_display, -.024672658552096074, 1e-16)
	assert_almost_eq(Vector3(.4339753766858621, 2.4051723976923536, .3996451637692787).distance_to(
		Vector3(.30663679988527087, 2.1429267468144504, -1.0967962579645545)), 1.5245736529360432, .0000002)
	assert_almost_eq(749.0 - 748.8595829969472, .1404170030528, 1e-12)
	assert_almost_eq(789.9554707346122 - 749.0, 40.9554707346122, 1e-12)


func test_native_geometry_keys_and_interpolation_at_every_key_midpoint_and_seam() -> void:
	assert_false(_source.is_empty())
	if _source.is_empty():
		return
	var scene: Node3D = load(_calibration.scene_path).instantiate()
	add_child_autofree(scene)
	var skeleton: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	var mesh: MeshInstance3D = scene.find_child("royal", true, false)
	var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var original: Animation = player.get_animation("MARCH")
	var detached: Animation = _source.animation
	assert_ne(original, detached)
	assert_eq(detached.length, original.length)
	assert_eq(detached.loop_mode, original.loop_mode)
	assert_eq(detached.get_track_count(), original.get_track_count())
	var times: Array[float] = [0.0, .73 * original.length, .11 * original.length, .999999 * original.length]
	for t: int in original.get_track_count():
		assert_eq(detached.track_get_path(t), original.track_get_path(t))
		assert_eq(detached.track_get_type(t), original.track_get_type(t))
		assert_eq(detached.track_get_interpolation_type(t), original.track_get_interpolation_type(t))
		assert_eq(detached.track_get_interpolation_loop_wrap(t), original.track_get_interpolation_loop_wrap(t))
		assert_eq(detached.track_get_key_count(t), original.track_get_key_count(t))
		for k: int in original.track_get_key_count(t):
			assert_eq(detached.track_get_key_time(t, k), original.track_get_key_time(t, k))
			assert_eq(detached.track_get_key_value(t, k), original.track_get_key_value(t, k))
			assert_eq(detached.track_get_key_transition(t, k), original.track_get_key_transition(t, k))
			var time: float = original.track_get_key_time(t, k)
			if time < original.length and not times.has(time):
				times.append(time)
			if k > 0:
				var middle: float = (time + original.track_get_key_time(t, k - 1)) / 2.0
				if middle < original.length and not times.has(middle):
					times.append(middle)
	for i: int in skeleton.get_bone_count():
		assert_eq(_source.bones[i].name, String(skeleton.get_bone_name(i)))
		assert_eq(_source.bones[i].rest, skeleton.get_bone_rest(i))
		assert_eq(_source.bones[i].parent, skeleton.get_bone_parent(i))
	for i: int in mesh.skin.get_bind_count():
		assert_eq(_source.binds[i].name, String(mesh.skin.get_bind_name(i)))
		assert_eq(_source.binds[i].inverse_bind, mesh.skin.get_bind_pose(i))
	for s: int in mesh.mesh.get_surface_count():
		assert_eq(_source.surfaces[s].arrays, mesh.mesh.surface_get_arrays(s), "every mesh array; no weight normalization")
	player.play("MARCH")
	var max_local: float = 0.0
	var max_skin: float = 0.0
	times.sort()
	# Reverse query order as well: no preceding sampled pose is input authority.
	for time: float in times + [times[-1], times[0], .73 * original.length]:
		player.seek(time, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var sampled: Dictionary = Source.sample(_source, _source.identity, time / original.length)
		assert_true(sampled.ok, str(sampled.get("diagnostics")))
		if not sampled.ok:
			return
		for i: int in skeleton.get_bone_count():
			var a: Transform3D = sampled.locals[String(skeleton.get_bone_name(i))]
			var b: Transform3D = skeleton.get_bone_pose(i)
			max_local = maxf(max_local, _affine_distance(a, b))
		var matrices: Array[Transform3D] = []
		for bind: int in mesh.skin.get_bind_count():
			var bone: int = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			matrices.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		var at: Transform3D = scene.global_transform.affine_inverse() * skeleton.global_transform
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v: int in vertices.size():
				var p := Vector3.ZERO
				for influence: int in 4:
					var offset: int = v * 4 + influence
					p += (matrices[arrays[Mesh.ARRAY_BONES][offset]] * vertices[v]) * arrays[Mesh.ARRAY_WEIGHTS][offset]
				max_skin = maxf(max_skin, (at * p).distance_to(sampled.positions[surface][v]))
	assert_lte(max_local, .00001, "unchanged native/kernel precision, full locals")
	assert_lte(max_skin, .00001, "every vertex incl mixed skin and gear")
	print("ROYAL_NATIVE_EQUIVALENCE phases=", times.size(), " local_max=", max_local, " skin_max=", max_skin)
	var at073: Dictionary = Source.sample(_source, _source.identity, .73)
	for native_vertex: int in _calibration.observations.native_flat.native_vertices:
		assert_eq(_source.surfaces[0].arrays[Mesh.ARRAY_VERTEX][native_vertex], _calibration.observations.native_flat.bind_position)
		assert_almost_eq(at073.positions[0][native_vertex].y, -.0592770278453827, .000001)
	var measurement: Dictionary = Source.plane_observation(at073.positions[0], {
		"surface_kind": "independent_plane", "model_to_world": Transform3D(Basis.IDENTITY, Vector3(0, .0360048115253448, 0)),
		"ground": Vector3.ZERO, "normal": Vector3.UP, "provenance": "Frozen flat-seat native query; not actual Terrain3D"})
	assert_true(measurement.ok)
	assert_eq(measurement.vertex_count, 23774)
	assert_gte(measurement.penetration_m, .023271, "all-mode whole mesh retains .73 witness")
	assert_false(measurement.activation_pass)


func _affine_distance(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin), maxf(a.basis.x.distance_to(b.basis.x),
		maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z))))


func test_corrupt_stale_and_invalid_inputs_reject_without_partial_pose() -> void:
	if _source.is_empty():
		return
	var stale: Dictionary = _source.identity.duplicate(true)
	stale.godot.hash = "stale"
	var result: Dictionary = Source.sample(_source, stale, .73)
	assert_false(result.ok)
	assert_true(result.locals.is_empty())
	for phase: Variant in [-.1, 1.0, INF, NAN, 0, "0.73"]:
		assert_false(Source.sample(_source, _source.identity, phase).ok)
	for kind: String in ["weights", "bind", "hierarchy", "rest", "key", "interpolation", "loop", "patch"]:
		var changed: Dictionary = _source.duplicate(true)
		changed.animation = _source.animation.duplicate(true)
		match kind:
			"weights":
				changed.surfaces[0].arrays[Mesh.ARRAY_WEIGHTS][0] += .01
			"bind":
				changed.binds[0].inverse_bind.origin.x += .01
			"hierarchy":
				changed.bones[1].parent = -1
			"rest":
				changed.bones[0].rest.origin.x += .01
			"key":
				changed.animation.track_set_key_time(0, 0, .001)
			"interpolation":
				changed.animation.track_set_interpolation_type(0, Animation.INTERPOLATION_NEAREST)
			"loop":
				changed.animation.loop_mode = Animation.LOOP_NONE
			"patch":
				changed.calibration.sole_patches["FrontHoof.R"].vertices[0] = 0
		result = Source.sample(changed, _source.identity, .73)
		assert_false(result.ok, kind)
		assert_true(result.locals.is_empty(), kind)
		changed.sha256 = Source._source_digest(changed)
		assert_false(Source.sample(changed, _source.identity, .73).ok, "rehashing cannot replace measured identity: " + kind)
	assert_true(Source.validate(_source, _source.identity).ok, "mutating copies cannot touch retained source")
	var bad = _calibration.duplicate(true)
	bad.source_hashes[bad.scene_path] = "stale"
	assert_false(bad.extract().ok)
	bad = _calibration.duplicate(true)
	bad.sole_patches["FrontHoof.L"].vertices[0] = 0
	assert_false(bad.extract().ok)


func test_calibration_binds_complete_source_identity_and_required_importer() -> void:
	var settings := ConfigFile.new()
	assert_eq(settings.load("res://assets/3D/units/royal/royal.glb.import"), OK)
	var importer: String = settings.get_value("params", "import_script/path")
	assert_false(importer.is_empty())
	var bad = _calibration.duplicate(true)
	bad.source_hashes.erase(importer)
	assert_ne(Source._digest(bad.calibration_data()), bad.calibration_sha256, "the seal binds the complete dependency set")
	for reseal: bool in [false, true]:
		if reseal:
			bad.calibration_sha256 = Source._digest(bad.calibration_data())
		var result: Dictionary = bad.extract()
		assert_false(result.ok, "missing importer, resealed=%s" % reseal)
		assert_true(result.source.is_empty())
		assert_eq(result.diagnostics.get("reason", ""), "unbound_import_script:" + importer)
	bad = _calibration.duplicate(true)
	bad.source_hashes[importer] = "changed dependency"
	var changed: Dictionary = bad.extract()
	assert_false(changed.ok)
	assert_true(changed.source.is_empty())
	assert_eq(changed.diagnostics.get("reason", ""), "stale_source:" + importer)
	bad = _calibration.duplicate(true)
	bad.scene_path += ".changed"
	assert_ne(Source._digest(bad.calibration_data()), bad.calibration_sha256, "the seal binds the scene path")


func test_raw_packed_weights_and_affine_skin_are_not_normalized() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(1, 2, 3)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 1, 0, 1])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([.25, .5, 0, 0])
	var transforms: Array[Transform3D] = [Transform3D(Basis(Vector3(2, 0, 0), Vector3(1, 3, 0), Vector3(0, 0, 4)), Vector3(1, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))]
	# .25*(5,6,12) + .5*(1,4,3) = (1.75,3.5,4.5); sum weights=.75.
	assert_eq(Source._skin_vertices(arrays, transforms)[0], Vector3(1.75, 3.5, 4.5))


func test_disk_import_identity_rejects_stale_or_corrupt_native_cache() -> void:
	var prefix: String = "user://royal_source_cache_test"
	var paths: Array[String] = [prefix + ".glb", prefix + ".glb.import", prefix + ".scn", prefix + ".md5"]
	for path: String in [paths[0], paths[2]]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("original bytes")
		file.close()
	var settings := ConfigFile.new()
	settings.set_value("deps", "source_file", paths[0])
	settings.set_value("deps", "dest_files", [paths[2]])
	settings.set_value("remap", "path", paths[2])
	assert_eq(settings.save(paths[1]), OK)
	var checksums := ConfigFile.new()
	checksums.set_value("", "source_md5", FileAccess.get_md5(paths[0]))
	checksums.set_value("", "dest_md5", FileAccess.get_md5(paths[2]))
	assert_eq(checksums.save(paths[3]), OK)
	assert_true(Source.import_identity(paths[1]).ok)
	settings.set_value("params", "import_script/path", 42)
	assert_eq(settings.save(paths[1]), OK)
	assert_eq(Source.import_identity(paths[1]).diagnostics.reason, "import_script_schema")
	settings.set_value("params", "import_script/path", "")
	assert_eq(settings.save(paths[1]), OK)
	var file := FileAccess.open(paths[2], FileAccess.WRITE)
	file.store_string("changed compiled native scene")
	file.close()
	assert_false(Source.import_identity(paths[1]).ok)
	checksums.set_value("", "dest_md5", FileAccess.get_md5(paths[2]))
	checksums.save(paths[3])
	file = FileAccess.open(paths[0], FileAccess.WRITE)
	file.store_string("new source, old native import")
	file.close()
	assert_false(Source.import_identity(paths[1]).ok)
	for path: String in paths:
		DirAccess.remove_absolute(path)


func test_material_patch_is_fixed_bind_geometry_with_actual_named_skin_frame() -> void:
	assert_false(_source.is_empty())
	if _source.is_empty():
		return
	for hoof: String in _calibration.sole_patches:
		var patch: Dictionary = _calibration.sole_patches[hoof]
		var arrays: Array = _source.surfaces[patch.surface].arrays
		var triangle: int = patch.reference_triangle
		var centroid := Vector3.ZERO
		for corner: int in 3:
			var index: int = arrays[Mesh.ARRAY_INDEX][triangle * 3 + corner]
			centroid += arrays[Mesh.ARRAY_VERTEX][index] / 3.0
			var recorded: Array = patch.reference_positions[corner]
			assert_eq(arrays[Mesh.ARRAY_VERTEX][index], Vector3(recorded[0], recorded[1], recorded[2]))
		assert_lt(centroid.distance_to(patch.bind_frame.origin), .000001)
		for bind: Dictionary in _source.binds:
			if bind.name == hoof:
				assert_lt(_affine_distance(bind.inverse_bind * patch.bind_frame, patch.bone_from_sole), .000001)
		assert_eq(patch.role, "measured_material_patch_not_stance")
