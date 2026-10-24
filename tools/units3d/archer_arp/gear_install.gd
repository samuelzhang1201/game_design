extends SceneTree
## Extract gear meshes through Godot; install only the explicitly selected candidate.
## Godot --path . --script res://tools/units3d/archer_arp/gear_install.gd -- WORK [--install proposed]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() in [1, 3], "WORK [--install proposed|conservative]")
	var work := args[0]
	var install := ""
	if args.size() == 3:
		assert(args[1] == "--install" and args[2] in ["proposed", "conservative"])
		install = args[2]
	var model: Node = load("res://scenes/models/units/archers.tscn").instantiate()
	for variant: String in ["conservative", "proposed"]:
		for part: String in ["bow", "arrow", "quiver"]:
			var directory := work.path_join(variant)
			var state := GLTFState.new()
			var document := GLTFDocument.new()
			assert(document.append_from_file(directory.path_join("archers_" + part + ".glb"), state) == OK)
			var imported := document.generate_scene(state)
			var sources := imported.find_children("*", "MeshInstance3D", true, false)
			assert(sources.size() == 1)
			var source := sources[0] as MeshInstance3D
			var original := model.find_child("archers_" + part, true, false) as MeshInstance3D
			var palette: Array[int] = []
			for index in source.skin.get_bind_count():
				var name := source.skin.get_bind_name(index)
				if name == &"":
					var skeleton := source.get_node(source.skeleton) as Skeleton3D
					name = skeleton.get_bone_name(source.skin.get_bind_bone(index))
				var target := -1
				for j in original.skin.get_bind_count():
					if original.skin.get_bind_name(j) == name:
						target = j
				assert(target >= 0, "unexpected skin bind: " + name)
				palette.append(target)
			var arrays := source.mesh.surface_get_arrays(0)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for index in bones.size():
				assert(bones[index] < palette.size())
				bones[index] = palette[bones[index]]
			arrays[Mesh.ARRAY_BONES] = bones
			var result := ImporterMesh.new()
			var flags: int = source.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			result.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", flags)
			result.generate_lods(60, 60, [])
			var mesh := result.get_mesh()
			mesh.resource_name = original.mesh.resource_name
			assert(ResourceSaver.save(mesh, directory.path_join("archers_" + part + ".res"), ResourceSaver.FLAG_COMPRESS) == OK)
			print("EXTRACTED ", variant, " ", part, " triangles=", arrays[Mesh.ARRAY_INDEX].size()/3, " palette=", palette)
			if install == variant:
				var destination := "res://assets/3D/units/archers/archers_" + part + ".res"
				var uid := ResourceLoader.get_resource_uid(destination)
				assert(ResourceSaver.save(mesh, destination, ResourceSaver.FLAG_COMPRESS) == OK)
				assert(ResourceSaver.set_uid(destination, uid) == OK)
				assert(DirAccess.copy_absolute(directory.path_join("archers_" + part + ".glb"),
					ProjectSettings.globalize_path("res://assets/3D/units/archers/archers_" + part + ".glb")) == OK)
				var material := original.get_surface_override_material(0) as StandardMaterial3D
				for channel: String in ["base", "mr", "normal"]:
					if part == "quiver" and channel == "mr":
						continue
					var texture: Texture2D = material.albedo_texture if channel == "base" else (
						material.normal_texture if channel == "normal" else material.roughness_texture)
					assert(texture != null and texture.resource_path.begins_with("res://assets/3D/units/archers/"))
					assert(DirAccess.copy_absolute(directory.path_join(part + "_" + channel + ".jpg"),
						ProjectSettings.globalize_path(texture.resource_path)) == OK)
			imported.free()
	model.free()
	quit()
