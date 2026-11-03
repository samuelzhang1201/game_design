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


func _track_values(animation: Animation, time: float) -> Array:
	var values: Array = []
	for i: int in animation.get_track_count():
		match animation.track_get_type(i):
			Animation.TYPE_POSITION_3D:
				values.append(_vector(animation.position_track_interpolate(i, time)))
			Animation.TYPE_ROTATION_3D:
				values.append(_vector(animation.rotation_track_interpolate(i, time)))
			Animation.TYPE_SCALE_3D:
				values.append(_vector(animation.scale_track_interpolate(i, time)))
	return values


func _track_records(animation: Animation) -> Array:
	var tracks: Array = []
	for i: int in animation.get_track_count():
		var keys: Array = []
		for j: int in animation.track_get_key_count(i):
			keys.append({"time": animation.track_get_key_time(i, j), "value": _vector(animation.track_get_key_value(i, j)),
				"transition": animation.track_get_key_transition(i, j)})
		tracks.append({"path": str(animation.track_get_path(i)), "type": animation.track_get_type(i),
			"interpolation": animation.track_get_interpolation_type(i), "compressed": animation.track_is_compressed(i),
			"loop_wrap": animation.track_get_interpolation_loop_wrap(i), "enabled": animation.track_is_enabled(i), "keys": keys})
	return tracks


