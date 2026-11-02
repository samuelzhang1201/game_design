extends SceneTree
## Read-only native data capture, not a rendered-surface or contact certificate.
## --out must be a new directory. Use the shared Godot lock; see the paired Python tool.

const SOURCE: String = "res://assets/3D/units/cavalry/cavalry.glb"
const SCENE: String = "res://scenes/models/units/cavalry.tscn"


func _initialize() -> void:
	call_deferred("_capture")


func _flat(value: Transform3D) -> Array:
	return [value.basis.x.x, value.basis.y.x, value.basis.z.x, value.origin.x,
		value.basis.x.y, value.basis.y.y, value.basis.z.y, value.origin.y,
		value.basis.x.z, value.basis.y.z, value.basis.z.z, value.origin.z]


func _vector(value: Variant) -> Array:
	if value is Quaternion:
		return [value.x, value.y, value.z, value.w]
	if value is Vector2:
		return [value.x, value.y]
	return [value.x, value.y, value.z]


func _vectors(values: Variant) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(_vector(value))
	return result


func _fail(message: String) -> void:
	push_error(message)
	quit(2)


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--out" or not args[1].is_absolute_path():
		_fail("Usage: cavalry_march_capture.gd -- --out /absolute/new-directory")
		return
	var output: String = args[1]
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		_fail("Refusing to overwrite capture output")
		return
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		_fail("Current cavalry scene did not load")
		return
	var model: Node3D = packed.instantiate() as Node3D
	root.add_child(model)
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if skeletons.size() != 1 or players.size() != 1 or meshes.size() != 1:
		_fail("Expected exactly one skeleton, player and mesh")
		return
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	var player: AnimationPlayer = players[0] as AnimationPlayer
	var mesh: MeshInstance3D = meshes[0] as MeshInstance3D
	if not player.has_animation("MARCH") or mesh.skin == null:
		_fail("Missing MARCH or native Skin")
		return
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var animation: Animation = player.get_animation("MARCH")
	var bones: Array = []
	var default_positions: Array[Vector3] = []
	var default_rotations: Array[Quaternion] = []
	var default_scales: Array[Vector3] = []
	for i: int in skeleton.get_bone_count():
		default_positions.append(skeleton.get_bone_pose_position(i))
		default_rotations.append(skeleton.get_bone_pose_rotation(i))
		default_scales.append(skeleton.get_bone_pose_scale(i))
		bones.append({"name": skeleton.get_bone_name(i), "parent": skeleton.get_bone_parent(i),
			"rest": _flat(skeleton.get_bone_rest(i)), "global_rest": _flat(skeleton.get_bone_global_rest(i)),
			"rest_rotation": _vector(skeleton.get_bone_rest(i).basis.get_rotation_quaternion()),
			"default_position": _vector(skeleton.get_bone_pose_position(i)),
			"default_rotation": _vector(skeleton.get_bone_pose_rotation(i)),
			"default_scale": _vector(skeleton.get_bone_pose_scale(i))})
	var binds: Array = []
	var bind_bones: Array[int] = []
	for i: int in mesh.skin.get_bind_count():
		var name: String = str(mesh.skin.get_bind_name(i))
		var bone: int = skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(i)
		if bone < 0 or bone >= skeleton.get_bone_count():
			_fail("Unresolved native Skin bind")
			return
		bind_bones.append(bone)
		binds.append({"name": name, "bone": mesh.skin.get_bind_bone(i), "resolved_bone": bone,
			"pose": _flat(mesh.skin.get_bind_pose(i))})
	var surfaces: Array = []
	for i: int in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(i)
		surfaces.append({"vertices": _vectors(arrays[Mesh.ARRAY_VERTEX]),
			"normals": _vectors(arrays[Mesh.ARRAY_NORMAL]), "uv": _vectors(arrays[Mesh.ARRAY_TEX_UV]),
			"tangents": Array(arrays[Mesh.ARRAY_TANGENT]), "joints": Array(arrays[Mesh.ARRAY_BONES]),
			"weights": Array(arrays[Mesh.ARRAY_WEIGHTS]), "indices": Array(arrays[Mesh.ARRAY_INDEX]),
			"format": mesh.mesh.surface_get_format(i), "primitive": mesh.mesh.surface_get_primitive_type(i)})
	var tracks: Array = []
	var times: Array[float] = [0.0, animation.length]
	for i: int in animation.get_track_count():
		var keys: Array = []
		for j: int in animation.track_get_key_count(i):
			var time: float = animation.track_get_key_time(i, j)
			keys.append({"time": time, "value": _vector(animation.track_get_key_value(i, j)),
				"transition": animation.track_get_key_transition(i, j)})
			if time not in times:
				times.append(time)
		tracks.append({"path": str(animation.track_get_path(i)), "type": animation.track_get_type(i),
			"interpolation": animation.track_get_interpolation_type(i),
			"loop_wrap": animation.track_get_interpolation_loop_wrap(i),
			"enabled": animation.track_is_enabled(i), "keys": keys})
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SOURCE)
	var json_length: int = bytes.decode_u32(12)
	var source: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	var binary_start: int = 28 + json_length
	for clip: Dictionary in source.animations:
		if clip.name != "MARCH":
			continue
		for sampler: Dictionary in clip.samplers:
			var accessor: Dictionary = source.accessors[int(sampler.input)]
			var view: Dictionary = source.bufferViews[int(accessor.bufferView)]
			if accessor.componentType != 5126 or accessor.type != "SCALAR":
				_fail("Unsupported source time accessor")
				return
			for i: int in int(accessor.count):
				var offset: int = binary_start + int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0)) + i * int(view.get("byteStride", 4))
				var time: float = bytes.decode_float(offset)
				if time not in times:
					times.append(time)
	times.sort()
	var sample_times: Array[float] = times.duplicate()
	for i: int in times.size() - 1:
		for share: float in [0.25, 0.5, 0.75]:
			sample_times.append(lerpf(times[i], times[i + 1], share))
	for phase: float in [0.137, 0.25, 0.26, 0.27, 0.31, 0.45, 0.57, 0.58, 0.76, 0.999999]:
		sample_times.append(phase * animation.length)
	var search_boundaries: Array[float] = []
	for key_time: float in times:
		# Audit the pinned engine's approximate key search, not a contact error allowance.
		if key_time > 0.00001:
			search_boundaries.append(key_time - 0.00001)
		for offset: float in [-0.0000100001, -0.00001, -0.0000099999, -0.000001, 0.000001]:
			var sample: float = key_time + offset
			if sample >= 0.0 and sample <= animation.length and sample not in sample_times:
				sample_times.append(sample)
	sample_times.sort()
	var unique_times: Array[float] = []
	for time: float in sample_times:
		if unique_times.is_empty() or time != unique_times[-1]:
			unique_times.append(time)
	sample_times = unique_times
	var nodes: Array = []
	for node: Node in [model] + model.find_children("*", "Node3D", true, false):
		if node is Node3D:
			nodes.append({"path": str(model.get_path_to(node)), "transform": _flat(node.transform),
				"global_transform": _flat(node.global_transform)})
	var input_hashes: Dictionary = {}
	for path: String in [SOURCE, SOURCE + ".import", SCENE, "res://tools/units3d/archer_arp/pivot_import.gd",
		"res://tools/units3d/cavalry_march_capture.gd", "res://project.godot"]:
		input_hashes[path.trim_prefix("res://")] = FileAccess.get_sha256(path)
	for suffix: String in ["", "_mr", "_n"]:
		var path: String = "res://assets/3D/units/cavalry/cavalry_cavalry_atlas%s.jpg" % suffix
		input_hashes[path.trim_prefix("res://")] = FileAccess.get_sha256(path)
		input_hashes[(path + ".import").trim_prefix("res://")] = FileAccess.get_sha256(path + ".import")
	var static_data: Dictionary = {"version": 1, "engine": Engine.get_version_info(),
		"project_root": ProjectSettings.globalize_path("res://"),
		"engine_executable": OS.get_executable_path(), "engine_executable_sha256": FileAccess.get_sha256(OS.get_executable_path()),
		"input_hashes": input_hashes, "nodes": nodes, "bones": bones, "skin": binds,
		"mesh_global": _flat(mesh.global_transform), "skeleton_global": _flat(skeleton.global_transform),
		"mesh_to_skeleton": _flat(skeleton.global_transform.affine_inverse() * mesh.global_transform),
		"skeleton_path": str(model.get_path_to(skeleton)), "mesh_path": str(model.get_path_to(mesh)),
		"mesh_skeleton": str(mesh.skeleton), "player_root": str(player.root_node),
		"length": animation.length, "loop_mode": animation.loop_mode, "tracks": tracks,
		"surfaces": surfaces, "span_boundaries_seconds": times, "sample_times_seconds": sample_times,
		"native_search_boundaries_seconds": search_boundaries,
		"claim": "native CPU data only; no rendered or continuous bound"}
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("Cannot create capture directory")
		return
	var static_file: FileAccess = FileAccess.open(output.path_join("native.json"), FileAccess.WRITE)
	var samples_file: FileAccess = FileAccess.open(output.path_join("samples.jsonl"), FileAccess.WRITE)
	if static_file == null or samples_file == null:
		_fail("Cannot open capture files")
		return
	static_file.store_string(JSON.stringify(static_data, "", true, true))
	static_file.close()
	for time: float in sample_times:
		player.stop()
		for i: int in bones.size():
			skeleton.set_bone_pose_position(i, default_positions[i])
			skeleton.set_bone_pose_rotation(i, default_rotations[i])
			skeleton.set_bone_pose_scale(i, default_scales[i])
		player.play("MARCH")
		player.seek(time, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var locals: Array = []
		var globals: Array = []
		var pose_components: Array = []
		var track_values: Array = []
		for i: int in animation.get_track_count():
			match animation.track_get_type(i):
				Animation.TYPE_POSITION_3D:
					track_values.append(_vector(animation.position_track_interpolate(i, time)))
				Animation.TYPE_ROTATION_3D:
					track_values.append(_vector(animation.rotation_track_interpolate(i, time)))
				Animation.TYPE_SCALE_3D:
					track_values.append(_vector(animation.scale_track_interpolate(i, time)))
		var skin_transforms: Array[Transform3D] = []
		for i: int in skeleton.get_bone_count():
			locals.append(_flat(skeleton.get_bone_pose(i)))
			globals.append(_flat(skeleton.get_bone_global_pose(i)))
			pose_components.append({"position": _vector(skeleton.get_bone_pose_position(i)),
				"rotation": _vector(skeleton.get_bone_pose_rotation(i)), "scale": _vector(skeleton.get_bone_pose_scale(i))})
		for i: int in binds.size():
			skin_transforms.append(skeleton.get_bone_global_pose(bind_bones[i]) * mesh.skin.get_bind_pose(i))
		var points: Array = []
		for surface: Dictionary in surfaces:
			var vertices: Array = []
			for i: int in surface.vertices.size():
				var rest: Vector3 = Vector3(surface.vertices[i][0], surface.vertices[i][1], surface.vertices[i][2])
				var position: Vector3 = Vector3.ZERO
				for j: int in 4:
					position += (skin_transforms[int(surface.joints[i * 4 + j])] * rest) * float(surface.weights[i * 4 + j])
				vertices.append(_vector(position))
			points.append(vertices)
		samples_file.store_line(JSON.stringify({"time": time, "phase": time / animation.length,
			"locals": locals, "globals": globals, "track_values": track_values, "pose_components": pose_components,
			"skinned_skeleton_local": points}, "", true, true))
	samples_file.close()
	print("NATIVE_CAPTURE ", JSON.stringify({"bones": bones.size(), "surfaces": surfaces.size(),
		"samples": sample_times.size(), "output": output}))
	model.queue_free()
	quit()
