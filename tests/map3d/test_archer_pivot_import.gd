extends GutTest
## Generated GLB, independent of the unmerged archer clips. No editor-class skips.

const PROVIDER: String = "res://tools/units3d/archer_arp/pivot_import.gd"
const OLD: Array[String] = ["STANDBY", "MARCH", "SPRINT", "DRAW", "GARRISON", "DEATH"]
const TIMES: Array[float] = [0.0, .03125, 1.0 / 30.0, .487, 1.0]
var _files: Array[String] = []
var _directories: Array[String] = []
var _bin: PackedByteArray
var _json: Dictionary


func after_each() -> void:
	for path: String in _files:
		DirAccess.remove_absolute(path)
	_files.clear()
	for path: String in _directories:
		_remove_tree(path)
	_directories.clear()


func _accessor(values: Array, width: int, kind: String) -> int:
	var start: int = _bin.size()
	for value: float in values:
		var bytes := PackedByteArray()
		bytes.resize(4)
		bytes.encode_float(0, value)
		_bin.append_array(bytes)
	var view: int = _json.bufferViews.size()
	_json.bufferViews.append({"buffer": 0, "byteOffset": start, "byteLength": _bin.size() - start})
	var index: int = _json.accessors.size()
	_json.accessors.append({"bufferView": view, "componentType": 5126, "count": values.size() / width, "type": kind})
	return index


func _channel(animation: Dictionary, node: int, path: String, values: Array, times: Array = TIMES) -> void:
	var width: int = 4 if path == "rotation" else 3
	var input: int = _accessor(times, 1, "SCALAR")
	var output: int = _accessor(values, width, "VEC4" if width == 4 else "VEC3")
	animation.channels.append({"sampler": animation.samplers.size(), "target": {"node": node, "path": path}})
	animation.samplers.append({"input": input, "output": output, "interpolation": "LINEAR"})