func _import_trace(output: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SOURCE + ".import") != OK:
		return {"error": "Cannot read installed import configuration"}
	var subresources: Dictionary = config.get_value("params", "_subresources", {})
	# This bounded replay handles this asset's default AnimationPlayer import settings.
	if not subresources.get("nodes", {}).is_empty():
		return {"error": "Node import overrides require explicit replay accounting"}
	var settings: Dictionary = {"bake_fps": config.get_value("params", "animation/fps"),
		"trimming": config.get_value("params", "animation/trimming"),
		"remove_immutable_tracks": config.get_value("params", "animation/remove_immutable_tracks"),
		"optimizer/enabled": true, "optimizer/max_velocity_error": 0.01,
		"optimizer/max_angular_error": 0.01, "optimizer/max_precision_error": 3,
		"compression/enabled": false, "import_tracks/mode": 1, "generate_scene/remove_immutable_tracks": false, "source": "pinned ResourceImporterScene INTERNAL_IMPORT_CATEGORY_ANIMATION_NODE defaults; no node overrides"}
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(SOURCE, state) != OK:
		return {"error": "Cannot decode frozen GLB for import replay"}
	var generated: Node = document.generate_scene(state, float(settings.bake_fps), bool(settings.trimming), false)
	if generated == null:
		return {"error": "Native GLTF scene generation failed"}
	var player: AnimationPlayer = generated.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = generated.find_children("*", "Skeleton3D", true, false)[0]
	var initialization: Dictionary = {}
	for node: GLTFNode in state.get_nodes():
		var bone: int = skeleton.find_bone(node.resource_name)
		if bone >= 0:
			initialization[node.resource_name] = {"original_name": node.original_name,
				"node_transform": _flat(node.xform), "rest_transform": _flat(node.get_additional_data("GODOT_rest_transform")),
				"generated_rest": _flat(skeleton.get_bone_rest(bone)),
				"position": _vector(skeleton.get_bone_pose_position(bone)),
				"rotation": _vector(skeleton.get_bone_pose_rotation(bone)),
				"scale": _vector(skeleton.get_bone_pose_scale(bone))}
	var generated_tracks: Dictionary = {}
	var used_tracks: Dictionary = {}
	var defaults: Dictionary = {}
	for animation_name: StringName in player.get_animation_list():
		var candidate: Animation = player.get_animation(animation_name)
		generated_tracks[str(animation_name)] = _track_records(candidate)
		for track: int in candidate.get_track_count():
			var path: NodePath = candidate.track_get_path(track)
			var bone: int = skeleton.find_bone(path.get_subname(0))
			if bone < 0:
				generated.free()
				return {"error": "Import replay expected a named bone track"}
			var rest: Transform3D = skeleton.get_bone_rest(bone)
			var kind: int = candidate.track_get_type(track)
			var initial: Variant
			match kind:
				Animation.TYPE_POSITION_3D:
					initial = rest.origin / skeleton.motion_scale
				Animation.TYPE_ROTATION_3D:
					initial = rest.basis.get_rotation_quaternion()
				Animation.TYPE_SCALE_3D:
					initial = rest.basis.get_scale()
				_:
					generated.free()
					return {"error": "Unsupported import replay track"}
			var key: String = str(path) + "|" + str(kind)
			defaults[key] = _vector(initial)
			if not used_tracks.has(key):
				used_tracks[key] = false
			for i: int in candidate.track_get_key_count(track):
				if not candidate.track_get_key_value(track, i).is_equal_approx(initial):
					used_tracks[key] = true
	var animation: Animation = player.get_animation("MARCH")
	if settings.remove_immutable_tracks:
		for track: int in range(animation.get_track_count() - 1, -1, -1):
			var key: String = str(animation.track_get_path(track)) + "|" + str(animation.track_get_type(track))
			if not used_tracks[key]:
				animation.remove_track(track)
	var before: Array = _track_records(animation)
	animation.optimize(float(settings["optimizer/max_velocity_error"]), float(settings["optimizer/max_angular_error"]), int(settings["optimizer/max_precision_error"]))
	var after: Array = _track_records(animation)
	animation.loop_mode = Animation.LOOP_LINEAR
	var serialized_path: String = output.path_join("import-replay.res")
	if ResourceSaver.save(animation, serialized_path) != OK:
		generated.free()
		return {"error": "Cannot retain immutable serialization replay"}
	var reloaded: Animation = ResourceLoader.load(serialized_path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	var result: Dictionary = {"settings": settings, "initialization": initialization, "all_animation_baked": generated_tracks, "immutable_defaults": defaults,
		"used_tracks": used_tracks, "baked": before, "optimized": after,
		"serialized": _track_records(reloaded), "serialized_sha256": FileAccess.get_sha256(serialized_path),
		"operations": ["GLTFDocument.append_from_file", "GLTFDocument.generate_scene(remove_immutable=false)", "ResourceImporterScene cross-animation immutable removal", "Animation.optimize", "Animation loop setting", "ResourceSaver/ResourceLoader roundtrip"]}
	generated.free()
	return result


func _fail(message: String) -> void:
	push_error(message)
	quit(2)


func _capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 6 and args[0] == "--views" and args[2] == "--native" and args[4] == "--accounting":
		await _views(args[1], args[3], args[5])
		return
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
			"compressed": animation.track_is_compressed(i),
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
	var os_build: Array = []
	if OS.get_name() != "macOS" or OS.execute("/usr/bin/sw_vers", ["-buildVersion"], os_build) != 0:
		_fail("Native numerical replay requires the captured macOS build")
		return
	var static_data: Dictionary = {"version": 2, "engine": Engine.get_version_info(),
		"runtime": {"os": OS.get_name(), "build": str(os_build[0]).strip_edges(),
			"arm64": OS.has_feature("arm64"), "double_precision": OS.has_feature("double")},
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
	static_data["import_trace"] = _import_trace(output)
	if static_data.import_trace.has("error"):
		_fail(str(static_data.import_trace.error))
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
		var player_time: float = player.current_animation_position
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
			"player_time": player_time, "player_track_values": _track_values(animation, player_time),
			"locals": locals, "globals": globals, "track_values": _track_values(animation, time), "pose_components": pose_components,
			"skinned_skeleton_local": points}, "", true, true))
	samples_file.close()
	print("NATIVE_CAPTURE ", JSON.stringify({"bones": bones.size(), "surfaces": surfaces.size(),
		"samples": sample_times.size(), "output": output}))
	model.queue_free()
	quit()


func _face_surface(target: ArrayMesh, arrays: Array, faces: Array, material: Material) -> void:
	var subset: Array = arrays.duplicate()
	var indices: PackedInt32Array = []
	for face: int in faces:
		for corner: int in 3:
			indices.append(arrays[Mesh.ARRAY_INDEX][face * 3 + corner])
	subset[Mesh.ARRAY_INDEX] = indices
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, subset)
	target.surface_set_material(target.get_surface_count() - 1, material)


