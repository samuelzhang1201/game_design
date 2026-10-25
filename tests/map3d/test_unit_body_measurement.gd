extends GutTest

const TOOL := "res://tools/units3d/measure_unit_bodies.gd"
const SuiteData := preload("res://tests/suite_data.gd")

func _measure(scene: PackedScene, size: float = 1.0) -> Dictionary:
	if not FileAccess.file_exists(TOOL):
		assert_true(false, "CF01 measurement interface must exist")
		return {}
	var tool: Script = load(TOOL)
	return tool.call("measure", scene, {"repo": SuiteData.repo(), "size": size,
		"fov_deg": 45.0, "view_h_px": 1080.0, "ref_m": 25000.0,
		"world_per_sim_m": 1.0})

func _scene() -> PackedScene:
	var root := Node3D.new()
	var parent := Node3D.new()
	parent.position = Vector3(3, 0, 0)
	root.add_child(parent)
	parent.owner = root
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	(body.mesh as BoxMesh).size = Vector3(2, 2, 4)
	parent.add_child(body)
	body.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func test_body_measurement_scales_and_contains_nested_mount_or_machine() -> void:
	var one := _measure(_scene())
	if one.is_empty(): return
	var two := _measure(_scene(), 2.0)
	# Nested centre x=3, half width=1, half depth=2: sqrt(4²+2²).
	var repo := SuiteData.repo()
	var k := Map3DUnits.scale_for(repo, 45.0, 1080.0, 25000.0, 2.0)
	assert_almost_eq(float(one.radius_m), sqrt(20.0) * k, 0.001)
	assert_almost_eq(float(two.radius_m), float(one.radius_m) * 2.0, 0.001)
	assert_gte(float(one.deploy_min_width_m), float(one.radius_m) * 10.0)
	assert_gte(float(one.deploy_min_depth_m), float(one.radius_m) * 4.0)

func test_missing_model_fails_explicitly() -> void:
	var result := _measure(null)
	if result.is_empty(): return
	assert_eq(result.get("status"), "error")
	assert_true(String(result.get("error", "")).contains("model"))

func test_idle_walk_and_rotation_are_sampled() -> void:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = BoxMesh.new()
	(body.mesh as BoxMesh).size = Vector3(2, 2, 4)
	root.add_child(body)
	body.owner = root
	var player := AnimationPlayer.new()
	root.add_child(player)
	player.owner = root
	var library := AnimationLibrary.new()
	for clip: String in ["STANDBY", "MARCH"]:
		var animation := Animation.new()
		animation.length = 1.0
		var track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, NodePath("Body:position"))
		animation.position_track_insert_key(track, 0.0, Vector3.ZERO)
		animation.position_track_insert_key(track, 0.5, Vector3(8, 0, 0))
		animation.position_track_insert_key(track, 1.0, Vector3.ZERO)
		track = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("Body:rotation"))
		animation.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
		animation.rotation_track_insert_key(track, 1.0, Quaternion(Vector3.UP, PI))
		library.add_animation(clip, animation)
	player.add_animation_library("", library)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	var result := _measure(packed)
	if result.is_empty(): return
	assert_eq((result.sampled_clips as Array).size(), 2)
	var k := float(result.scale_inputs.simulation_scale)
	assert_gte(float(result.radius_m), 8.0 * k, "Animated translation and yaw included")

func _skin_scene(weapon: bool = false) -> PackedScene:
	var root := Node3D.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	skeleton.add_bone("mount")
	if weapon:
		skeleton.add_bone("Sword")
		skeleton.set_bone_pose_position(1, Vector3(100, 0, 0))
	skeleton.set_bone_pose_position(0, Vector3(8, 0, 0))
	root.add_child(skeleton)
	skeleton.owner = root
	var mesh := MeshInstance3D.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(1, 2, 0), Vector3(0, 0, 1)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0, 0,0,0,0, 0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0, 1,0,0,0, 1,0,0,0])
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if weapon:
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(1, 2, 0), Vector3(0, 0, 1)])
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array([1,0,0,0, 1,0,0,0, 1,0,0,0])
		geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = geometry
	mesh.skin = Skin.new()
	mesh.skin.add_bind(0, Transform3D.IDENTITY)
	if weapon: mesh.skin.add_bind(1, Transform3D.IDENTITY)
	skeleton.add_child(mesh)
	mesh.owner = root
	mesh.skeleton = NodePath("..")
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func test_skin_pose_includes_mount_or_machine_vertices() -> void:
	var result := _measure(_skin_scene())
	if result.is_empty(): return
	assert_almost_eq(float(result.radius_m), 9.0 * float(result.scale_inputs.simulation_scale), 0.001)