func _fixture(mode: String = "pair") -> String:
	_bin = PackedByteArray()
	_json = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"name": "Fixture", "nodes": [0]}],
		"nodes": [{"name": "Rig", "children": [1, 4]}, {"name": "root", "children": [2]},
			{"name": "foot", "translation": [.2, .1, -.3], "scale": [1.1, .9, 1.2], "children": [3]},
			{"name": "toe", "translation": [0, 0, -.12]}, {"name": "Body", "mesh": 0, "skin": 0}],
		"skins": [{"joints": [1, 2, 3], "skeleton": 1}], "buffers": [], "bufferViews": [], "accessors": [], "animations": []}
	var positions: int = _accessor([0, 0, 0, .1, 0, 0, 0, .1, 0], 3, "VEC3")
	_json.accessors[positions].min = [0, 0, 0]
	_json.accessors[positions].max = [.1, .1, 0]
	var weights: int = _accessor([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4, "VEC4")
	var joint_view: int = _json.bufferViews.size()
	var offset: int = _bin.size()
	_bin.resize(offset + 24)
	for i: int in range(12):
		_bin.encode_u16(offset + i * 2, 1 if i % 4 == 0 else 0)
	_json.bufferViews.append({"buffer": 0, "byteOffset": offset, "byteLength": 24})
	var joints: int = _json.accessors.size()
	_json.accessors.append({"bufferView": joint_view, "componentType": 5123, "count": 3, "type": "VEC4"})
	_json.meshes = [{"primitives": [{"attributes": {"POSITION": positions, "JOINTS_0": joints, "WEIGHTS_0": weights}}]}]
	for name: String in OLD + (["PIVOT_LEFT", "PIVOT_RIGHT"] if mode != "absent" else []):
		if mode == "partial" and name == "PIVOT_RIGHT":
			continue
		var animation: Dictionary = {"name": name, "samplers": [], "channels": []}
		var root_rot: Array = []
		var foot_rot: Array = []
		var foot_pos: Array = []
		for time: float in TIMES:
			var angle: float = time * (.7 if name == "PIVOT_LEFT" else -.7)
			var q := Quaternion(Vector3.UP, angle)
			root_rot.append_array([q.x, q.y, q.z, q.w])
			q = q.inverse()
			foot_rot.append_array([q.x, q.y, q.z, q.w])
			var pos: Vector3 = Basis(q) * Vector3(.2, .1, -.3)
			foot_pos.append_array([pos.x, pos.y, pos.z])
		_channel(animation, 1, "rotation", root_rot)
		_channel(animation, 2, "translation", foot_pos)
		_channel(animation, 2, "rotation", foot_rot)
		_channel(animation, 2, "scale", [1.1, .9, 1.2, 1.1, .9, 1.2], [0.0, 1.0])
		_channel(animation, 3, "translation", [0, 0, -.12, 0, 0, -.12], [0.0, 1.0])
		_json.animations.append(animation)
	if mode == "unsupported":
		_json.animations[-1].samplers[0].interpolation = "CUBICSPLINE"
	if mode == "step":
		_json.animations[-1].samplers[0].interpolation = "STEP"
	if mode == "dynamic_missing":
		_json.animations[-1].channels.remove_at(1)
	if mode == "duplicate":
		_json.animations.append(_json.animations[-2].duplicate(true))
	if mode in ["nan", "descending", "nonunit"]:
		var sampler: Dictionary = _json.animations[-1].samplers[0]
		var accessor: Dictionary = _json.accessors[sampler.output if mode == "nonunit" else sampler.input]
		var view: Dictionary = _json.bufferViews[accessor.bufferView]
		_bin.encode_float(int(view.byteOffset) + (12 if mode == "nonunit" else 4), 2.0 if mode == "nonunit" else (NAN if mode == "nan" else 0.0))
	if mode == "malformed":
		_json.accessors[_json.animations[-1].samplers[0].output].count = 999999
	_json.buffers = [{"byteLength": _bin.size()}]
	var json_bytes: PackedByteArray = JSON.stringify(_json).to_utf8_buffer()
	while json_bytes.size() % 4:
		json_bytes.append(32)
	var bytes := PackedByteArray()
	bytes.resize(20)
	bytes.encode_u32(0, 0x46546c67)
	bytes.encode_u32(4, 2)
	bytes.encode_u32(8, 28 + json_bytes.size() + _bin.size())
	bytes.encode_u32(12, json_bytes.size())
	bytes.encode_u32(16, 0x4e4f534a)
	bytes.append_array(json_bytes)
	var header := PackedByteArray()
	header.resize(8)
	header.encode_u32(0, _bin.size())
	header.encode_u32(4, 0x004e4942)
	bytes.append_array(header)
	bytes.append_array(_bin)
	var path: String = "user://pivot_import_" + mode + ".glb"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	_files.append(path)
	return path


func _import(path: String) -> Node:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert_eq(document.append_from_file(path, state), OK)
	var scene: Node = document.generate_scene(state, 30.0, false, true)
	for name: StringName in _player(scene).get_animation_list():
		_player(scene).get_animation(name).optimize()
		if str(name) in ["STANDBY", "MARCH", "SPRINT", "GARRISON"]:
			_player(scene).get_animation(name).loop_mode = Animation.LOOP_LINEAR
	return scene


func _player(scene: Node) -> AnimationPlayer:
	return scene.find_children("*", "AnimationPlayer", true, false)[0]


func _run(scene: Node, path: String) -> Dictionary:
	var script: Script = load(PROVIDER)
	assert_not_null(script)
	return script.process(scene, path)


func test_pair_preserves_source_times_and_full_affine_contacts_without_touching_old_resources() -> void:
	var path: String = _fixture()
	var scene: Node = _import(path)
	var player: AnimationPlayer = _player(scene)
	var old: Dictionary = {}
	for name: String in OLD:
		old[name] = player.get_animation(name)
	var result: Dictionary = _run(scene, path)
	assert_true(result.ok, str(result))
	assert_same(result.scene, scene)
	for name: String in OLD:
		assert_same(player.get_animation(name), old[name], name)
	for name: String in ["PIVOT_LEFT", "PIVOT_RIGHT"]:
		var clip: Animation = player.get_animation(name)
		assert_eq(clip.loop_mode, Animation.LOOP_NONE)
		assert_eq(clip.length, 1.0)
		var track: int = -1
		for i: int in range(clip.get_track_count()):
			if clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and str(clip.track_get_path(i)).ends_with(":root"):
				track = i
		assert_gte(track, 0)
		if track >= 0:
			assert_eq(clip.track_get_key_count(track), TIMES.size(), "source key count")
			for i: int in range(mini(TIMES.size(), clip.track_get_key_count(track))):
				assert_almost_eq(clip.track_get_key_time(track, i), TIMES[i], .0000001, "nonuniform source times")
	scene.free()


func _snapshot(player: AnimationPlayer) -> Dictionary:
	var out: Dictionary = {}
	for name: StringName in player.get_animation_list():
		var clip: Animation = player.get_animation(name)
		var tracks: Array = []
		for i: int in range(clip.get_track_count()):
			var keys: Array = []
			for k: int in range(clip.track_get_key_count(i)):
				keys.append([clip.track_get_key_time(i, k), clip.track_get_key_value(i, k), clip.track_get_key_transition(i, k)])
			tracks.append([clip.track_get_type(i), clip.track_get_path(i), clip.track_get_interpolation_type(i),
				clip.track_get_interpolation_loop_wrap(i), clip.track_is_enabled(i), clip.track_is_imported(i), keys])
		out[name] = [clip, clip.length, clip.loop_mode, clip.step, tracks]
	return out


func _hierarchy(scene: Node) -> Array:
	var out: Array = []
	for node: Node in [scene] + scene.find_children("*", "", true, false):
		var row: Array = [node, node.name, node.get_parent(), node.get_script()]
		if node is Node3D:
			row.append(node.transform)
		if node is MeshInstance3D:
			row.append_array([node.mesh, node.skin, node.skeleton, node.material_override])
			if node.mesh != null:
				for surface: int in range(node.mesh.get_surface_count()):
					row.append([node.mesh.surface_get_arrays(surface).duplicate(true), node.mesh.surface_get_material(surface), node.get_surface_override_material(surface)])
			if node.skin != null:
				for bind: int in range(node.skin.get_bind_count()):
					row.append([node.skin.get_bind_name(bind), node.skin.get_bind_bone(bind), node.skin.get_bind_pose(bind)])
		if node is Skeleton3D:
			for bone: int in range(node.get_bone_count()):
				row.append([node.get_bone_name(bone), node.get_bone_parent(bone), node.get_bone_rest(bone)])
		out.append(row)
	return out


func _matrix(actual: Transform3D, expected: Transform3D, label: String) -> void:
	assert_lt(actual.origin.distance_to(expected.origin), .00001, label + " origin")
	for axis: int in range(3):
		assert_lt(actual.basis[axis].distance_to(expected.basis[axis]), .00001, label + " full affine")


func test_source_key_poses_contacts_and_static_components_reach_real_skeleton() -> void:
	var path: String = _fixture()
	var scene: Node = _import(path)
	var structure: Array = _hierarchy(scene)
	var snapshot: Dictionary = _snapshot(_player(scene))
	var result: Dictionary = _run(scene, path)
	assert_true(result.ok, str(result))
	assert_eq(_hierarchy(scene), structure, "provider never replaces hierarchy/mesh/skin/rest")
	for name: String in OLD:
		assert_eq(_snapshot(_player(scene))[name], snapshot[name], name + " complete old native curves")
	add_child(scene)
	var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = _player(scene)
	for name: String in ["PIVOT_LEFT", "PIVOT_RIGHT"]:
		player.play(name)
		for time: float in TIMES:
			player.seek(time, true)
			var angle: float = time * (.7 if name == "PIVOT_LEFT" else -.7)
			var root := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
			var foot := Transform3D(Basis.IDENTITY.scaled(Vector3(1.1, .9, 1.2)), Vector3(.2, .1, -.3))
			_matrix(skeleton.get_bone_global_pose(skeleton.find_bone("root")), root, name)
			_matrix(skeleton.get_bone_global_pose(skeleton.find_bone("foot")), foot, "planted foot")
			_matrix(skeleton.get_bone_global_pose(skeleton.find_bone("toe")), foot * Transform3D(Basis.IDENTITY, Vector3(0, 0, -.12)), "toe contact")
	remove_child(scene)
	scene.free()


func test_absent_pair_is_same_scene_and_same_animations() -> void:
	var path: String = _fixture("absent")
	var scene: Node = _import(path)
	var before: Dictionary = _snapshot(_player(scene))
	var result: Dictionary = _run(scene, path)
	assert_true(result.ok, str(result))
	assert_same(result.scene, scene)
	assert_eq(_snapshot(_player(scene)), before)
	scene.free()


func test_partial_malformed_and_unsupported_pairs_reject_without_publishing_either_clip() -> void:
	var scene: Node = _import(_fixture())
	var before: Dictionary = _snapshot(_player(scene))
	var hierarchy: Array = _hierarchy(scene)
	for mode: String in ["partial", "malformed", "unsupported", "dynamic_missing", "duplicate", "nan", "descending", "nonunit"]:
		var result: Dictionary = _run(scene, _fixture(mode))
		assert_false(result.ok, mode)
		assert_false(str(result.error).is_empty())
		assert_eq(_snapshot(_player(scene)), before, mode + " atomic resources")
		assert_eq(_hierarchy(scene), hierarchy)
	scene.free()


func test_path_and_native_rest_disagreement_reject_atomically() -> void:
	var path: String = _fixture()
	for mode: String in ["path", "rest", "nan_rest"]:
		var scene: Node = _import(path)
		var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		if mode == "path":
			skeleton.name = "WrongNativePath"
		elif mode == "nan_rest":
			var bad: Transform3D = skeleton.get_bone_rest(1)
			bad.origin.x = NAN
			skeleton.set_bone_rest(1, bad)
		else:
			skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(5, 4, 3)))
		var before: Dictionary = _snapshot(_player(scene))
		var hierarchy: Array = _hierarchy(scene)
		var result: Dictionary = _run(scene, path)
		assert_false(result.ok, mode)
		assert_eq(_snapshot(_player(scene)), before)
		if mode == "nan_rest":
			assert_true(is_nan(skeleton.get_bone_rest(1).origin.x), "reject rather than launder invalid rest")
		else:
			assert_eq(_hierarchy(scene), hierarchy)
		scene.free()