func _views(output: String, native_path: String, accounting_path: String) -> void:
	if DisplayServer.get_name() == "headless" or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):
		_fail("Views require a normal renderer/window and a new absolute output directory")
		return
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(native_path))
	var accounting: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(accounting_path))
	for path: String in native.input_hashes:
		if FileAccess.get_sha256("res://" + path) != native.input_hashes[path]:
			_fail("View resource differs from native capture: " + path)
			return
	root.size = Vector2i(2560, 1600)
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.001
	camera.current = true
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	root.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-50, -30, 0)
	var names: Array[String] = ["FrontHoof.L", "FrontHoof.R", "HindHoof.L", "HindHoof.R"]
	var labels: Image = Image.create(256, 83, false, Image.FORMAT_R8)
	labels.fill(Color.BLACK)
	for part: int in names.size():
		for vertex: int in accounting.patches[names[part]].native_shell_vertices:
			labels.set_pixel(vertex % 256, vertex / 256, Color(float(part + 1) / 255.0, 0, 0))
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D parts : filter_nearest;
varying flat int part;
void vertex() { part = int(round(texelFetch(parts, ivec2(VERTEX_ID % 256, VERTEX_ID / 256), 0).r * 255.0)); }
void fragment() {
 ALBEDO = part == 1 ? vec3(1.0,0.2,0.15) : part == 2 ? vec3(0.1,0.65,1.0) :
          part == 3 ? vec3(0.95,0.7,0.1) : part == 4 ? vec3(0.25,0.85,0.35) : vec3(0.3);
}
"""
	material.set_shader_parameter("parts", ImageTexture.create_from_image(labels))
	var wire: MeshInstance3D = MeshInstance3D.new()
	root.add_child(wire)
	var wire_material: StandardMaterial3D = StandardMaterial3D.new()
	wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_material.no_depth_test = true
	wire_material.albedo_color = Color(1, 0, 1)
	wire.material_override = wire_material
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("Cannot create view directory")
		return
	var rows: Array = []
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var original_material: Material = mesh.get_active_material(0)
	if original_material == null:
		_fail("Missing effective scene material")
		return
	var isolated: MeshInstance3D = MeshInstance3D.new()
	mesh.get_parent().add_child(isolated)
	isolated.transform = mesh.transform
	isolated.skin = mesh.skin
	isolated.skeleton = isolated.get_path_to(skeleton)
	var classified: MeshInstance3D = MeshInstance3D.new()
	mesh.get_parent().add_child(classified)
	classified.transform = mesh.transform
	classified.skin = mesh.skin
	classified.skeleton = classified.get_path_to(skeleton)
	var region_materials: Dictionary = {}
	for kind: String in ["bottom", "rim", "wall"]:
		var region: StandardMaterial3D = StandardMaterial3D.new()
		region.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		region.cull_mode = BaseMaterial3D.CULL_DISABLED
		region.albedo_color = Color(0.1, 0.6, 1.0) if kind == "bottom" else Color(1.0, 0.7, 0.1) if kind == "rim" else Color(0.45, 0.45, 0.45)
		region_materials[kind] = region
	for phase: float in [0.0, 0.137]:
		player.stop()
		for i: int in native.bones.size():
			var bone: Dictionary = native.bones[i]
			skeleton.set_bone_pose_position(i, Vector3(bone.default_position[0], bone.default_position[1], bone.default_position[2]))
			skeleton.set_bone_pose_rotation(i, Quaternion(bone.default_rotation[0], bone.default_rotation[1], bone.default_rotation[2], bone.default_rotation[3]))
			skeleton.set_bone_pose_scale(i, Vector3(bone.default_scale[0], bone.default_scale[1], bone.default_scale[2]))
		player.play("MARCH")
		player.seek(phase * player.get_animation("MARCH").length, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var transforms: Array[Transform3D] = []
		for i: int in native.skin.size():
			transforms.append(skeleton.get_bone_global_pose(int(native.skin[i].resolved_bone)) * mesh.skin.get_bind_pose(i))
		var points: PackedVector3Array = []
		for i: int in arrays[Mesh.ARRAY_VERTEX].size():
			var point: Vector3 = Vector3.ZERO
			for j: int in 4:
				point += (transforms[arrays[Mesh.ARRAY_BONES][i * 4 + j]] * arrays[Mesh.ARRAY_VERTEX][i]) * arrays[Mesh.ARRAY_WEIGHTS][i * 4 + j]
			points.append(skeleton.global_transform * point)
		for name: String in names:
			var patch: Dictionary = accounting.patches[name]
			var bounds: AABB = AABB(points[patch.native_shell_vertices[0]], Vector3.ZERO)
			for vertex: int in patch.native_shell_vertices:
				bounds = bounds.expand(points[vertex])
			var shell_mesh: ArrayMesh = ArrayMesh.new()
			_face_surface(shell_mesh, arrays, patch.native_shell_triangles, original_material)
			isolated.mesh = shell_mesh
			var class_mesh: ArrayMesh = ArrayMesh.new()
			for kind: String in ["bottom", "rim", "wall"]:
				_face_surface(class_mesh, arrays, patch["native_" + kind + "_triangles"], region_materials[kind])
			classified.mesh = class_mesh
			var boundary_lines: ImmediateMesh = ImmediateMesh.new()
			boundary_lines.surface_begin(Mesh.PRIMITIVE_LINES)
			for edge: Array in patch.native_boundary_edges:
				boundary_lines.surface_add_vertex(points[edge[0]])
				boundary_lines.surface_add_vertex(points[edge[1]])
			boundary_lines.surface_end()
			var lines: ImmediateMesh = ImmediateMesh.new()
			lines.surface_begin(Mesh.PRIMITIVE_LINES)
			for triangle: int in patch.native_candidate_triangles:
				for edge: int in 3:
					lines.surface_add_vertex(points[arrays[Mesh.ARRAY_INDEX][triangle * 3 + edge]])
					lines.surface_add_vertex(points[arrays[Mesh.ARRAY_INDEX][triangle * 3 + (edge + 1) % 3]])
			lines.surface_end()
			wire.mesh = lines
			for view: String in ["underside", "oblique", "oblique_back", "oblique_inside", "oblique_outside"]:
				var directions: Dictionary = {"underside": Vector3(0, -1, 0), "oblique": Vector3(0.7, -0.5, 0.7),
					"oblique_back": Vector3(-0.7, -0.5, -0.7), "oblique_inside": Vector3(-0.7, -0.5, 0.7),
					"oblique_outside": Vector3(0.7, -0.5, -0.7)}
				var direction: Vector3 = directions[view].normalized()
				var span: float = bounds.size.length()
				camera.size = span * 1.6
				camera.position = bounds.get_center() + direction * span * 4.0
				camera.look_at(bounds.get_center(), Vector3.FORWARD if view == "underside" else Vector3.UP)
				for mode: String in ["native", "source_parts", "candidate_edges", "isolated_material", "classification", "boundaries"]:
					mesh.visible = mode in ["native", "source_parts", "candidate_edges"]
					mesh.material_override = null if mode == "native" else material
					isolated.visible = mode in ["isolated_material", "boundaries"]
					classified.visible = mode == "classification"
					wire.visible = mode in ["candidate_edges", "boundaries"]
					wire.mesh = boundary_lines if mode == "boundaries" else lines
					for frame: int in 3:
						await process_frame
					await RenderingServer.frame_post_draw
					var filename: String = "%s-p%.3f-%s-%s.png" % [name, phase, view, mode]
					var screenshot: Image = root.get_texture().get_image()
					if screenshot.save_png(output.path_join(filename)) != OK:
						_fail("Cannot save native view")
						return
					rows.append({"file": filename, "sha256": FileAccess.get_sha256(output.path_join(filename)),
						"hoof": name, "phase": phase, "view": view, "mode": mode,
						"size": [screenshot.get_width(), screenshot.get_height()], "camera_position": _vector(camera.position),
						"camera_size": camera.size, "target": _vector(bounds.get_center())})
	var report: Dictionary = {"native_sha256": FileAccess.get_sha256(native_path),
		"accounting_sha256": FileAccess.get_sha256(accounting_path), "renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(), "rows": rows,
		"isolated_material_resource": original_material.resource_path,
		"legend": {"red": names[0], "blue": names[1], "gold": names[2], "green": names[3], "magenta": "candidate_edges: rejected negative-normal facets; boundaries: all bottom/rim/wall interfaces (X-ray)",
			"classification": "blue bottom plate; gold peripheral rim; gray wall", "isolated_material": "complete original-material hoof shell, native skin and all original vertex attributes; only index subset is isolated"},
		"limits": "Installed native mesh/skin untouched. Source-part shader changes display material only. Isolated/classified surfaces copy original native vertex attributes and skin with explicit shell/region index subsets; GPU skinning remains native. Magenta edges are an X-ray CPU-position overlay including hidden candidate triangles, not GPU displacement evidence. No terrain, seat, gameplay-scale, contact, desktop-input or FPS acceptance."}
	var report_file: FileAccess = FileAccess.open(output.path_join("views.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "", true, true))
	report_file.close()
	print("NATIVE_VIEWS ", rows.size(), " ", output)
	model.queue_free()
	quit()
