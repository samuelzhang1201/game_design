extends SceneTree
## Samples the imported infantry clips with the real AnimationPlayer (pivot_mapping.py input).
## Godot --headless --path . -s tools/units3d/soldier_arp/pivot_native.gd -- REQUEST.json OUT.json
## REQUEST: {"clip": "MARCH", "samples": [{"id": <exact float hex>, "phase": <0..1>}], "baseline": bool}.
## OUT: skeleton-space bone globals per sample; no interpolation outside the player. With
## "baseline" it also holds the imported skin (bind poses by name) and the mesh's first surface
## (vertices, 4 bones / weights per vertex, indices): pivot_mapping.py's native mesh.

func _matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x], [t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y],
		[t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z], [0.0, 0.0, 0.0, 1.0]]


func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, type)
		if found != null:
			return found
	return null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = "res://assets/3D/units/infantry/infantry.glb"
	var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var player: AnimationPlayer = _find(model, "AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = _find(model, "Skeleton3D") as Skeleton3D
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var clip: String = request.clip
	var animation: Animation = player.get_animation(clip)
	player.speed_scale = 0.0
	var result: Dictionary = {"clip": clip, "source_sha256": FileAccess.get_sha256(path),
		"import_sha256": FileAccess.get_sha256(path + ".import"), "godot": Engine.get_version_info(),
		"length_s": animation.length, "loop_mode": animation.loop_mode, "samples": []}
	if request.get("baseline", false):
		var mesh: MeshInstance3D = _find(model, "MeshInstance3D") as MeshInstance3D
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: Array = []
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			vertices.append([v.x, v.y, v.z])
		var binds: Array = []
		for i: int in mesh.skin.get_bind_count():
			var name: String = String(mesh.skin.get_bind_name(i))
			if name.is_empty():
				name = String(skeleton.get_bone_name(mesh.skin.get_bind_bone(i)))
			binds.append({"name": name, "pose": _matrix(mesh.skin.get_bind_pose(i))})
		result.binds = binds
		result.surfaces = [{"vertices": vertices, "bones": Array(arrays[Mesh.ARRAY_BONES]),
			"weights": Array(arrays[Mesh.ARRAY_WEIGHTS]), "indices": Array(arrays[Mesh.ARRAY_INDEX])}]
	for sample: Dictionary in request.samples:
		var phase: float = float(sample.phase)
		player.play(clip, 0.0)
		player.seek(animation.length * phase, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var bones: Dictionary = {}
		for bone: int in skeleton.get_bone_count():
			bones[String(skeleton.get_bone_name(bone))] = _matrix(skeleton.global_transform * skeleton.get_bone_global_pose(bone))
		result.samples.append({"id": sample.id, "requested_phase": phase,
			"observed_time_s": player.current_animation_position, "global_bones": bones})
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(result, "", true, true))
	print("PIVOT_NATIVE_COMPLETE ", result.samples.size())
	model.free()
	quit()