func test_success_and_rejection_free_all_temporary_native_nodes() -> void:
	var path: String = _fixture()
	var scene: Node = _import(path)
	# Warm script/resource loading before the orphan count, with no tree scheduling.
	var result: Dictionary = _run(scene, path)
	assert_true(result.ok, str(result))
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i: int in range(3):
		assert_true(_run(scene, path).ok)
		var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var name_before: StringName = skeleton.name
		skeleton.name = "BadPath"
		assert_false(_run(scene, path).ok)
		skeleton.name = name_before
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), before, "no temporary generated scene leaks")
	scene.free()


func test_dynamic_track_cannot_be_dropped_or_replaced_with_a_rest_padding_track() -> void:
	var path: String = _fixture()
	var scene: Node = _import(path)
	var clip: Animation = _player(scene).get_animation("PIVOT_RIGHT")
	clip.track_set_path(0, NodePath("MissingSkeleton:root"))
	var before: Dictionary = _snapshot(_player(scene))
	assert_false(_run(scene, path).ok)
	assert_eq(_snapshot(_player(scene)), before)
	scene.free()


func test_missing_static_components_are_padded_from_unchanged_native_rest() -> void:
	var path: String = _fixture()
	var scene: Node = _import(path)
	var result: Dictionary = _run(scene, path)
	assert_true(result.ok, str(result))
	var clip: Animation = _player(scene).get_animation("PIVOT_LEFT")
	var padded: bool = false
	for i: int in range(clip.get_track_count()):
		if clip.track_get_type(i) == Animation.TYPE_POSITION_3D and str(clip.track_get_path(i)).ends_with(":root"):
			padded = true
			for k: int in range(clip.track_get_key_count(i)):
				assert_eq(clip.track_get_key_value(i, k), Vector3.ZERO)
	assert_true(padded, "source root has no translation channel; pad only its native static rest")
	scene.free()


