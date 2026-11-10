extends SceneTree
## Samples the imported infantry clips with the real AnimationPlayer (pivot_mapping.py input).
## Godot --headless --path . -s tools/units3d/soldier_arp/pivot_native.gd -- REQUEST.json OUT.json
## REQUEST: {"clip": "MARCH", "samples": [{"id": <exact float hex>, "phase": <0..1>}]}.
## OUT: skeleton-space bone globals per sample; no interpolation outside the player.

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