func test_calibration_is_required_and_simulation_conversion_is_explicit() -> void:
	if not FileAccess.file_exists(TOOL):
		assert_true(false, "CF01 measurement interface must exist")
		return
	var tool: Script = load(TOOL)
	var missing: Dictionary = tool.call("measure", _scene(), {})
	assert_eq(missing.get("status"), "error")
	var art := {"repo": SuiteData.repo(), "size": 1.0, "fov_deg": 45.0,
		"view_h_px": 1080.0, "ref_m": 25000.0, "world_per_sim_m": 0.05}
	var converted: Dictionary = tool.call("measure", _scene(), art)
	var one := _measure(_scene())
	assert_almost_eq(float(converted.radius_m), float(one.radius_m) * 20.0, 0.01)
	assert_eq(converted.slot_pitch_m, int(converted.body_radius_m) * 4)
	assert_eq(converted.deploy_min_width_m, int(converted.slot_pitch_m) * 4 + int(converted.body_radius_m) * 2)
	assert_eq(converted.deploy_min_depth_m, int(converted.slot_pitch_m) + int(converted.body_radius_m) * 2)

func test_configured_stature_and_terrain_tilt_are_conservative() -> void:
	var tool: Script = load(TOOL)
	var art := {"repo": SuiteData.repo(), "fov_deg": 45.0, "view_h_px": 1080.0,
		"ref_m": 25000.0, "world_per_sim_m": 1.0, "max_stature": 1.1, "max_tilt_deg": 90.0}
	var result: Dictionary = tool.call("measure", _scene(), art)
	var k := float(result.scale_inputs.simulation_scale)
	# Farthest corner is (4, 1, 2); free tilt turns its full length horizontal.
	assert_almost_eq(float(result.radius_m), sqrt(21.0) * k * 1.1, 0.001)

func test_attack_weapon_vertices_are_separate_from_body() -> void:
	var tool: Script = load(TOOL)
	var art := {"repo": SuiteData.repo(), "fov_deg": 45.0, "view_h_px": 1080.0,
		"ref_m": 25000.0, "world_per_sim_m": 1.0, "attack_bones": ["Sword"]}
	var result: Dictionary = tool.call("measure", _skin_scene(true), art)
	var k := float(result.scale_inputs.simulation_scale)
	assert_almost_eq(float(result.radius_m), 9.0 * k, 0.001)
	assert_gt(float(result.get("all_mesh_radius_m", 0)), 99.0 * k)

func test_sidecar_only_change_invalidates_model_fingerprint() -> void:
	var run_dir: Script = preload("res://tests/run_dir.gd")
	var path: String = run_dir.dir("unit-body-fingerprint").path_join("fixture.tscn")
	assert_eq(ResourceSaver.save(_scene(), path), OK)
	var scene := load(path) as PackedScene
	var source_hash := FileAccess.get_sha256(path)
	var file := FileAccess.open(path + ".import", FileAccess.WRITE)
	file.store_string("[params]\nanimation/import=true\n")
	file.close()
	var before := _measure(scene)
	file = FileAccess.open(path + ".import", FileAccess.WRITE)
	file.store_string("[params]\nanimation/import=false\n")
	file.close()
	var after := _measure(scene)
	assert_eq(FileAccess.get_sha256(path), source_hash, "Only importer settings changed")
	assert_eq(after.radius_m, before.radius_m, "Loaded fixture geometry is unchanged")
	assert_ne(after.model_hash, before.model_hash, "Import-only edits must invalidate model evidence")