func _remove_tree(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for directory: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(directory))
	DirAccess.remove_absolute(path)


func test_real_editor_import_callback_uses_source_file_and_replaces_only_the_pair() -> void:
	# The parent runner owns the shared Godot lock; these children run serially inside it.
	var directory: String = "user://pivot_editor_" + str(OS.get_process_id())
	_directories.append(directory)
	DirAccess.make_dir_recursive_absolute(directory)
	var project := FileAccess.open(directory.path_join("project.godot"), FileAccess.WRITE)
	project.store_string('config_version=5\n[application]\nconfig/name="Pivot callback fixture"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
	project.close()
	assert_eq(DirAccess.copy_absolute(_fixture(), directory.path_join("fixture.glb")), OK)
	assert_eq(DirAccess.copy_absolute(PROVIDER, directory.path_join("pivot_import.gd")), OK)
	var output: Array = []
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path(directory), "--import"])
	assert_eq(OS.execute(OS.get_executable_path(), arguments, output, true), 0, str(output))
	var config := ConfigFile.new()
	assert_eq(config.load(directory.path_join("fixture.glb.import")), OK)
	config.set_value("params", "import_script/path", "res://pivot_import.gd")
	assert_eq(config.save(directory.path_join("fixture.glb.import")), OK)
	# Headless scanning does not treat an edited .import option as a reimport request.
	var cached: String = directory.path_join(str(config.get_value("remap", "path")).trim_prefix("res://"))
	assert_eq(DirAccess.remove_absolute(cached), OK)
	var checksum: String = cached.get_basename() + ".md5"
	if FileAccess.file_exists(checksum):
		assert_eq(DirAccess.remove_absolute(checksum), OK)
	output.clear()
	assert_eq(OS.execute(OS.get_executable_path(), arguments, output, true), 0, str(output))
	assert_false(str(output).contains("SCRIPT ERROR:"), str(output))
	assert_eq(config.load(directory.path_join("fixture.glb.import")), OK)
	var imported_path: String = directory.path_join(str(config.get_value("remap", "path")).trim_prefix("res://"))
	var packed: PackedScene = load(imported_path)
	assert_not_null(packed)
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	var player: AnimationPlayer = _player(scene)
	for name: String in OLD:
		assert_true(player.has_animation(name), name)
	for name: String in ["PIVOT_LEFT", "PIVOT_RIGHT"]:
		var clip: Animation = player.get_animation(name)
		var found: bool = false
		for track: int in range(clip.get_track_count()):
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D and str(clip.track_get_path(track)).ends_with(":root"):
				found = true
				assert_eq(clip.track_get_key_count(track), TIMES.size(), "actual callback retains exact source keys: " + str(output))
				assert_almost_eq(clip.track_get_key_time(track, 1), .03125, .0000001)
		assert_true(found, "callback must retain the root track")
	scene.free()


func test_step_source_interpolation_stays_step_at_its_nonuniform_source_times() -> void:
	var path: String = _fixture("step")
	var scene: Node = _import(path)
	var result: Dictionary = _run(scene, path)
	assert_true(result.ok, str(result))
	var clip: Animation = _player(scene).get_animation("PIVOT_RIGHT")
	for i: int in range(clip.get_track_count()):
		if clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and str(clip.track_get_path(i)).ends_with(":root"):
			assert_eq(clip.track_get_interpolation_type(i), Animation.INTERPOLATION_NEAREST)
			var actual: Quaternion = clip.rotation_track_interpolate(i, .04)
			_matrix(Transform3D(Basis(actual), Vector3.ZERO), Transform3D(Basis(Vector3.UP, -.7 / 30.0), Vector3.ZERO), "STEP source value")
	scene.free()


func test_nonpivot_animation_in_another_library_keeps_identity_and_every_key() -> void:
	var path: String = _fixture()
	var scene: Node = _import(path)
	var player: AnimationPlayer = _player(scene)
	var library := AnimationLibrary.new()
	var other := Animation.new()
	other.loop_mode = Animation.LOOP_PINGPONG
	other.length = 7.3
	var track: int = other.add_track(Animation.TYPE_VALUE)
	other.track_set_path(track, NodePath(".:visible"))
	other.track_insert_key(track, .317, false)
	other.track_insert_key(track, 5.29, true)
	library.add_animation("OTHER", other)
	player.add_animation_library("extras", library)
	var snapshot: Dictionary = _snapshot(player)
	assert_true(_run(scene, path).ok)
	assert_same(player.get_animation_library("extras"), library)
	assert_eq(_snapshot(player)["extras/OTHER"], snapshot["extras/OTHER"])
	scene.free()
